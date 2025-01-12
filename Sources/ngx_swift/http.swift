#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
import Foundation
import libnginx

public enum Http {
    static let postconfiguration: @convention(c) (UnsafeMutablePointer<ngx_as_lib_api_t>?, UnsafeMutableRawPointer?, OpaquePointer?) -> Int = { api, _, cf in
        api!.pointee.add_http_handler(cf, Int(NGX_HTTP_CONTENT_PHASE), handler)
    }

    static let handler: ngx_http_handler_pt = { r in
        let api = App.dummyApi.pointee.get_api_from_req(r)!
        let err = api.pointee.http_read_client_request_body(r, bodyhandler)
        if err >= NGX_HTTP_SPECIAL_RESPONSE {
            return err
        }
        return Int(NGX_DONE)
    }

    static let bodyhandler: ngx_http_client_body_handler_pt = { r in
        let api = App.dummyApi.pointee.get_api_from_req(r)!
        let locId = api.pointee.get_loc_id_from_req(r)

        let ud = Unmanaged<ContextData>.fromOpaque(api.pointee.get_upcall()!.pointee.ud).takeUnretainedValue()
        guard let handler = ud.app.httpServerHandler[locId] else {
            api.pointee.log(UInt(NGX_LOG_ERR), "unable to find handler related to the location \(locId)")
            api.pointee.http_finalize_request(r, 500)
            return
        }

        var req = HttpRequest(api: api, contextData: ud, req: r!)
        let err: Int
        do {
            err = try handler(req)
        } catch {
            req.log(.ERR, "failed to handle the request: \(error)")
            api.pointee.http_finalize_request(r, 500)
            return
        }
        if err == NGX_AGAIN {
            return
        }
        api.pointee.http_finalize_request(r, err)
    }
}

public class HttpRequest: @unchecked Sendable {
    private let api: UnsafePointer<ngx_as_lib_api_t>
    private var headersSent = false
    private let contextData: ContextData
    public var data: AnyObject? { contextData.data }
    public let req: UnsafeMutablePointer<ngx_http_request_t>

    init(api: UnsafePointer<ngx_as_lib_api_t>, contextData: ContextData, req: UnsafeMutablePointer<ngx_http_request_t>) {
        self.api = api
        self.contextData = contextData
        self.req = req
    }

    public func log(_ level: NgxLogLevel, _ message: String) {
        api.pointee.log(UInt(level.rawValue), message)
    }

    public func executeOnWorker(_ f: @escaping () -> Int) {
        let ok = contextData.queue.push(Runnable {
            let ret = f()
            if ret == NGX_AGAIN {
                return
            }
            self.api.pointee.http_finalize_request(self.req, ret)
        })
        if !ok {
            contextData.enqueueFailedCount.wrappingIncrement(ordering: .relaxed)
        }
        api.pointee.notify()
    }

    public var method: HttpMethod {
        let method = req.pointee.method
        if method & HttpMethod.UNKNOWN.rawValue != 0 {
            return .UNKNOWN
        }
        if method & HttpMethod.GET.rawValue != 0 {
            return .GET
        }
        if method & HttpMethod.HEAD.rawValue != 0 {
            return .HEAD
        }
        if method & HttpMethod.POST.rawValue != 0 {
            return .POST
        }
        if method & HttpMethod.PUT.rawValue != 0 {
            return .PUT
        }
        if method & HttpMethod.DELETE.rawValue != 0 {
            return .DELETE
        }
        if method & HttpMethod.MKCOL.rawValue != 0 {
            return .MKCOL
        }
        if method & HttpMethod.COPY.rawValue != 0 {
            return .COPY
        }
        if method & HttpMethod.MOVE.rawValue != 0 {
            return .MOVE
        }
        if method & HttpMethod.OPTIONS.rawValue != 0 {
            return .OPTIONS
        }
        if method & HttpMethod.PROPFIND.rawValue != 0 {
            return .PROPFIND
        }
        if method & HttpMethod.PROPPATCH.rawValue != 0 {
            return .PROPPATCH
        }
        if method & HttpMethod.LOCK.rawValue != 0 {
            return .LOCK
        }
        if method & HttpMethod.UNLOCK.rawValue != 0 {
            return .UNLOCK
        }
        if method & HttpMethod.PATCH.rawValue != 0 {
            return .PATCH
        }
        if method & HttpMethod.TRACE.rawValue != 0 {
            return .TRACE
        }
        if method & HttpMethod.CONNECT.rawValue != 0 {
            return .CONNECT
        }
        return .UNKNOWN
    }

    private static let emptyBody = [CChar]()
    private var _body: [CChar]?
    public var body: [CChar] {
        if let _body {
            return _body
        }
        let body = req.pointee.request_body
        guard let body else {
            _body = Self.emptyBody
            return _body!
        }
        let chain = body.pointee.bufs
        guard let chain else {
            _body = Self.emptyBody
            return _body!
        }
        var node: UnsafeMutablePointer<ngx_chain_t>? = chain
        var cap = 0
        while let n = node {
            if let buf = n.pointee.buf {
                if buf.pointee.pos == nil {
                    log(.ERR, "req body is not in memory")
                    _body = Self.emptyBody
                    return _body!
                }
                let len = buf.pointee.last - buf.pointee.pos
                cap += len
            }
            node = n.pointee.next
        }
        var copiedBody = [CChar](unsafeUninitializedCapacity: cap) { _, len in len = cap }
        copiedBody.withUnsafeMutableBufferPointer { p in
            var off = 0
            var node: UnsafeMutablePointer<ngx_chain_t>? = chain
            let base = p.baseAddress!
            while let n = node {
                if let buf = n.pointee.buf {
                    let len = buf.pointee.last - buf.pointee.pos
                    memcpy(base + off, buf.pointee.pos, len)
                    off += len
                }
                node = n.pointee.next
            }
        }
        _body = copiedBody
        return _body!
    }

    public func status(_ code: Int) {
        req.pointee.headers_out.status = UInt(code)
    }

    public func send(_ s: String, flush: Bool = false) throws {
        return try send(s, len: s.utf8CString.count - 1, flush: flush)
    }

    public func send(_ bytes: [CChar], flush: Bool = false) throws {
        return try send(bytes, len: bytes.count, flush: flush)
    }

    public func send(_ bytes: UnsafeRawPointer, len: Int, noCopy: Bool = false, flush: Bool = false) throws {
        if len <= 0 {
            throw Exception("the length must be greater than 0 when calling send(...)")
        }
        if !headersSent {
            let err = api.pointee.http_send_header(req)
            if err != 0 {
                throw Exception("send header failed: \(err)")
            }
            headersSent = true
        }

        let data: UnsafeMutableRawPointer
        if noCopy {
            data = UnsafeMutableRawPointer(mutating: bytes)
        } else {
            let xdata = api.pointee.pcalloc(req.pointee.pool, len)
            guard let xdata else {
                throw Exception("unable to allocate memory for the bytes to send: (\(len))")
            }
            memcpy(xdata, bytes, len)
            data = xdata
        }

        let bufraw = api.pointee.pcalloc(req.pointee.pool, MemoryLayout<ngx_buf_t>.stride)
        guard let bufraw else {
            throw Exception("unable to allocate memory for buf")
        }
        let buf = bufraw.assumingMemoryBound(to: ngx_buf_t.self)
        buf.pointee.pos = data
        buf.pointee.last = data.advanced(by: len)
        if noCopy {
            buf.pointee.flags |= UInt32(NGX_BUF_memory)
        } else {
            buf.pointee.flags |= UInt32(NGX_BUF_temporary)
        }
        if flush {
            buf.pointee.flags |= UInt32(NGX_BUF_flush)
        }

        let err = api.pointee.http_buf_output_filter(req, buf)
        if err != 0 {
            throw Exception("output filter failed: \(err)")
        }
    }

    public func end() throws -> Int {
        return try end(nil, len: 0)
    }

    public func end(_ s: String) throws -> Int {
        return try end(s, len: s.utf8CString.count - 1)
    }

    public func end(_ bytes: [CChar]) throws -> Int {
        return try end(bytes, len: bytes.count)
    }

    public func end(_ bytes: UnsafeRawPointer?, len: Int, noCopy: Bool = false) throws -> Int {
        if !headersSent {
            req.pointee.headers_out.content_length_n = Int64(len)
            if len == 0 {
                req.pointee.header_only = true
            }
            let err = api.pointee.http_send_header(req)
            if err != 0 {
                throw Exception("send header failed: \(err)")
            }
            headersSent = true
            if len == 0 {
                return 0
            }
        } else {
            if len == 0 {
                let buf = withUnsafeMutablePointer(to: &req.pointee.appbuf) { p in p }
                buf.pointee.flags |= UInt32(NGX_BUF_last_buf)
                let err = api.pointee.http_buf_output_filter(req, buf)
                if err != 0 {
                    throw Exception("output filter for last buf failed: \(err)")
                }
                return 0
            }
        }

        guard let bytes else {
            throw Exception("input bytes is nil, cannot be transmitted")
        }

        let data: UnsafeMutableRawPointer
        if noCopy {
            data = UnsafeMutableRawPointer(mutating: bytes)
        } else {
            let xdata = api.pointee.pcalloc(req.pointee.pool, len)
            guard let xdata else {
                throw Exception("unable to allocate memory for the bytes to send: (\(len))")
            }
            memcpy(xdata, bytes, len)
            data = xdata
        }

        let buf = withUnsafeMutablePointer(to: &req.pointee.appbuf) { p in p }
        buf.pointee.pos = data
        buf.pointee.last = data.advanced(by: len)
        if noCopy {
            buf.pointee.flags |= UInt32(NGX_BUF_memory)
        } else {
            buf.pointee.flags |= UInt32(NGX_BUF_temporary)
        }
        buf.pointee.flags |= UInt32(NGX_BUF_last_buf)

        let err = api.pointee.http_buf_output_filter(req, buf)
        if err != 0 {
            throw Exception("output filter failed: \(err)")
        }
        return 0
    }
}

public enum HttpMethod: UInt {
    case UNKNOWN = 0x1
    case GET = 0x2
    case HEAD = 0x4
    case POST = 0x8
    case PUT = 0x10
    case DELETE = 0x20
    case MKCOL = 0x40
    case COPY = 0x80
    case MOVE = 0x100
    case OPTIONS = 0x200
    case PROPFIND = 0x400
    case PROPPATCH = 0x800
    case LOCK = 0x1000
    case UNLOCK = 0x2000
    case PATCH = 0x4000
    case TRACE = 0x8000
    case CONNECT = 0x10000
}

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
        let locId = api.pointee.get_loc_id_from_req(r)
        let ud = Unmanaged<ContextData>.fromOpaque(api.pointee.get_upcall()!.pointee.ud).takeUnretainedValue()
        if ud.app.httpServerHandler[locId] == nil {
            api.pointee.log(UInt(NGX_LOG_DEBUG), "unable to find handler related to the location \(locId)")
            return Int(NGX_DECLINED)
        }

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
        let result: HttpResult
        do {
            result = try handler(req)
        } catch {
            req.api.log(.ERR, "failed to handle the request: \(error)")
            api.pointee.http_finalize_request(r, 500)
            return
        }
        let code: Int
        switch result {
        case .ASYNC:
            return
        case let .STATUS(c):
            code = c
        case .OK:
            code = Int(NGX_OK)
        }
        api.pointee.http_finalize_request(r, code)
    }
}

public class HttpRequest: @unchecked Sendable {
    let _api: UnsafePointer<ngx_as_lib_api_t>
    public var api: Api { Api(_api) }
    private var headersSent = false
    private let contextData: ContextData
    public let req: UnsafeMutablePointer<ngx_http_request_t>

    init(api: UnsafePointer<ngx_as_lib_api_t>, contextData: ContextData, req: UnsafeMutablePointer<ngx_http_request_t>) {
        _api = api
        self.contextData = contextData
        self.req = req
    }

    public func executeOnWorker(_ f: @escaping () -> HttpResult) {
        let ok = contextData.queue.push(Runnable {
            let ret = f()
            let code: Int
            switch ret {
            case .ASYNC:
                return
            case let .STATUS(c):
                code = c
            case .OK:
                code = Int(NGX_OK)
            }
            self._api.pointee.http_finalize_request(self.req, code)
        })
        if !ok {
            contextData.enqueueFailedCount.wrappingIncrement(ordering: .relaxed)
        }
        _api.pointee.notify()
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

    private var _uri: String?
    public var uri: String {
        if let _uri {
            return _uri
        }
        _uri = App.ngxstrToString(&req.pointee.unparsed_uri)
        return _uri!
    }

    public var httpVer: UInt {
        return req.pointee.http_version
    }

    static let emptyBody = Data()
    private var _body: Data?
    public var body: Data {
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
        _body = App.makeDataFromChain(_api, chain)
        return _body!
    }

    private var _headers: [String: [String]]?

    public func header(_ key: String) -> [String]? {
        if _headers == nil {
            foreachHeader { _, _ in }
        }
        return _headers![key]
    }

    public func foreachHeader(_ f: (String, String) throws -> Void) rethrows {
        if let _headers {
            for (k, v) in _headers {
                for vv in v {
                    try f(k, vv)
                }
            }
            return
        }
        var __headers = [String: [String]]()
        var part: UnsafeMutablePointer<ngx_list_part_t>? = withUnsafeMutablePointer(to: &req.pointee.headers_in.headers.part) { p in p }
        while let p = part {
            for i in 0 ..< Int(p.pointee.nelts) {
                let h: UnsafeMutablePointer<ngx_table_elt_t> = p.pointee.elts.advanced(by: i * MemoryLayout<ngx_table_elt_t>.stride)
                    .assumingMemoryBound(to: ngx_table_elt_t.self)
                let k = App.ngxstrToString(&h.pointee.key)
                let v = App.ngxstrToString(&h.pointee.value)
                try f(k, v)
                if __headers.keys.contains(k) {
                    __headers[k]!.append(v)
                } else {
                    __headers[k] = [v]
                }
            }
            part = p.pointee.next
        }
        _headers = __headers
    }

    public func header(key: String, value: String) throws -> HttpRequest {
        let err = _api.pointee.add_http_header(req, &req.pointee.headers_out.headers, key, value)
        if err != NGX_OK {
            throw Exception("failed to set header \(key): \(value)")
        }
        return self
    }

    public func status(_ code: Int) -> HttpRequest {
        req.pointee.headers_out.status = UInt(code)
        return self
    }

    public func send(_ s: String, flush: Bool = false) throws -> HttpRequest {
        return try send(s, len: s.utf8CString.count - 1, flush: flush)
    }

    public func send(_ bytes: [CChar], flush: Bool = false) throws -> HttpRequest {
        return try send(bytes, len: bytes.count, flush: flush)
    }

    public func send(_ bytes: UnsafeRawPointer, len: Int, noCopy: Bool = false, flush: Bool = false) throws -> HttpRequest {
        if len <= 0 {
            throw Exception("the length must be greater than 0 when calling send(...)")
        }
        if !headersSent {
            let err = _api.pointee.http_send_header(req)
            if err != 0 {
                throw Exception("send header failed: \(err)")
            }
            headersSent = true
        }

        let data: UnsafeMutableRawPointer
        if noCopy {
            data = UnsafeMutableRawPointer(mutating: bytes)
        } else {
            let xdata = _api.pointee.pcalloc(req.pointee.pool, len)
            guard let xdata else {
                throw Exception("unable to allocate memory for the bytes to send: (\(len))")
            }
            memcpy(xdata, bytes, len)
            data = xdata
        }

        let bufraw = _api.pointee.pcalloc(req.pointee.pool, MemoryLayout<ngx_buf_t>.stride)
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

        let err = _api.pointee.http_buf_output_filter(req, buf)
        if err != 0 {
            throw Exception("output filter failed: \(err)")
        }
        return self
    }

    public func end() throws -> HttpResult {
        return try end(nil, len: 0)
    }

    public func end(_ s: String) throws -> HttpResult {
        return try end(s, len: s.utf8CString.count - 1)
    }

    public func end(_ bytes: Data) throws -> HttpResult {
        return try bytes.withUnsafeBytes { p in try end(p.baseAddress!, len: bytes.count) }
    }

    public func end(_ bytes: UnsafeRawPointer?, len: Int, noCopy: Bool = false) throws -> HttpResult {
        if !headersSent {
            req.pointee.headers_out.content_length_n = Int64(len)
            if len == 0 {
                req.pointee.header_only = true
            }
            let err = _api.pointee.http_send_header(req)
            if err != 0 {
                throw Exception("send header failed: \(err)")
            }
            headersSent = true
            if len == 0 {
                return .OK
            }
        } else {
            if len == 0 {
                let buf = withUnsafeMutablePointer(to: &req.pointee.appbuf) { p in p }
                buf.pointee.flags |= UInt32(NGX_BUF_last_buf)
                let err = _api.pointee.http_buf_output_filter(req, buf)
                if err != 0 {
                    throw Exception("output filter for last buf failed: \(err)")
                }
                return .OK
            }
        }

        guard let bytes else {
            throw Exception("input bytes is nil, cannot be transmitted")
        }

        let data: UnsafeMutableRawPointer
        if noCopy {
            data = UnsafeMutableRawPointer(mutating: bytes)
        } else {
            let xdata = _api.pointee.pcalloc(req.pointee.pool, len)
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

        let err = _api.pointee.http_buf_output_filter(req, buf)
        if err != 0 {
            throw Exception("output filter failed: \(err)")
        }
        return .OK
    }

    public func sendRequest(main: HttpRequest? = nil, target: SockAddr? = nil, method: HttpMethod, uri: String, args: String? = nil,
                            headers: [String: String]? = nil, body: String,
                            callback: @escaping (inout HttpSubRequest, Int) throws -> HttpResult) throws
    {
        return try sendRequest(main: main, target: target, method: method, uri: uri, args: args, headers: headers, body: body, bodyLen: body.utf8CString.count - 1, callback: callback)
    }

    public func sendRequest(main: HttpRequest? = nil, target: SockAddr? = nil, method: HttpMethod, uri: String, args: String? = nil,
                            headers: [String: String]? = nil, body: [CChar],
                            callback: @escaping (inout HttpSubRequest, Int) throws -> HttpResult) throws
    {
        return try sendRequest(main: main, target: target, method: method, uri: uri, args: args, headers: headers, body: body, bodyLen: body.count, callback: callback)
    }

    public func sendRequest(main: HttpRequest? = nil, target: SockAddr? = nil, method: HttpMethod, uri: String, args: String? = nil,
                            headers: [String: String]? = nil, body: UnsafeRawPointer? = nil, bodyLen: Int = 0, copyBody: Bool = true,
                            callback: @escaping (inout HttpSubRequest, Int) throws -> HttpResult) throws
    {
        let cb = _api.pointee.pcalloc(req.pointee.pool, MemoryLayout<ngx_http_post_subrequest_t>.stride)?.assumingMemoryBound(to: ngx_http_post_subrequest_t.self)
        guard let cb else {
            throw Exception("unable to allocate callback object")
        }
        let subreq = SubReq(api: _api, contextData: contextData, main: main, parent: self, target: target, headers: headers, callback: callback)

        var buf: UnsafeMutablePointer<ngx_buf_t>?
        if let body {
            let buf0 = _api.pointee.pcalloc(req.pointee.pool, MemoryLayout<ngx_buf_t>.stride + bodyLen)?.assumingMemoryBound(to: ngx_buf_t.self)
            guard let buf0 else {
                throw Exception("unable to allocate body buf")
            }
            if copyBody {
                let data = UnsafeMutableRawPointer(mutating: buf0).advanced(by: MemoryLayout<ngx_buf_t>.stride)
                memcpy(data, body, bodyLen)
                buf0.pointee.pos = data
                buf0.pointee.last = data.advanced(by: bodyLen)
                buf0.pointee.flags |= UInt32(NGX_BUF_temporary)
            } else {
                buf0.pointee.pos = UnsafeMutableRawPointer(mutating: body)
                buf0.pointee.last = buf0.pointee.pos!.advanced(by: bodyLen)
                buf0.pointee.flags |= UInt32(NGX_BUF_memory)
            }
            buf = buf0
        }

        let un = Unmanaged.passRetained(subreq)
        cb.pointee.data = un.toOpaque()
        cb.pointee.handler = SubReq.subreqPostHandler

        var initCB = ngx_http_init_subrequest_t()
        initCB.handler = SubReq.subreqInitHandler
        initCB.data = cb.pointee.data

        let err = uri.utf8CString.withUnsafeBufferPointer { _uri in
            if let args {
                args.utf8CString.withUnsafeBufferPointer { _args in
                    _api.pointee.http_subrequest(req, Int(method.rawValue),
                                                 UnsafeMutablePointer(mutating: _uri.baseAddress!),
                                                 UnsafeMutablePointer(mutating: _args.baseAddress!),
                                                 buf, &initCB, cb)
                }
            } else {
                _api.pointee.http_subrequest(req, Int(method.rawValue),
                                             UnsafeMutablePointer(mutating: _uri.baseAddress!),
                                             nil, // args
                                             buf, &initCB, cb)
            }
        }
        if err != NGX_OK {
            un.release()
            throw Exception("failed to initialize subrequest")
        }
    }

    public func getSubreqTarget(_ sockaddr: inout SockAddr, default: SockAddr? = nil) -> Bool {
        if req.pointee.sockaddr_holder.0 == nil && req.pointee.sockaddr_holder.1 == nil &&
            req.pointee.sockaddr_holder.2 == nil && req.pointee.sockaddr_holder.3 == nil &&
            req.pointee.sockaddr_holder.4 == nil
        {
            guard let d = `default` else {
                return false
            }
            sockaddr = d
        } else {
            memcpy(&sockaddr, &req.pointee.sockaddr_holder, MemoryLayout<SockAddr>.stride)
        }
        return true
    }
}

public class DummyHttpRequest: HttpRequest, @unchecked Sendable {
    override init(api: UnsafePointer<ngx_as_lib_api_t>, contextData: ContextData, req: UnsafeMutablePointer<ngx_http_request_t>) {
        super.init(api: api, contextData: contextData, req: req)
    }

    public func runPostedRequests() {
        _api.pointee.http_run_posted_requests(req.pointee.connection)
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

class SubReq {
    private let api: UnsafePointer<ngx_as_lib_api_t>
    private let contextData: ContextData
    private let main: HttpRequest?
    private let parent: HttpRequest
    private var target: SockAddr? // var because memcpy need &target
    private let headers: [String: String]?
    private let callback: (inout HttpSubRequest, Int) throws -> HttpResult
    init(api: UnsafePointer<ngx_as_lib_api_t>, contextData: ContextData,
         main: HttpRequest?, parent: HttpRequest,
         target: SockAddr?, headers: [String: String]?,
         callback: @escaping (inout HttpSubRequest, Int) throws -> HttpResult)
    {
        self.api = api
        self.contextData = contextData
        self.main = main
        self.parent = parent
        self.target = target
        self.headers = headers
        self.callback = callback
    }

    static let subreqInitHandler: ngx_http_init_subrequest_pt = { req, data in
        let subreq = Unmanaged<SubReq>.fromOpaque(data!).takeUnretainedValue() // it's still used by the post handler, so `unretained`
        if subreq.target != nil {
            memcpy(&req!.pointee.sockaddr_holder, &subreq.target, MemoryLayout<SockAddr>.stride)
        }
        if let headers = subreq.headers {
            for (k, v) in headers {
                let err = subreq.api.pointee.add_http_header(req, &req!.pointee.headers_in.headers, k, v)
                if err != 0 {
                    return err
                }
            }
        }
        return 0
    }

    static let subreqPostHandler: ngx_http_post_subrequest_pt = { r, data, status in
        let subreq = Unmanaged<SubReq>.fromOpaque(data!).takeRetainedValue()
        let req = HttpRequest(api: subreq.api, contextData: subreq.contextData, req: r!)
        var httpsubreq = HttpSubRequest(ptr: r!, req: req)
        do {
            let ret = try subreq.callback(&httpsubreq, status)
            let code: Int
            switch ret {
            case .ASYNC:
                if r!.pointee.main.pointee.is_dummy {
                    // always release the dummy req
                    subreq.api.pointee.http_finalize_request(r!.pointee.main, 0)
                }
                return 0
            case let .STATUS(c):
                code = c
            case .OK:
                code = Int(NGX_OK)
            }
            subreq.api.pointee.http_finalize_request(r!.pointee.main, code)
            if let main = subreq.main, main.req != r!.pointee.main {
                subreq.api.pointee.http_finalize_request(main.req, code)
            }
        } catch {
            subreq.api.pointee.http_finalize_request(r!.pointee.main, 500)
            if let main = subreq.main, main.req != r!.pointee.main {
                subreq.api.pointee.http_finalize_request(main.req, 500)
            }
        }
        return 0
    }
}

public struct HttpSubRequest {
    public let ptr: UnsafeMutablePointer<ngx_http_request_t>
    public let req: HttpRequest

    private var _body: Data?
    public var body: Data {
        mutating get {
            if let _body {
                return _body
            }
            guard let chain = ptr.pointee.out else {
                _body = HttpRequest.emptyBody
                return _body!
            }
            _body = App.makeDataFromChain(req._api, chain)
            return _body!
        }
    }

    init(ptr: UnsafeMutablePointer<ngx_http_request_t>, req: HttpRequest) {
        self.ptr = ptr
        self.req = req
    }
}

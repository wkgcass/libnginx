#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
import Atomics
import Foundation
import libnginx
import WaitfreeMpscQueueSwift
#if os(Linux)
import LinuxSOMemfd
#endif

public class App {
    private var libnginxPath: String
    public var threads: [AppThreadConf]?
    var httpServerHandler = [Int64: (HttpRequest) throws -> HttpResult]()
    var httpUpstreamHandler = [UInt: (HttpRequest, inout SockAddr) throws -> Bool]()

    nonisolated(unsafe) static var _dummyApi: UnsafePointer<ngx_as_lib_api_t>?
    static var dummyApi: UnsafePointer<ngx_as_lib_api_t> { _dummyApi! }

    public init(libpath: String) {
        libnginxPath = libpath
    }

    public func addHttpServerHandler(id: Int64, handler: @escaping (HttpRequest) throws -> HttpResult) {
        httpServerHandler[id] = handler
    }

    public func addHttpUpstreamHandler(id: UInt, handler: @escaping (HttpRequest, inout SockAddr) throws -> Bool) {
        httpUpstreamHandler[id] = handler
    }

    public func launch(conf: String) throws {
        let threadCount = if let threads {
            threads.count
        } else { 1 }
        let confs: [String]
        if let threads {
            var c = [String](repeating: conf, count: threadCount)
            for i in 0 ..< threadCount {
                if let affinity = threads[i].workerCpuAffinity {
                    c[i] = "worker_cpu_affinity \(affinity);\n\(c[i])"
                }
            }
            confs = c
        } else {
            confs = [String](repeating: conf, count: 1)
        }

// prepare pthread
#if canImport(Darwin)
        let pthreads = UnsafeMutablePointer<pthread_t?>.allocate(capacity: threadCount)
#else
        let pthreads = UnsafeMutablePointer<pthread_t>.allocate(capacity: threadCount)
#endif

#if os(Linux)
        let data = try Data(contentsOf: URL(fileURLWithPath: libnginxPath))
        var libnginxBytes = [UInt8](data)
#endif

        // start
        for i in 0 ..< threadCount {
#if !os(Linux)
            let tmplib = FileManager.default.temporaryDirectory.appendingPathComponent("libnginx\(i)").path
            do { try FileManager.default.removeItem(atPath: tmplib) } catch {}
            try FileManager.default.copyItem(atPath: libnginxPath, toPath: tmplib)
#else
            var ctmplib = [CChar](repeating: 0, count: 2048)
            let memfd = ngx_helper_create_memfd_for_so(&libnginxBytes, UInt32(libnginxBytes.count), "libnginx\(i)", &ctmplib)
            if memfd < 0 {
                throw Exception("failed to create memfd for so \(i): errno: \(-memfd)")
            }
            let tmplib = String(utf8String: &ctmplib)!
#endif

            let lib = dlopen(tmplib, RTLD_NOW | RTLD_LOCAL)
            guard let lib else {
                throw Exception("failed to open library: \(tmplib)")
            }
#if !os(Linux)
            try FileManager.default.removeItem(atPath: tmplib)
#endif

            let libngxSym = dlsym(lib, LIBNGX)
            guard let libngxSym else {
                throw Exception("failed to get symbol: \"\(LIBNGX)\"")
            }
            let libngx = unsafeBitCast(libngxSym, to: libngx_entrypoint.self)
            let api = UnsafePointer(libngx()!)
            if i == 0 {
                Self._dummyApi = api
            }
            let userdata: AnyObject? = if let threads { threads[i].data } else { nil }
            let queue = WaitfreeMpscQueue<Runnable>()
            let contextData = ContextData(app: self, queue: queue, data: userdata)
            let contextPtr: UnsafeMutableRawPointer = Unmanaged.passRetained(contextData).toOpaque()

            let upcall = UnsafeMutablePointer<ngx_as_lib_upcall_t>.allocate(capacity: 1)
            upcall.initialize(to: ngx_as_lib_upcall_t())
            upcall.pointee.ud = contextPtr
            upcall.pointee.postconfiguration = Http.postconfiguration
            upcall.pointee.get_upstream_peer = Upstream.getpeer
            upcall.pointee.looptick = Self.looptick

            api.pointee.set_upcall(upcall)

            let tmpconf = FileManager.default.temporaryDirectory.appendingPathComponent("nginx\(i).conf").path
            try confs[i].write(toFile: tmpconf, atomically: true, encoding: String.Encoding.utf8)

            let argc = 3
            let argv: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?> = malloc(8 * argc).assumingMemoryBound(to: UnsafeMutablePointer?.self)
            let err = "sample".withCString { arg0 in
                "-c".withCString { arg1 in
                    tmpconf.withCString { arg2 in
                        argv.pointee = UnsafeMutablePointer(mutating: arg0)
                        argv.advanced(by: 1).pointee = UnsafeMutablePointer(mutating: arg1)
                        argv.advanced(by: 2).pointee = UnsafeMutablePointer(mutating: arg2)
                        return api.pointee.main_new_thread(&pthreads[i], Int32(argc), argv)
                    }
                }
            }
            free(argv)
            if err != 0 {
                throw Exception("failed to launch server thread[\(i)]")
            }
        }

        // wait for workers to exit
        for i in 0 ..< threadCount {
#if canImport(Darwin)
            pthread_join(pthreads[i]!, nil)
#else
            pthread_join(pthreads[i], nil)
#endif
        }
    }

    static let looptick: @convention(c) (UnsafeMutablePointer<ngx_as_lib_api_t>?, UnsafeMutableRawPointer?) -> Int64 = { api, ud in
        let contextData = Unmanaged<ContextData>.fromOpaque(ud!).takeUnretainedValue()
        let queue = contextData.queue
        while true {
            guard let r = queue.pop() else {
                break
            }
            r.f()
        }
        let failedCount = contextData.enqueueFailedCount.load(ordering: .relaxed)
        if failedCount != contextData.lastEnqueueFailedCount {
            api!.pointee.log(UInt(NGX_LOG_CRIT), "an async task was unable to be enqueued")
        }
        contextData.lastEnqueueFailedCount = failedCount
        return -1
    }

    static func makeDataFromChain(_ api: UnsafePointer<ngx_as_lib_api_t>, _ chain: UnsafeMutablePointer<ngx_chain_t>) -> Data {
        var node: UnsafeMutablePointer<ngx_chain_t>? = chain
        var cap = 0
        while let n = node {
            if let buf = n.pointee.buf {
                if buf.pointee.pos == nil {
                    api.pointee.log(UInt(NGX_LOG_ERR), "body is not in memory")
                    return HttpRequest.emptyBody
                }
                let len = buf.pointee.last - buf.pointee.pos
                cap += len
            }
            node = n.pointee.next
        }
        var copiedBody = Data(capacity: cap)
        copiedBody.count = cap
        copiedBody.withUnsafeMutableBytes { p in
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
        return copiedBody
    }

    static func ngxstrToString(_ s: UnsafePointer<ngx_str_t>) -> String {
        var cchars = [CChar](unsafeUninitializedCapacity: s.pointee.len + 1) { _, l in l = s.pointee.len + 1 }
        cchars[cchars.count - 1] = 0
        memcpy(&cchars, s.pointee.data, s.pointee.len)
        return String(cString: &cchars)
    }
}

public struct Api {
    @usableFromInline
    let api: UnsafePointer<ngx_as_lib_api_t>
    init(_ api: UnsafePointer<ngx_as_lib_api_t>) {
        self.api = api
    }

    @inlinable @inline(__always)
    public var workerData: AnyObject? {
        let contextData = Unmanaged<ContextData>.fromOpaque(api.pointee.get_upcall()!.pointee.ud!).takeUnretainedValue()
        return contextData.data
    }

    @inlinable @inline(__always)
    public func log(_ level: NgxLogLevel, _ message: String) {
        api.pointee.log(UInt(level.rawValue), message)
    }

    public func newDummyHttpRequest(serverId: Int) throws -> DummyHttpRequest {
        let r = api.pointee.new_http_dummy_request(serverId)
        guard let r else {
            throw Exception("failed to allocate dummy http request")
        }
        let ctx = Unmanaged<ContextData>.fromOpaque(api.pointee.get_upcall()!.pointee.ud).takeUnretainedValue()
        return DummyHttpRequest(api: api, contextData: ctx, req: r)
    }
}

class Runnable {
    let f: () -> Void
    init(_ f: @escaping () -> Void) {
        self.f = f
    }
}

@usableFromInline
class ContextData {
    let app: App
    let queue: WaitfreeMpscQueue<Runnable>
    let enqueueFailedCount = ManagedAtomic<UInt64>(0)
    var lastEnqueueFailedCount: UInt64 = 0
    @usableFromInline
    let data: AnyObject?

    init(app: App, queue: WaitfreeMpscQueue<Runnable>, data: AnyObject?) {
        self.app = app
        self.queue = queue
        self.data = data
    }
}

public struct AppThreadConf {
    public var workerCpuAffinity: String?
    public var data: AnyObject?
    public init(workerCpuAffinity: String? = nil, data: AnyObject? = nil) {
        self.workerCpuAffinity = workerCpuAffinity
        self.data = data
    }
}

struct Exception: Error {
    let message: String
    init(_ message: String) {
        self.message = message
    }
}

public enum NgxLogLevel: Int32 {
    case STDERR = 0
    case EMERG = 1
    case ALERT = 2
    case CRIT = 3
    case ERR = 4
    case WARN = 5
    case NOTICE = 6
    case INFO = 7
    case DEBUG = 8
}

public enum HttpResult {
    case ASYNC
    case STATUS(_ code: Int)
    case OK
}

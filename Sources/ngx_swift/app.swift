#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
import Atomics
import Foundation
import libnginx
import WaitfreeMpscQueueSwift

public class App {
    private var libnginxPath: String
    public var threads: [AppThreadConf]?
    var httpServerHandler = [Int64: (HttpRequest) throws -> Int]()

    nonisolated(unsafe) static var _dummyApi: UnsafePointer<ngx_as_lib_api_t>?
    static var dummyApi: UnsafePointer<ngx_as_lib_api_t> { _dummyApi! }

    public init(libpath: String) {
        libnginxPath = libpath
    }

    public func addHttpServerHandler(id: Int64, handler: @escaping (HttpRequest) throws -> Int) {
        httpServerHandler[id] = handler
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
        let pthreads = UnsafeMutablePointer<pthread_t?>.allocate(capacity: threadCount)

        // start
        for i in 0 ..< threadCount {
            let tmplib = FileManager.default.temporaryDirectory.appendingPathComponent("libnginx\(i)").path
            do { try FileManager.default.removeItem(atPath: tmplib) } catch {}
            try FileManager.default.copyItem(atPath: libnginxPath, toPath: tmplib)

            let lib = dlopen(tmplib, RTLD_NOW | RTLD_LOCAL)
            guard let lib else {
                throw Exception("failed to open library: \(tmplib)")
            }
            try FileManager.default.removeItem(atPath: tmplib)

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
            pthread_join(pthreads[i]!, nil)
        }
    }

    static let looptick: @convention(c) (UnsafeMutablePointer<ngx_as_lib_api_t>?, UnsafeMutableRawPointer?) -> Void = { api, ud in
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
    }
}

class Runnable {
    let f: () -> Void
    init(_ f: @escaping () -> Void) {
        self.f = f
    }
}

class ContextData {
    let app: App
    let queue: WaitfreeMpscQueue<Runnable>
    let enqueueFailedCount = ManagedAtomic<UInt64>(0)
    var lastEnqueueFailedCount: UInt64 = 0
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

public let ASYNC: Int = .init(NGX_AGAIN)

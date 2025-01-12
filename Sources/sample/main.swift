#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
import ArgumentParser
import Foundation
import ngx_swift

NgxSwiftSample.main()

struct NgxSwiftSample: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Sample code of ngx_swift.")

#if canImport(Darwin)
    @Option(help: "The path to libnginx shared library.") var lib: String = "objs/libnginx.dylib"
#else
    @Option(help: "The path to libnginx shared library.") var lib: String = "objs/libnginx.so"
#endif
    @Option(help: "Thread count.") var threads: Int = 1

    func run() throws {
        let app = App(libpath: lib)
        app.threads = [AppThreadConf]()
        for _ in 0 ..< threads {
            app.threads!.append(AppThreadConf(data: Storage()))
        }

        /* /sample */
        app.addHttpServerHandler(id: 1) { req in
            req.status(200)
            return try req.end("""
            You can request the following uris:
            * /sample  -> this page
            * /async   -> wait for a few seconds and get the full response
            * /echo    -> respond whatever you input
            * /storage -> get or set data

            """)
        }
        /* /async */
        app.addHttpServerHandler(id: 2) { req in
            req.status(200)
            _ = try req.send("Please wait for 2 seconds ...\n", flush: true)
            let thread = Thread {
                sleep(2)
                req.executeOnWorker {
                    do {
                        return try req.end("Async response done!\n")
                    } catch {
                        return 500
                    }
                }
            }
            thread.start()
            return ASYNC
        }
        /* /echo */
        app.addHttpServerHandler(id: 3) { req in
            if req.method != .POST && req.method != .PUT {
                return 405
            }
            req.status(200)
            try req.send("You input is:\n")
            return try req.end(req.body)
        }
        /* GET /storage */
        app.addHttpServerHandler(id: 4) { req in
            let storage = req.data as! Storage
            guard let data = storage.data else {
                req.status(404)
                return try req.end("no data\n")
            }
            req.status(200)
            return try req.end(data)
        }
        /* POST /storage */
        app.addHttpServerHandler(id: 5) { req in
            let storage = req.data as! Storage
            storage.data = req.body
            req.status(200)
            return try req.end()
        }

        try app.launch(conf: """
        error_log /dev/stdout debug;
        events {}
        http {
            server {
                listen 0.0.0.0:7788 reuseport;
                location = /sample {
                    upcall 1;
                }
                location = /async {
                    upcall 2;
                }
                location = /echo {
                    upcall 3;
                }
                location = /storage {
                    if ($request_method = GET) {
                        upcall 4; break;
                    }
                    if ($request_method = POST) {
                        upcall 5; break;
                    }
                    return 405;
                }
            }
        }
        """)
        print("exiting ...")
    }
}

class Storage {
    var data: [CChar]?
}

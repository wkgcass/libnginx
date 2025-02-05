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
        let global = GlobalData()
        for _ in 0 ..< threads {
            app.threads!.append(AppThreadConf(data: PercoreData(global: global)))
        }

        /* /sample */
        app.addHttpServerHandler(id: 1) { req in
            _ = req.status(200)
            return try req.end("""
            You can request the following uris:
            * /sample  -> this page
            * /async   -> wait for a few seconds and get the full response
            * /echo    -> respond whatever you input
            * /storage -> get or set data
            * /sub     -> make nginx subrequests
            * /headers -> echo request method, uri and headers in body
            * /sndhdrs -> parse {key:str} json body and respond them in headers

            """)
        }
        /* /async */
        app.addHttpServerHandler(id: 2) { req in
            _ = req.status(200)
            _ = try req.send("Please wait for 2 seconds ...\n", flush: true)
            let thread = Thread {
                sleep(2)
                req.executeOnWorker {
                    do {
                        return try req.end("Async response done!\n")
                    } catch {
                        return .STATUS(500)
                    }
                }
            }
            thread.start()
            return .ASYNC
        }
        /* /echo */
        app.addHttpServerHandler(id: 3) { req in
            if req.method != .POST && req.method != .PUT {
                return .STATUS(405)
            }
            return try req.status(200)
                .send("You input is:\n")
                .end(req.body)
        }
        /* GET /storage */
        app.addHttpServerHandler(id: 4) { req in
            let storage = (req.api.workerData as! PercoreData).global
            guard let data = storage.data else {
                return try req.status(404).end("no data\n")
            }
            return try req.status(200).end(data)
        }
        /* POST /storage */
        app.addHttpServerHandler(id: 5) { req in
            let storage = (req.api.workerData as! PercoreData).global
            storage.data = req.body
            _ = req.status(200)
            return try req.end()
        }
        /* /sub */
        app.addHttpServerHandler(id: 6) { req in
            let dummy = try req.api.newDummyHttpRequest(serverId: 1)
            try dummy.sendRequest(main: req, target: SockAddr("[::1]:8899"),
                                  method: .POST, uri: "/some_uri", headers: ["x-req-id": "\(Date())"],
                                  body: "body content")
            { sub, status in
                if status != 0 {
                    return .STATUS(500)
                }
                _ = req.status(200)
                return try req.end(sub.body)
            }
            dummy.runPostedRequests()
            return .ASYNC
        }
        /* /headers */
        app.addHttpServerHandler(id: 7) { req in
            var resp = "method=\(req.method) uri=\(req.uri) ver=\(req.httpVer)\r\n"
            req.foreachHeader { k, v in resp += "\(k): \(v)\r\n" }
            return try req.status(200).end(resp)
        }
        /* /sndhdrs */
        app.addHttpServerHandler(id: 8) { req in
            let decoder = JSONDecoder()
            let map = try decoder.decode([String: String].self, from: req.body)
            for (k, v) in map {
                _ = try req.header(key: k, value: v)
            }
            return try req.status(200).end()
        }

        /* upstream */
        app.addHttpUpstreamHandler(id: 1) { req, s in req.getSubreqTarget(&s, default: SockAddr("[::1]:9900")) }

        try app.launch(conf: """
        error_log /dev/stdout debug;
        # error_log off;
        events {}
        http {
            access_log /dev/stdout;
            # access_log off;
            server {
                listen 0.0.0.0:7788 reuseport;
                http2 on;
                keepalive_requests 100000000;
                keepalive_timeout  100000000;
                location / {
                    upcall 1;
                }
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
                location = /sub {
                    upcall 6;
                }
                location = /headers {
                    upcall 7;
                }
                location = /sndhdrs {
                    upcall 8;
                }
            }
            server {
                listen 0.0.0.0:8899 reuseport;
                listen [::]:8899 reuseport;
                keepalive_requests 100000000;
                keepalive_timeout  100000000;
                location = /some_uri {
                    if ($request_method = POST) {
                        return 200 "POST resposne from 8899\r\n"; break;
                    }
                    return 405;
                }
            }
            server {
                listen 0.0.0.0:9900 reuseport;
                listen [::]:9900 reuseport;
                keepalive_requests 100000000;
                keepalive_timeout  100000000;
                location / {
                    return 200 "I am 9900\r\n";
                }
            }
            server {
                server_id 1;
                listen 0.0.0.0:65535 reuseport;
                location / {
                    proxy_set_header Connection "";
                    proxy_http_version 1.1;
                    proxy_pass http://servers/;
                }
            }
            upstream servers {
                upcall 1;
                keepalive 128;
                keepalive_requests 100000000;
                keepalive_timeout  100000000;
                server 1.1.1.1:1; # template
            }
        }
        """)
        print("exiting ...")
    }
}

class PercoreData {
    let global: GlobalData
    init(global: GlobalData) {
        self.global = global
    }
}

class GlobalData {
    var data: Data?
}

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
import libnginx

class Upstream {
    static let getpeer: (@convention(c) (UnsafeMutablePointer<ngx_as_lib_api_t>?, UnsafeMutableRawPointer?,
                                         UnsafeMutablePointer<ngx_http_request_t>?, UInt, UnsafeMutablePointer<ngx_peer_connection_t>?) -> Int) = { api, ud, r, id, pc in
        let context = Unmanaged<ContextData>.fromOpaque(ud!).takeUnretainedValue()
        guard let handler = context.app.httpUpstreamHandler[id] else {
            api!.pointee.log(UInt(NGX_LOG_ERR), "unable to find handler related to the upstream \(id)")
            return Int(NGX_DECLINED)
        }
        let req = HttpRequest(api: api!, contextData: context, req: r!)
        var addr: SockAddr?
        do {
            addr = try handler(req)
        } catch {
            req.api.log(.ERR, "failed to provide server for upstream \(id): \(error)")
            return Int(NGX_DECLINED)
        }
        guard var addr else {
            req.api.log(.WARN, "no server provided for upstream \(id)")
            return Int(NGX_DECLINED)
        }
        switch addr.type {
        case .v4:
            pc!.pointee.socklen = socklen_t(MemoryLayout<sockaddr_in>.stride)
            let p = api!.pointee.pcalloc(r!.pointee.pool, MemoryLayout<sockaddr_in>.stride)
            guard let p else {
                req.api.log(.ERR, "failed to allocate memory for sockaddr_in")
                return Int(NGX_ERROR)
            }
            let pp = p.assumingMemoryBound(to: sockaddr_in.self)
#if canImport(Darwin)
            pp.pointee.sin_family = UInt8(AF_INET)
#else
            pp.pointee.sin_family = UInt16(AF_INET)
#endif
            pp.pointee.sin_addr = addr.v4
            pp.pointee.sin_port = addr.portNetworkOrder
            pc!.pointee.sockaddr = p.assumingMemoryBound(to: sockaddr.self)
        case .v6:
            pc!.pointee.socklen = socklen_t(MemoryLayout<sockaddr_in6>.stride)
            let p = api!.pointee.pcalloc(r!.pointee.pool, MemoryLayout<sockaddr_in6>.stride)
            guard let p else {
                req.api.log(.ERR, "failed to allocate memory for sockaddr_in6")
                return Int(NGX_ERROR)
            }
            let pp = p.assumingMemoryBound(to: sockaddr_in6.self)
#if canImport(Darwin)
            pp.pointee.sin6_family = UInt8(AF_INET6)
#else
            pp.pointee.sin6_family = UInt16(AF_INET6)
#endif
            pp.pointee.sin6_addr = addr.v6
            pp.pointee.sin6_port = addr.portNetworkOrder
            pc!.pointee.sockaddr = p.assumingMemoryBound(to: sockaddr.self)
        }
        return Int(NGX_OK)
    }
}

public struct SockAddr {
    public var v6: in6_addr // 16
    public var v4: in_addr // 4
    public var portNetworkOrder: UInt16 // 2
    public var type: SockAddrType // 1
    // total <= 24

    public init(_ v4: in_addr, _ port: UInt16) {
        type = .v4
        self.v4 = v4
        v6 = in6_addr()
        portNetworkOrder = ((port >> 8) & 0xff) | ((port & 0xff) << 8)
    }

    public init(_ v6: in6_addr, _ port: UInt16) {
        type = .v6
        v4 = in_addr()
        self.v6 = v6
        portNetworkOrder = ((port >> 8) & 0xff) | ((port & 0xff) << 8)
    }

    public init?(_ addr: String) {
        let lastColon = addr.lastIndex(of: ":")
        guard let lastColon else {
            return nil
        }
        let ippart = String(addr[..<lastColon])
        let portpart = String(addr[addr.index(lastColon, offsetBy: 1)...])

        let port = UInt16(portpart)
        guard let port else {
            return nil
        }
        self.init(ippart, port)
    }

    public init?(_ ippart: String, _ port: UInt16) {
        var ippart = ippart
        if ippart.hasPrefix("["), ippart.hasSuffix("]") {
            ippart = String(ippart.dropFirst().dropLast())
        }
        if ippart.contains(":") {
            // v6
            var addr = in6_addr()
            if inet_pton(AF_INET6, ippart, &addr) != 1 {
                return nil
            }
            self.init(addr, port)
        } else {
            // v4
            var addr = in_addr()
            if inet_pton(AF_INET, ippart, &addr) != 1 {
                return nil
            }
            self.init(addr, port)
        }
    }
}

public enum SockAddrType: UInt8 {
    case v4
    case v6
}

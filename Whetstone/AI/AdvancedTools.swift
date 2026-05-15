import Foundation
import Network
#if canImport(Darwin)
import Darwin.C
#endif

import Citadel
import NIOCore

// MARK: - Catalogue

enum AdvancedTools {

    static let all: [Tool] = [
        dnsLookupTool, pingHostTool, ipGeolocationTool, portScanTool,
        httpRequestTool, whoisLookupTool, networkInterfacesTool, sshExecuteTool,
    ]

    static func dispatch(_ call: ToolCall) async -> ToolResult {
        let badArgs = ToolResult(callId: call.id, output: "Invalid JSON arguments.", svgPayload: nil, chipsPayload: nil)
        let unknown = ToolResult(callId: call.id, output: "Unknown advanced tool.", svgPayload: nil, chipsPayload: nil)

        guard let data = call.arguments.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return badArgs }

        do {
            switch call.name {
            case "dns_lookup":
                return ToolResult(callId: call.id, output: try await handleDNS(dict), svgPayload: nil, chipsPayload: nil)
            case "ping_host":
                return ToolResult(callId: call.id, output: try await handlePing(dict), svgPayload: nil, chipsPayload: nil)
            case "ip_geolocation":
                return ToolResult(callId: call.id, output: try await handleGeo(dict), svgPayload: nil, chipsPayload: nil)
            case "port_scan":
                return ToolResult(callId: call.id, output: try await handlePortScan(dict), svgPayload: nil, chipsPayload: nil)
            case "http_request":
                return ToolResult(callId: call.id, output: try await handleHTTP(dict), svgPayload: nil, chipsPayload: nil)
            case "whois_lookup":
                return ToolResult(callId: call.id, output: try await handleWhois(dict), svgPayload: nil, chipsPayload: nil)
            case "network_interfaces":
                return ToolResult(callId: call.id, output: handleInterfaces(), svgPayload: nil, chipsPayload: nil)
            case "ssh_execute":
                return ToolResult(callId: call.id, output: try await handleSSH(dict), svgPayload: nil, chipsPayload: nil)
            default:
                return unknown
            }
        } catch {
            return ToolResult(
                callId: call.id,
                output: "Tool error: \(error.localizedDescription)",
                svgPayload: nil,
                chipsPayload: nil
            )
        }
    }

    private static let dnsLookupTool = Tool(
        name: "dns_lookup",
        description:
            """
            Resolve a hostname via getaddrinfo on this device — returns canon name plus A and/or AAAA strings.
            """,
        parameters: toolParameters(
            required: ["hostname"],
            properties: [
                "hostname": strProp("FQDN."),
                "record_type": strProp("'A', 'AAAA', or 'BOTH' (default BOTH)."),
            ]
        )
    )

    private static let pingHostTool = Tool(
        name: "ping_host",
        description:
            """
            TCP handshake timing probes (NOT ICMP — iOS restricts raw ping). Repeated sequential connects timing success path.
            """,
        parameters: toolParameters(
            required: ["host"],
            properties: [
                "host": strProp("Hostname or IP."),
                "port": intProp("TCP port (default 443)."),
                "count": intProp("Attempts (default 3, max 10)."),
            ]
        )
    )

    private static let ipGeolocationTool = Tool(
        name: "ip_geolocation",
        description:
            """
            Lightweight IP/geo via public HTTPS `ipinfo.io` from the device — rate-limited by vendor; coarse location only.
            """,
        parameters: toolParameters(required: ["ip"], properties: ["ip": strProp("IPv4 / IPv6 address.")])
    )

    private static let portScanTool = Tool(
        name: "port_scan",
        description:
            """
            Parallel-ish sequential TCP SYN substitute (NWConnection handshake) capped at 256 ports per invocation with ~1s timeout/port.
            """,
        parameters: toolParameters(
            required: ["host", "ports"],
            properties: [
                "host": strProp("Hostname or IP."),
                "ports": portsArrayProp,
            ]
        )
    )

    private static let httpRequestTool = Tool(
        name: "http_request",
        description:
            """
            HTTPS/HTTP outbound request via URLSession. Headers optional object of strings; body optional UTF-8; response clipped for token safety.
            """,
        parameters: toolParameters(
            required: ["method", "url"],
            properties: [
                "method": strProp("GET, POST, HEAD, PUT, PATCH, DELETE."),
                "url": strProp("Absolute URL."),
                "headers": headersProp,
                "body": strProp("Optional UTF-8 body."),
            ]
        )
    )

    private static let whoisLookupTool = Tool(
        name: "whois_lookup",
        description: "Bootstrap RDAP lookup to `rdap.org` for registrable domains.",
        parameters: toolParameters(required: ["domain"], properties: ["domain": strProp("example.com.")])
    )

    private static let networkInterfacesTool = Tool(
        name: "network_interfaces",
        description: "List non-loopback inet addresses observed via `getifaddrs`.",
        parameters: ["type": "object", "properties": [:]] as [String: Any]
    )

    private static let sshExecuteTool = Tool(
        name: "ssh_execute",
        description:
            """
            Authenticate via password, run ONE remote command via Citadel, return captured channel output plus exit semantics. \
            Validates host keys with `.acceptAnything` (MITM susceptible—tell only trusted lab usage). Credentials never persisted client-side UI state.
            """,
        parameters: toolParameters(
            required: ["host", "username", "password", "command"],
            properties: [
                "host": strProp("Hostname or IP."),
                "port": intProp("SSH port (default 22)."),
                "username": strProp("Account name."),
                "password": strProp("SSH password ephemeral to this invocation."),
                "command": strProp("Escaped remote command."),
            ]
        )
    )

    private static let portsArrayProp: [String: Any] = [
        "type": "array",
        "description": "Integer TCP ports — max 256.",
        "items": ["type": "integer"],
    ]

    private static let headersProp: [String: Any] = [
        "type": "object",
        "description": "Arbitrary HTTP header pairs (string values only).",
        "additionalProperties": ["type": "string"],
    ]

    private static func toolParameters(
        required keys: [String],
        properties: [String: [String: Any]]
    ) -> [String: Any] {
        [
            "type": "object",
            "properties": properties,
            "required": keys,
        ]
    }

    private static func strProp(_ description: String) -> [String: Any] {
        ["type": "string", "description": description]
    }

    private static func intProp(_ description: String) -> [String: Any] {
        ["type": "integer", "description": description]
    }
}

// MARK: - Parsing helpers

private func stringRequired(_ dict: [String: Any], _ key: String) throws -> String {
    guard let raw = dict[key] as? String else { throw AdvErr("\(key) must be string") }
    let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !t.isEmpty else { throw AdvErr("\(key) empty") }
    return t
}

private func optionalString(_ dict: [String: Any], _ key: String) -> String? {
    guard let raw = dict[key] as? String else { return nil }
    let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    return t.isEmpty ? nil : t
}

private func coerceInt(_ any: Any?) -> Int? {
    if let i = any as? Int { return i }
    if let d = any as? Double { return Int(d) }
    if let s = any as? String { return Int(s.trimmingCharacters(in: .whitespacesAndNewlines)) }
    return nil
}

private func optionalInt(_ dict: [String: Any], _ key: String, default defaultValue: Int) -> Int {
    coerceInt(dict[key]) ?? defaultValue
}

private struct AdvErr: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

// MARK: Tool bodies

private func handleDNS(_ dict: [String: Any]) async throws -> String {
    let host = try stringRequired(dict, "hostname")
    let modeRaw = optionalString(dict, "record_type") ?? "BOTH"
    let mode = modeRaw.uppercased()

    return try await Task.detached(priority: .utility) { () throws -> String in
        var hints = addrinfo()
        hints.ai_family = PF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        hints.ai_flags = AI_CANONNAME

        var res: UnsafeMutablePointer<addrinfo>?
        let rc = host.withCString { getaddrinfo($0, nil, &hints, &res) }
        defer {
            if let res {
                freeaddrinfo(res)
            }
        }

        guard rc == 0, let first = res else {
            let detail = rc != 0 ? String(cString: gai_strerror(rc)) : "no results"
            throw AdvErr(detail)
        }

        var v4: Set<String> = []
        var v6: Set<String> = []

        func appendNumeric(_ pinfo: UnsafeMutablePointer<addrinfo>) {
            let family = pinfo.pointee.ai_family
            let addrLen = pinfo.pointee.ai_addrlen
            guard let sockaddrPtr = pinfo.pointee.ai_addr else { return }

            var hostBuf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(
                sockaddrPtr,
                socklen_t(addrLen),
                &hostBuf,
                socklen_t(hostBuf.count),
                nil,
                0,
                NI_NUMERICHOST
            ) == 0 {
                let dotted = String(cString: hostBuf)
                switch family {
                case AF_INET: v4.insert(dotted)
                case AF_INET6: v6.insert(dotted)
                default: break
                }
            }
        }

        var canon: String?
        var walker: UnsafeMutablePointer<addrinfo>? = first
        while let cur = walker {
            if canon == nil, let c = cur.pointee.ai_canonname {
                canon = String(cString: c)
            }
            appendNumeric(cur)
            walker = cur.pointee.ai_next
        }

        var lines: [String] = []
        lines.append("canonical: \(canon ?? "—")")
        switch mode {
        case "A":
            lines.append("A: \(v4.sorted())")
        case "AAAA":
            lines.append("AAAA: \(v6.sorted())")
        default:
            lines.append("A: \(v4.sorted())")
            lines.append("AAAA: \(v6.sorted())")
        }
        return lines.joined(separator: "\n")
    }.value
}

private func tcpProbeLatency(host: String, port: UInt16) async throws -> TimeInterval {
    guard let nwPort = NWEndpoint.Port(rawValue: port) else { throw AdvErr("bad port") }
    let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: nwPort)

    return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<TimeInterval, Error>) in
        let conn = NWConnection(to: endpoint, using: NWParameters.tcp)
        let start = CFAbsoluteTimeGetCurrent()
        let queue = DispatchQueue.global(qos: .utility)

        var finished = false
        func finish(_ result: Result<TimeInterval, Error>) {
            guard !finished else { return }
            finished = true
            conn.cancel()
            switch result {
            case let .success(v): continuation.resume(returning: v)
            case let .failure(e): continuation.resume(throwing: e)
            }
        }

        conn.stateUpdateHandler = { state in
            switch state {
            case .ready:
                finish(.success(CFAbsoluteTimeGetCurrent() - start))
            case let .failed(err):
                finish(.failure(err))
            default:
                break
            }
        }

        conn.start(queue: queue)
        queue.asyncAfter(deadline: .now() + 5) {
            finish(.failure(AdvErr("connect timeout"))) 
        }
    }
}

private func handlePing(_ dict: [String: Any]) async throws -> String {
    let host = try stringRequired(dict, "host")
    let portNum = UInt16(clamping: max(1, optionalInt(dict, "port", default: 443)))
    var count = max(1, min(optionalInt(dict, "count", default: 3), 10))

    var rows: [String] = []
    while count > 0 {
        do {
            let ms = try await tcpProbeLatency(host: host, port: portNum) * 1000
            rows.append(String(format: "ok\t%.2f ms", ms))
        } catch {
            rows.append("fail\t\(error.localizedDescription)")
        }
        count -= 1
    }
    return "host \(host):\(portNum) TCP probes\n\(rows.joined(separator: "\n"))"
}

private func handleGeo(_ dict: [String: Any]) async throws -> String {
    let ip = try stringRequired(dict, "ip")
    guard let url = URL(string: "https://ipinfo.io/\(ip)/json") else {
        throw AdvErr("bad url assemble")
    }
    var req = URLRequest(url: url)
    req.timeoutInterval = 20
    let (data, response) = try await URLSession.shared.data(for: req)
    guard let http = response as? HTTPURLResponse else { throw AdvErr("no HTTP response") }
    let bodySnippet = formatBodySnippet(data, limit: 12_288)
    return "status \(http.statusCode)\n\(bodySnippet)"
}

private func handlePortScan(_ dict: [String: Any]) async throws -> String {
    let host = try stringRequired(dict, "host")
    guard let rawPorts = dict["ports"] as? [Any], !rawPorts.isEmpty else {
        throw AdvErr("ports array required")
    }
    let ports = rawPorts.compactMap(coerceInt).filter { $0 > 0 && $0 < 65_536 }
    guard !ports.isEmpty else { throw AdvErr("ports empty") }
    let clipped = ports.count > 256 ? Array(ports.prefix(256)) : ports
    let truncated = ports.count > 256

    var lines: [String] = []
    for p in clipped {
        if let dur = try? await tcpProbeLatency(host: host, port: UInt16(clamping: p)) {
            lines.append(String(format: "port %d open/handshake %.3fs", p, dur))
        }
    }

    let note = truncated ? "note: truncated to first 256 ports\n\n" : ""
    if lines.isEmpty { return note + "(no reachable TCP handshake in probe window)" }
    return note + lines.joined(separator: "\n")
}

private func handleHTTP(_ dict: [String: Any]) async throws -> String {
    let methodRaw = try stringRequired(dict, "method")
    let urlString = try stringRequired(dict, "url")
    guard let url = URL(string: urlString) else { throw AdvErr("malformed URL") }

    var req = URLRequest(url: url)
    req.httpMethod = methodRaw.uppercased()

    if let headers = dict["headers"] as? [String: Any] {
        for (k, v) in headers {
            guard let value = v as? String else { continue }
            req.addValue(value, forHTTPHeaderField: k)
        }
    }

    if let bodyStr = dict["body"] as? String, !bodyStr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        req.httpBody = bodyStr.data(using: .utf8)
    }

    req.timeoutInterval = 40
    let (data, response) = try await URLSession.shared.data(for: req)
    guard let http = response as? HTTPURLResponse else { throw AdvErr("non-HTTP response") }

    var headerLines: [String] = []
    headerLines.reserveCapacity(http.allHeaderFields.count)
    for (key, value) in http.allHeaderFields {
        headerLines.append("\(key): \(value)")
    }

    let snippets = headerLines.sorted().prefix(40).joined(separator: "\n")
    let body = formatBodySnippet(data, limit: 262_144)
    return "HTTP \(http.statusCode)\n\(snippets)\n\nBODY:\n\(body)"
}

private func handleWhois(_ dict: [String: Any]) async throws -> String {
    let raw = try stringRequired(dict, "domain").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !raw.contains(where: { !($0.isLetter || $0.isNumber || $0 == "-" || $0 == ".") }) else {
        throw AdvErr("domain characters invalid")
    }

    guard let url = URL(string: "https://rdap.org/domain/\(raw)") else { throw AdvErr("url build failed") }
    var req = URLRequest(url: url)
    req.timeoutInterval = 30
    let (data, resp) = try await URLSession.shared.data(for: req)
    guard let http = resp as? HTTPURLResponse else { throw AdvErr("bad response object") }

    let bodySnippet = formatBodySnippet(data, limit: 24_576)
    return "status \(http.statusCode)\n\(bodySnippet)"
}

private func handleInterfaces() -> String {
    var interfaces: [(String, String)] = []
    var ifaddrsPtr: UnsafeMutablePointer<ifaddrs>?

    guard getifaddrs(&ifaddrsPtr) == 0 else { return "getifaddrs errno" }
    guard let head = ifaddrsPtr else { return "null ifaddrs ptr" }

    defer { freeifaddrs(head) }

    var cursor: UnsafeMutablePointer<ifaddrs>? = head
    while let node = cursor {
        defer { cursor = node.pointee.ifa_next }

        guard let sockaddr = node.pointee.ifa_addr else { continue }

        let family = Int32(sockaddr.pointee.sa_family)
        guard family != AF_LINK else { continue }

        let name = String(cString: node.pointee.ifa_name)
        let saLen = Int(sockaddr.pointee.sa_len)

        var hostBuf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let rc = getnameinfo(
            sockaddr,
            socklen_t(saLen),
            &hostBuf,
            socklen_t(hostBuf.count),
            nil,
            0,
            NI_NUMERICHOST
        )
        guard rc == 0 else { continue }

        let dotted = String(cString: hostBuf)
        if dotted.hasPrefix("fe80") || dotted == "::1" || dotted == "127.0.0.1" { continue }

        interfaces.append((name, dotted))
    }

    return interfaces
        .sorted { lhs, rhs in lhs.0 == rhs.0 ? (lhs.1 < rhs.1) : (lhs.0 < rhs.0) }
        .map { "\($0.0):\t\($0.1)" }
        .joined(separator: "\n")
}

private func stringifySSHBuffer(_ buffer: ByteBuffer) -> String {
    var mutable = buffer
    return mutable.readString(length: mutable.readableBytes) ?? ""
}

private func handleSSH(_ dict: [String: Any]) async throws -> String {
    let host = try stringRequired(dict, "host")
    let username = try stringRequired(dict, "username")
    let password = try stringRequired(dict, "password")
    let command = try stringRequired(dict, "command")
    let port = optionalInt(dict, "port", default: 22)
    guard port > 0, port < 65_536 else { throw AdvErr("port bounds") }

    let client = try await SSHClient.connect(
        host: host,
        port: port,
        authenticationMethod: SSHAuthenticationMethod.passwordBased(username: username, password: password),
        hostKeyValidator: .acceptAnything(),
        reconnect: .never,
        connectTimeout: .seconds(45)
    )

    defer {
        Task { try? await client.close() }
    }

    do {
        let bb = try await client.executeCommand(command, maxResponseSize: 512 * 1024)
        return "exit 0\n\(stringifySSHBuffer(bb))"
    } catch let cmd as SSHClient.CommandFailed {
        return "exit \(cmd.exitCode)\n(non-zero exit via Citadel)"
    } catch {
        return "SSH failure: \(error.localizedDescription)"
    }
}

private func formatBodySnippet(_ data: Data, limit: Int) -> String {
    guard limit > 0 else { return "" }
    guard !data.isEmpty else { return "(empty body)" }
    guard let text = String(data: data.prefix(limit), encoding: .utf8) else {
        return "(non-UTF8 body, \(data.count) bytes, showing hex prefix) \(data.prefix(32).map { String(format: "%02x", $0) }.joined())"
    }
    if data.count > limit {
        return text + "\n…truncated \(data.count - limit) bytes"
    }
    return text
}
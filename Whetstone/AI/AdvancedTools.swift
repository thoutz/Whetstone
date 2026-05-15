import Foundation
import Network
import Security
#if canImport(Darwin)
import Darwin.C
#endif

import Citadel
import Crypto
import NIOCore
import NetDiagnosis

// MARK: - Catalogue

enum AdvancedTools {

    static let all: [Tool] = [
        dnsLookupTool, dnsQueryTool, pingHostTool, ipGeolocationTool, portScanTool,
        httpRequestTool, whoisLookupTool, networkInterfacesTool, sshExecuteTool,
        tracerouteTool, tlsCertificateTool, tcpBannerGrabTool, networkSpeedTestTool,
        subnetInfoTool, certificateTransparencyTool,
    ]

    static func dispatch(_ call: ToolCall, credentialVault: CredentialVaultProviding? = nil) async -> ToolResult {
        let badArgs = ToolResult(callId: call.id, output: "Invalid JSON arguments.", svgPayload: nil, chipsPayload: nil)
        let unknown = ToolResult(callId: call.id, output: "Unknown advanced tool.", svgPayload: nil, chipsPayload: nil)

        guard let data = call.arguments.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return badArgs }

        do {
            switch call.name {
            case "dns_lookup":
                return ToolResult(callId: call.id, output: try await handleDNS(dict), svgPayload: nil, chipsPayload: nil)
            case "dns_query":
                return ToolResult(callId: call.id, output: try await handleDNSQuery(dict), svgPayload: nil, chipsPayload: nil)
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
                return ToolResult(callId: call.id, output: try await handleSSH(dict, credentialVault: credentialVault), svgPayload: nil, chipsPayload: nil)
            case "traceroute":
                return ToolResult(callId: call.id, output: try await handleTraceroute(dict), svgPayload: nil, chipsPayload: nil)
            case "tls_certificate":
                return ToolResult(callId: call.id, output: try await handleTLSCertificate(dict), svgPayload: nil, chipsPayload: nil)
            case "tcp_banner_grab":
                return ToolResult(callId: call.id, output: try await handleTCPBannerGrab(dict), svgPayload: nil, chipsPayload: nil)
            case "network_speed_test":
                return ToolResult(callId: call.id, output: try await handleNetworkSpeedTest(dict), svgPayload: nil, chipsPayload: nil)
            case "subnet_info":
                return ToolResult(callId: call.id, output: try handleSubnetInfo(dict), svgPayload: nil, chipsPayload: nil)
            case "certificate_transparency":
                return ToolResult(callId: call.id, output: try await handleCertificateTransparency(dict), svgPayload: nil, chipsPayload: nil)
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

    private static let dnsQueryTool = Tool(
        name: "dns_query",
        description:
            """
            DNS record lookup via DNS-over-HTTPS (Cloudflare 1.1.1.1 JSON). Returns status, Question, Answers (name/type/TTL/data). \
            Prefer for MX/TXT/CNAME/NS/PTR/SRV/CAA vs getaddrinfo-only `dns_lookup`.
            """,
        parameters: toolParameters(
            required: ["name"],
            properties: [
                "name": strProp("FQDN or query name."),
                "record_type": strProp("A (default), AAAA, MX, TXT, CNAME, NS, PTR, SRV, CAA."),
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
            Run ONE remote shell command via Citadel. Provide exactly one auth method: inline password, \
            saved_password_id, or saved_ssh_identity_id from Profile vault (each entry must allow Advanced tools). \
            Host key validation uses `.acceptAnything` (lab-only MITM risk). Vault-resolved secrets never appear in chat text; \
            remote output is returned as usual.
            """,
        parameters: toolParameters(
            required: ["host", "command"],
            properties: [
                "host": strProp("Hostname or IP."),
                "port": intProp("SSH port (default 22)."),
                "username": strProp("SSH login; optional if saved_ssh_identity_id has a Profile default username."),
                "password": strProp("Inline password (omit when using saved ids)."),
                "saved_password_id": strProp("UUID from Profile → Saved passwords."),
                "saved_ssh_identity_id": strProp("UUID from Profile → SSH identities (OpenSSH PEM, Ed25519 or RSA)."),
                "key_passphrase": strProp("Optional PEM decryption passphrase for encrypted keys."),
                "command": strProp("Escaped remote command."),
            ]
        )
    )

    private static let tracerouteTool = Tool(
        name: "traceroute",
        description:
            """
            ICMP-based hop trace (Datagram ICMP — iOS-sandbox-safe) via NetDiagnosis. Max 64 hops; 3 probes/hop by default. \
            Resolves hostname to IPv4 first, then IPv6 if needed.
            """,
        parameters: toolParameters(
            required: ["host"],
            properties: [
                "host": strProp("Hostname or IP."),
                "max_hops": intProp("1–64 (default 30)."),
                "timeout_ms": intProp("Per-probe timeout 50–10000 (default 500)."),
            ]
        )
    )

    private static let tlsCertificateTool = Tool(
        name: "tls_certificate",
        description:
            """
            TLS handshake to host:port; returns ordered chain with `subject_summary` plus SHA-256 fingerprint of DER for each certificate. \
            Minimal parse by design (`SecCertificateCopyValues` unavailable on iOS); use alongside `certificate_transparency` for issuance history.
            """,
        parameters: toolParameters(
            required: ["host"],
            properties: [
                "host": strProp("Hostname or IP (SNI uses this string)."),
                "port": intProp("TCP port (default 443)."),
            ]
        )
    )

    private static let tcpBannerGrabTool = Tool(
        name: "tcp_banner_grab",
        description:
            """
            TCP connect to host:port, optional short probe write, read up to 512 bytes for service fingerprinting (SSH, SMTP, FTP banners). \
            Lab / authorized targets only — may be interpreted hostile if mis-scoped.
            """,
        parameters: toolParameters(
            required: ["host", "port"],
            properties: [
                "host": strProp("Hostname or IP."),
                "port": intProp("TCP port."),
                "probe": strProp("Optional UTF-8 bytes sent after connect."),
                "timeout_ms": intProp("Overall timeout 100–30000 (default 3000)."),
            ]
        )
    )

    private static let networkSpeedTestTool = Tool(
        name: "network_speed_test",
        description:
            """
            Download throughput sample from Cloudflare `speed.cloudflare.com/__down` (GET with bytes query). Measures wall-clock Mbps; not a lab iperf session.
            """,
        parameters: toolParameters(
            required: [],
            properties: [
                "size_bytes": intProp("Payload size 1_000_000–50_000_000 (default 10_000_000)."),
            ]
        )
    )

    private static let subnetInfoTool = Tool(
        name: "subnet_info",
        description:
            """
            Pure IPv4 CIDR calculator: network/broadcast bounds, subnet mask dotted-decimal, usable host count (/31,/32 semantics).
            """,
        parameters: toolParameters(required: ["cidr"], properties: ["cidr": strProp("e.g. 192.168.1.0/24.")])
    )

    private static let certificateTransparencyTool = Tool(
        name: "certificate_transparency",
        description:
            """
            crt.sh certificate transparency lookup (HTTPS JSON); returns up to 50 recent entries with issuer and common-name fields where present.
            """,
        parameters: toolParameters(
            required: ["domain"],
            properties: [
                "domain": strProp("Registered domain/FQDN to search."),
                "include_subdomains": boolProp("When true, query `%.domain` wildcard pattern on crt.sh."),
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

    private static func boolProp(_ description: String) -> [String: Any] {
        ["type": "boolean", "description": description]
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

private func optionalUUID(_ dict: [String: Any], _ key: String) throws -> UUID? {
    guard let raw = dict[key] as? String else { return nil }
    let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !t.isEmpty else { return nil }
    guard let u = UUID(uuidString: t) else { throw AdvErr("\(key) must be UUID string") }
    return u
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

private func coerceBool(_ any: Any?) -> Bool {
    if let b = any as? Bool { return b }
    if let i = any as? Int { return i != 0 }
    if let s = any as? String {
        switch s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "y": return true
        default: return false
        }
    }
    return false
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

private func resolveSSHUsername(
    dict: [String: Any],
    savedSSHIdentityId: UUID?,
    credentialVault: CredentialVaultProviding?
) async throws -> String {
    if let explicit = optionalString(dict, "username"), !explicit.isEmpty {
        return explicit
    }
    guard let sid = savedSSHIdentityId else {
        throw AdvErr("username required")
    }
    guard let credentialVault else {
        throw AdvErr("credential vault unavailable — cannot read SSH identity defaults")
    }
    guard let du = await credentialVault.defaultUsernameForSSHIdentity(id: sid), !du.isEmpty else {
        throw AdvErr("username missing — pass username or set default on the SSH vault entry")
    }
    return du
}

private func sshAuthenticationMethod(
    dict: [String: Any],
    username: String,
    credentialVault: CredentialVaultProviding?
) async throws -> SSHAuthenticationMethod {
    let inlinePassword = optionalString(dict, "password")
    let savedPwdId = try optionalUUID(dict, "saved_password_id")
    let savedSSHId = try optionalUUID(dict, "saved_ssh_identity_id")

    let passphraseStr = optionalString(dict, "key_passphrase")
    let passphraseData = passphraseStr.map { Data($0.utf8) }

    var modes = 0
    if inlinePassword != nil { modes += 1 }
    if savedPwdId != nil { modes += 1 }
    if savedSSHId != nil { modes += 1 }
    guard modes == 1 else {
        throw AdvErr("Provide exactly one of password, saved_password_id, or saved_ssh_identity_id.")
    }

    if let inlinePassword {
        return SSHAuthenticationMethod.passwordBased(username: username, password: inlinePassword)
    }
    if let savedPwdId {
        guard let credentialVault else { throw AdvErr("credential vault unavailable") }
        let pwd = try await credentialVault.sshPasswordSecretForAgentUse(id: savedPwdId)
        return SSHAuthenticationMethod.passwordBased(username: username, password: pwd)
    }
    if let savedSSHId {
        guard let credentialVault else { throw AdvErr("credential vault unavailable") }
        let pem = try await credentialVault.sshPrivateKeyPEMForAgentUse(id: savedSSHId)
        let keyType = try SSHKeyDetection.detectPrivateKeyType(from: pem)
        switch keyType {
        case .ed25519:
            let pk = try Curve25519.Signing.PrivateKey(sshEd25519: pem, decryptionKey: passphraseData)
            return SSHAuthenticationMethod.ed25519(username: username, privateKey: pk)
        case .rsa:
            let pk = try Insecure.RSA.PrivateKey(sshRsa: pem, decryptionKey: passphraseData)
            return SSHAuthenticationMethod.rsa(username: username, privateKey: pk)
        default:
            throw AdvErr("SSH key type \(keyType.description) not supported — use Ed25519 or RSA OpenSSH PEM.")
        }
    }
    throw AdvErr("No SSH authentication method resolved")
}

private func handleSSH(_ dict: [String: Any], credentialVault: CredentialVaultProviding?) async throws -> String {
    let host = try stringRequired(dict, "host")
    let command = try stringRequired(dict, "command")

    let savedSSHId = try optionalUUID(dict, "saved_ssh_identity_id")
    let username = try await resolveSSHUsername(dict: dict, savedSSHIdentityId: savedSSHId, credentialVault: credentialVault)

    let port = optionalInt(dict, "port", default: 22)
    guard port > 0, port < 65_536 else { throw AdvErr("port bounds") }

    let authMethod = try await sshAuthenticationMethod(dict: dict, username: username, credentialVault: credentialVault)

    let client = try await SSHClient.connect(
        host: host,
        port: port,
        authenticationMethod: authMethod,
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

// MARK: - Advanced networking (expanded tools)

private let dnsQueryAllowedTypes: Set<String> = [
    "A", "AAAA", "MX", "TXT", "CNAME", "NS", "PTR", "SRV", "CAA",
]

private func handleDNSQuery(_ dict: [String: Any]) async throws -> String {
    let rawName = try stringRequired(dict, "name")
    let typeRaw = (optionalString(dict, "record_type") ?? "A").uppercased()
    guard dnsQueryAllowedTypes.contains(typeRaw) else {
        throw AdvErr("record_type must be one of \(dnsQueryAllowedTypes.sorted().joined(separator: ", "))")
    }

    var components = URLComponents(string: "https://cloudflare-dns.com/dns-query")!
    components.queryItems = [
        URLQueryItem(name: "name", value: rawName),
        URLQueryItem(name: "type", value: typeRaw),
    ]
    guard let url = components.url else { throw AdvErr("bad dns URL") }

    var req = URLRequest(url: url)
    req.setValue("application/dns-json", forHTTPHeaderField: "accept")
    req.timeoutInterval = 25

    let (data, response) = try await URLSession.shared.data(for: req)
    guard let http = response as? HTTPURLResponse else { throw AdvErr("no HTTP response") }
    let snippet = formatBodySnippet(data, limit: 65_536)
    return "HTTP \(http.statusCode)\n\(snippet)"
}

private func pingProbeSummary(_ result: NetDiagnosis.Pinger.PingResult) -> String {
    switch result {
    case let .pong(r):
        return "\(r.from) \(String(format: "%.2fms", r.rtt * 1000))"
    case let .hopLimitExceeded(r):
        return "\(r.from) \(String(format: "%.2fms", r.rtt * 1000))"
    case .timeout:
        return "*"
    case let .failed(e):
        return "fail:\(e.localizedDescription)"
    }
}

private func resolveIPAddrForTrace(host: String) throws -> IPAddr {
    if let v4 = IPAddr.create(host, addressFamily: .ipv4) { return v4 }
    if let v6 = IPAddr.create(host, addressFamily: .ipv6) { return v6 }
    let v4List = try IPAddr.resolve(domainName: host, addressFamily: .ipv4)
    if let first = v4List.first { return first }
    let v6List = try IPAddr.resolve(domainName: host, addressFamily: .ipv6)
    guard let v6 = v6List.first else { throw AdvErr("could not resolve host for traceroute") }
    return v6
}

private func tracerouteStatusLine(_ status: NetDiagnosis.Pinger.TraceStatus) -> String {
    switch status {
    case .traced:
        return "trace_complete: reached_target"
    case .maxHopExceeded:
        return "trace_complete: max_hops_exceeded"
    case .stoped:
        return "trace_complete: stopped"
    case let .failed(err):
        return "trace_complete: failed — \(err.localizedDescription)"
    }
}

private func handleTraceroute(_ dict: [String: Any]) async throws -> String {
    let host = try stringRequired(dict, "host")
    let maxHops = max(1, min(optionalInt(dict, "max_hops", default: 30), 64))
    let timeoutMs = max(50, min(optionalInt(dict, "timeout_ms", default: 500), 10_000))
    let timeoutSec = TimeInterval(timeoutMs) / 1000.0

    let remote = try resolveIPAddrForTrace(host: host)
    let pinger = try NetDiagnosis.Pinger(remoteAddr: remote)

    return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
        var lines: [String] = []
        lines.append("traceroute to \(host) (\(remote)) max_hops=\(maxHops) timeout_ms=\(timeoutMs)")

        pinger.trace(
            initHop: 1,
            maxHop: UInt8(clamping: maxHops),
            packetCount: 3,
            timeOut: timeoutSec,
            tracePacketCallback: nil,
            onTraceComplete: { resultMap, status in
                for pair in resultMap {
                    let hop = pair.key
                    let probes = pair.value.map(pingProbeSummary).joined(separator: "  ")
                    lines.append(String(format: "%2u  %@", hop, probes))
                }
                lines.append(tracerouteStatusLine(status))
                if case let .failed(err) = status {
                    cont.resume(throwing: err)
                } else {
                    cont.resume(returning: lines.joined(separator: "\n"))
                }
            }
        )
    }
}

private final class TLSInspectionSession: NSObject, URLSessionTaskDelegate {
    private let lock = NSLock()
    private var collected: [SecCertificate] = []

    func chain() -> [SecCertificate] {
        lock.lock()
        defer { lock.unlock() }
        return collected
    }

    lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            if let certs = SecTrustCopyCertificateChain(trust) as? [SecCertificate] {
                lock.lock()
                collected = certs
                lock.unlock()
            }
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}

private func tlsURL(host: String, port: Int) throws -> URL {
    var comps = URLComponents()
    comps.scheme = "https"
    comps.host = host
    comps.path = "/"
    if port > 0, port != 443 {
        comps.port = port
    }
    guard let url = comps.url else { throw AdvErr("bad TLS URL") }
    return url
}

private func describeCertificateFields(_ cert: SecCertificate, index: Int) -> String {
    var lines: [String] = []
    lines.append("[cert \(index + 1)]")
    if let summary = SecCertificateCopySubjectSummary(cert) as String? {
        lines.append("subject_summary: \(summary)")
    }
    let der = SecCertificateCopyData(cert) as Data
    lines.append("der_size_bytes: \(der.count)")
    let digest = SHA256.hash(data: der)
    lines.append("sha256_der: \(digest.map { String(format: "%02x", $0) }.joined())")
    return lines.joined(separator: "\n")
}

private func handleTLSCertificate(_ dict: [String: Any]) async throws -> String {
    let host = try stringRequired(dict, "host")
    let port = max(1, min(optionalInt(dict, "port", default: 443), 65_535))
    let url = try tlsURL(host: host, port: port)

    let inspector = TLSInspectionSession()
    let (_, response) = try await inspector.session.data(from: url)
    guard let http = response as? HTTPURLResponse else { throw AdvErr("non-HTTP/TLS response") }

    let chain = inspector.chain()
    var out: [String] = []
    out.append("HTTP status (post-handshake): \(http.statusCode)")
    out.append("certificates_in_chain: \(chain.count)")
    for (idx, cert) in chain.enumerated() {
        out.append(describeCertificateFields(cert, index: idx))
    }
    return out.joined(separator: "\n\n")
}

private func formatBannerData(_ data: Data) -> String {
    let limit = 512
    guard !data.isEmpty else { return "(empty)" }
    let prefix = data.prefix(limit)
    if let text = String(data: prefix, encoding: .utf8) {
        let cleaned = text.replacingOccurrences(of: "\r", with: "\\r").replacingOccurrences(of: "\n", with: "\\n")
        if data.count > limit { return cleaned + "\n…truncated \(data.count - limit) bytes" }
        return cleaned
    }
    return "(non-UTF8 \(data.count) B) \(prefix.map { String(format: "%02x", $0) }.joined(separator: " "))"
}

private func handleTCPBannerGrab(_ dict: [String: Any]) async throws -> String {
    let host = try stringRequired(dict, "host")
    let portNum = optionalInt(dict, "port", default: 80)
    guard portNum > 0, portNum < 65_536 else { throw AdvErr("port bounds") }
    let timeoutMs = max(100, min(optionalInt(dict, "timeout_ms", default: 3000), 30_000))
    let probe = optionalString(dict, "probe")

    guard let nwPort = NWEndpoint.Port(rawValue: UInt16(clamping: portNum)) else { throw AdvErr("bad port") }
    let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: nwPort)

    return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
        let conn = NWConnection(to: endpoint, using: NWParameters.tcp)
        let queue = DispatchQueue(label: "whetstone.banner")
        var finished = false

        func finish(_ result: Result<String, Error>) {
            queue.async {
                guard !finished else { return }
                finished = true
                conn.cancel()
                switch result {
                case let .success(s): cont.resume(returning: s)
                case let .failure(e): cont.resume(throwing: e)
                }
            }
        }

        func receiveBanner() {
            conn.receive(minimumIncompleteLength: 1, maximumLength: 512) { data, _, isComplete, error in
                if let error {
                    finish(.failure(error))
                    return
                }
                if let data, !data.isEmpty {
                    finish(.success(formatBannerData(data)))
                    return
                }
                if isComplete {
                    finish(.success("(eof before data)"))
                } else {
                    finish(.success("(empty)"))
                }
            }
        }

        conn.stateUpdateHandler = { state in
            switch state {
            case .ready:
                if let probe, !probe.isEmpty, let data = probe.data(using: .utf8) {
                    conn.send(content: data, completion: .contentProcessed { error in
                        if let error {
                            finish(.failure(error))
                            return
                        }
                        receiveBanner()
                    })
                } else {
                    receiveBanner()
                }
            case let .failed(error):
                finish(.failure(error))
            default:
                break
            }
        }

        conn.start(queue: queue)
        queue.asyncAfter(deadline: .now() + .milliseconds(timeoutMs)) {
            finish(.failure(AdvErr("tcp_banner_grab timeout")))
        }
    }
}

private func handleNetworkSpeedTest(_ dict: [String: Any]) async throws -> String {
    let sizeBytes = max(1_000_000, min(optionalInt(dict, "size_bytes", default: 10_000_000), 50_000_000))
    guard let url = URL(string: "https://speed.cloudflare.com/__down?bytes=\(sizeBytes)") else {
        throw AdvErr("bad speed URL")
    }
    var req = URLRequest(url: url)
    req.timeoutInterval = 120

    let start = CFAbsoluteTimeGetCurrent()
    let (data, response) = try await URLSession.shared.data(for: req)
    guard let http = response as? HTTPURLResponse else { throw AdvErr("bad response") }
    let elapsed = CFAbsoluteTimeGetCurrent() - start
    let bytes = data.count
    let Mbps = elapsed > 0 ? (Double(bytes) * 8 / 1_000_000 / elapsed) : 0 // decimal Mbps
    return """
    HTTP \(http.statusCode)
    bytes_received: \(bytes) (requested \(sizeBytes))
    seconds: \(String(format: "%.3f", elapsed))
    download_Mbps_approx: \(String(format: "%.2f", Mbps))
    note: CDN single-stream sample; varies by path and congestion.
    """
}

private func parseDottedIPv4HostOrder(_ s: String) throws -> UInt32 {
    let comps = s.split(separator: ".")
    guard comps.count == 4 else { throw AdvErr("invalid IPv4 in CIDR") }
    var acc: UInt32 = 0
    for piece in comps {
        guard let octet = Int(piece), octet >= 0, octet <= 255 else { throw AdvErr("bad IPv4 octet") }
        acc = (acc << 8) | UInt32(octet)
    }
    return acc
}

private func formatDottedIPv4(hostOrder u: UInt32) -> String {
    String(format: "%u.%u.%u.%u", (u >> 24) & 0xff, (u >> 16) & 0xff, (u >> 8) & 0xff, u & 0xff)
}

private func ipv4SubnetMask(prefix: Int) -> UInt32 {
    if prefix <= 0 { return 0 }
    if prefix >= 32 { return .max }
    return ~((UInt32(1) << UInt32(32 - prefix)) &- 1)
}

private func handleSubnetInfo(_ dict: [String: Any]) throws -> String {
    let raw = try stringRequired(dict, "cidr").trimmingCharacters(in: .whitespacesAndNewlines)
    let parts = raw.split(separator: "/")
    guard parts.count == 2 else { throw AdvErr("expected CIDR e.g. 10.0.0.1/24") }
    guard let prefix = Int(String(parts[1])), prefix >= 0, prefix <= 32 else { throw AdvErr("prefix 0–32 required") }

    let ipHost = try parseDottedIPv4HostOrder(String(parts[0]))
    let maskHost = ipv4SubnetMask(prefix: prefix)
    let networkHost = ipHost & maskHost
    let broadcastHost = networkHost | (~maskHost)

    let totalHosts: UInt64 = if prefix >= 32 {
        1
    } else {
        UInt64(1) << UInt64(32 - prefix)
    }
    let usableHosts: UInt64
    switch prefix {
    case 32: usableHosts = 1
    case 31: usableHosts = min(2, totalHosts)
    default: usableHosts = totalHosts >= 2 ? totalHosts - 2 : 0
    }

    let firstHost: UInt32
    let lastHost: UInt32
    switch prefix {
    case 32:
        firstHost = networkHost
        lastHost = broadcastHost
    case 31:
        firstHost = networkHost
        lastHost = broadcastHost
    default:
        firstHost = networkHost &+ 1
        lastHost = broadcastHost &- 1
    }

    return """
    cidr: \(raw)
    network: \(formatDottedIPv4(hostOrder: networkHost))
    broadcast: \(formatDottedIPv4(hostOrder: broadcastHost))
    subnet_mask: \(formatDottedIPv4(hostOrder: maskHost))
    first_host: \(formatDottedIPv4(hostOrder: firstHost))
    last_host: \(formatDottedIPv4(hostOrder: lastHost))
    total_addresses: \(totalHosts)
    usable_hosts_estimate: \(usableHosts)
    """
}

private func handleCertificateTransparency(_ dict: [String: Any]) async throws -> String {
    let domain = try stringRequired(dict, "domain").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let includeSub = coerceBool(dict["include_subdomains"])
    let q = includeSub ? "%.\(domain)" : domain

    var comps = URLComponents(string: "https://crt.sh/")!
    comps.queryItems = [
        URLQueryItem(name: "q", value: q),
        URLQueryItem(name: "output", value: "json"),
    ]
    guard let url = comps.url else { throw AdvErr("bad crt.sh URL") }
    var req = URLRequest(url: url)
    req.timeoutInterval = 60

    let (data, response) = try await URLSession.shared.data(for: req)
    guard let http = response as? HTTPURLResponse else { throw AdvErr("bad response") }
    guard let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
        let body = formatBodySnippet(data, limit: 4096)
        return "HTTP \(http.statusCode) (non-array JSON)\n\(body)"
    }

    let cap = raw.prefix(50)
    var lines: [String] = []
    lines.append("HTTP \(http.statusCode) rows_shown: \(cap.count) of \(raw.count)")
    for (i, row) in cap.enumerated() {
        let issuer = crtFieldString(row, "issuer_name") ?? crtFieldString(row, "issuer_ca_id") ?? "—"
        let name = crtFieldString(row, "common_name") ?? crtFieldString(row, "name_value") ?? "—"
        let nb = crtFieldString(row, "not_before") ?? "—"
        let na = crtFieldString(row, "not_after") ?? "—"
        lines.append("[\(i + 1)] issuer: \(issuer) | cn/name: \(name) | \(nb) → \(na)")
    }
    return lines.joined(separator: "\n")
}

private func crtFieldString(_ row: [String: Any], _ key: String) -> String? {
    guard let v = row[key] else { return nil }
    if let s = v as? String { return s }
    return String(describing: v)
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
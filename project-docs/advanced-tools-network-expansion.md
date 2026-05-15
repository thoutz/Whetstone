# Advanced networking tools expansion (May 2026)

Journal for adding **seven** Advanced Mode agent tools (`AdvancedTools.swift`), one SwiftPM dependency, prompt/doc updates, and feasibility notes for tool requests that stay off-device.

## Goals

- Enrich Advanced Mode with DNS-over-HTTPS, ICMP traceroute, TLS chain fingerprints, TCP banner reads, CDN download throughput sampling, IPv4 subnet math, and crt.sh certificate transparency.
- Keep **Standard** mode unchanged (still `render_construction` + `render_chips` only).
- Stay within iOS sandbox constraints (no `SOCK_RAW`, no bundled Nmap/Masscan/iperf server).

## SwiftPM: NetDiagnosis

- **Package:** `https://github.com/453jerry/NetDiagnosis.git`
- **Product linked to app target:** `NetDiagnosis` (for `Pinger.trace` ICMP traceroute / hop limits).
- **Xcode steps:** `File → Add Package Dependencies…` is equivalent to the committed `project.pbxproj` edits (`XCRemoteSwiftPackageReference` + `XCSwiftPackageProductDependency` + Frameworks build phase entry).
- **Resolved version (see `Package.resolved`):** `1.1.2` at time of implementation; graph also pins **RxSwift** and **swift-collections** as transitive dependencies (only `NetDiagnosis` is linked to Whetstone).

## Code changes

| Area | Change |
|------|--------|
| [`Whetstone/AI/AdvancedTools.swift`](../Whetstone/AI/AdvancedTools.swift) | `import Security`, `import NetDiagnosis`; extended `all` tool list; `dispatch` switch cases; seven new `Tool` schemas + handlers; `coerceBool`; `crtFieldString`; certificate dump via `SecCertificateCopyData` + **Crypto** `SHA256` ( `SecCertificateCopyValues` is not available on iOS ). |
| [`Whetstone.xcodeproj/project.pbxproj`](../Whetstone.xcodeproj/project.pbxproj) | NetDiagnosis package reference, product dependency, Frameworks link. |
| [`Whetstone/Resources/advanced_system_prompt.txt`](../Whetstone/Resources/advanced_system_prompt.txt) | Mentions all advanced tools; operational guidance (DoH vs `dns_lookup`, CT row cap, speed test vs iperf, SSH for Linux-only tools). |
| [`project-docs/advanced-agent-mode.md`](advanced-agent-mode.md) | Tool count **eight → fifteen**; Citadel + NetDiagnosis SPM notes; expanded `AdvancedTools` bullet. |

## New tool summary

| Tool | Behavior |
|------|-----------|
| `dns_query` | GET `https://cloudflare-dns.com/dns-query` with `Accept: application/dns-json`; types A, AAAA, MX, TXT, CNAME, NS, PTR, SRV, CAA. |
| `traceroute` | `NetDiagnosis.Pinger(remoteAddr:).trace` — IPv4 resolution preferred, then IPv6; `max_hops` 1–64, `timeout_ms` per probe. |
| `tls_certificate` | Ephemeral `URLSession` delegate captures `SecTrustCopyCertificateChain`; each cert: `SecCertificateCopySubjectSummary` + SHA-256 of DER. |
| `tcp_banner_grab` | `NWConnection` TCP; optional UTF-8 probe send; read up to 512 bytes; overall `timeout_ms`. |
| `network_speed_test` | GET `https://speed.cloudflare.com/__down?bytes=…` (1M–50M); wall-clock Mbps (decimal). |
| `subnet_info` | IPv4 CIDR only — network, broadcast, mask, first/last host, total addresses, usable estimate. |
| `certificate_transparency` | GET `https://crt.sh/?q=…&output=json`; optional `%.domain` wildcard; show up to **50** rows. |

## Feasibility (requested but not on-device)

- **Nmap / Masscan / raw SYN scans:** require capabilities iOS does not expose to App Store apps → use `ssh_execute` on a student-controlled Linux host.
- **Nessus / OpenVAS / GNS3 / Quagga / Ansible control plane:** server or desktop stacks — same SSH guidance.
- **Full `dig` / DNSrecon parity:** `dns_query` covers common record types via DoH; zone transfer / zone walking is out of scope and usually off-limits without authorization.

## Verification

- `xcodebuild -project Whetstone.xcodeproj -scheme Whetstone -destination 'generic/platform=iOS Simulator' build` — **BUILD SUCCEEDED** (after replacing macOS-only cert parsing with DER + SHA-256).

## Validation record (plan audit)

**Date:** 2026-05-15. Cross-check against the Advanced Networking Tools expansion plan and the companion **Validate Advanced Tools Work** audit checklist (Cursor plan; not committed to this repo).

### Section 1 — Structural (static)

| Check | Result |
|-------|--------|
| `AdvancedTools.all` + `dispatch` contain 8 legacy + 7 new tools (**15** total) | **PASS** — see `dns_query` … `certificate_transparency` in [`AdvancedTools.swift`](../Whetstone/AI/AdvancedTools.swift). |
| NetDiagnosis in `project.pbxproj` (remote ref, product dep, Frameworks) | **PASS** — `https://github.com/453jerry/NetDiagnosis.git`, product `NetDiagnosis`. |
| `advanced_system_prompt.txt` mentions new tools + limits | **PASS** — DoH vs `dns_lookup`, `traceroute` vs TCP `ping_host`, TLS/CT/speed-test notes, SSH for Linux CLIs. |
| `advanced-tools-network-expansion.md` + `advanced-agent-mode.md` | **PASS** — fifteen tools; Citadel + NetDiagnosis SPM; dispatch list documented. |
| `ConversationStore` uses `MentorTools.all + AdvancedTools.all` when Advanced | **PASS** — `effectiveModeSnapshot == .advanced`. |

### Section 2 — Per-tool vs plan

| Tool | Plan | Result |
|------|------|--------|
| `dns_query` | Cloudflare DoH JSON; record allow-list | **PASS** — `cloudflare-dns.com`, `application/dns-json`, `dnsQueryAllowedTypes`. |
| `traceroute` | NetDiagnosis ICMP; host/max_hops/timeout_ms | **PASS** — `Pinger(remoteAddr:).trace` with clamps in handler. |
| `tls_certificate` | Original plan: `SecCertificateCopyValues`/SAN/expiry detail | **DEVIATION DOCUMENTED — PASS (as shipped)** — iOS lacks practical `SecCertificateCopyValues`; implementation uses **`SecTrustCopyCertificateChain`**, **`SecCertificateCopySubjectSummary`**, DER + **SHA256** (`describeCertificateFields`). Tool `description` + `advanced_system_prompt.txt` state this explicitly. |
| `tcp_banner_grab` | NWConnection, optional probe, ≤512 B | **PASS** — `receive(..., maximumLength: 512)`. |
| `network_speed_test` | Cloudflare `__down`, size clamp, Mbps | **PASS** — `speed.cloudflare.com/__down`, 1M–50M, Mbps line. |
| `subnet_info` | IPv4 CIDR / UInt32 | **PASS** — `ipv4SubnetMask`, dotted formatting, /31 / /32 handling. |
| `certificate_transparency` | crt.sh JSON, `%.` wildcard, cap 50 | **PASS** — `crt.sh`, `include_subdomains`, `raw.prefix(50)`. |

### Section 3 — `Package.resolved`

- **PASS** — pins `netdiagnosis` (v1.1.2 at last resolve); transitive `rxswift`, `swift-collections` present (NetDiagnosis dependency graph); app target links only `NetDiagnosis` per `advanced-agent-mode.md`.

### Section 4 — Full-scheme build

- **FAIL (unrelated to Advanced Tools)** — `xcodebuild -project Whetstone.xcodeproj -scheme Whetstone -destination 'generic/platform=iOS Simulator' build` fails compiling [`ChatView.swift`](../Whetstone/Chat/ChatView.swift): `FocusState<Bool>.Binding` vs `Binding<Bool>` (lines ~432, ~577), and `PastableTextEditor` missing `applyFocus` (~799). **No errors reported in `AdvancedTools.swift` for this build.** Resolve ChatView before treating the app as green.

### Section 5 — Optional runtime smoke

- **Not run** in this audit (requires Simulator + Advanced entitlement + network). Use the seven smoke cases in the validation plan when `ChatView` builds cleanly.

### Summary

- **Advanced networking deliverable vs codebase:** **PASS** (static + per-tool).
- **TLS:** intentional deviation from original plan text; aligned with iOS and documented in code + prompts + this journal.
- **Gate:** full product build currently blocked by **ChatView** compile errors.

## Follow-ups (optional)

- Add `NSLocalNetworkUsageDescription` if LAN targets trigger the local-network privacy prompt.
- Structured redaction of tool args in logs (passwords, probes).
- Consider tightening `tls_certificate` to cancel the HTTP transaction after trust capture (today relies on default handling + small response read).

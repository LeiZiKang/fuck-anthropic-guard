import Foundation
import CryptoKit

/// Produced by the host's read-only local runtime auditor, and transported only
/// through the signature-constrained host XPC session. Not imported from JSON/UI.
struct LocalPolicyEvidence: Codable {
    let challenge: String
    let scopeDigest: String
    let activeProfileDigest: String
    let checkedAt: TimeInterval
    let checkedClock: TimeInterval
    let expiresClock: TimeInterval
    let dedicatedPortVerified: Bool
    let listenerVerified: Bool
    let runtimeStable: Bool
    var surgeOwner: ProcessIdentity? = nil
}
enum PolicyEvidenceVerifier {
    static func valid(_ value: LocalPolicyEvidence?, challenge: String, scope: String, profileDigest: String,
                      now: Date, uptime: TimeInterval) -> Bool {
        guard let value, !challenge.isEmpty, value.challenge == challenge, value.scopeDigest == scope,
              profileDigest.count == 64, value.activeProfileDigest == profileDigest,
              value.checkedAt.isFinite, value.checkedClock.isFinite, value.expiresClock.isFinite,
              now.timeIntervalSince1970 >= value.checkedAt, now.timeIntervalSince1970 - value.checkedAt < 6,
              uptime >= value.checkedClock, value.expiresClock > uptime,
              value.expiresClock - value.checkedClock <= 6, value.dedicatedPortVerified, value.listenerVerified, value.runtimeStable, value.surgeOwner != nil else { return false }
        return true
    }
    static func scope(proxy: ProxyEndpoint, bundles: [String], exits: [String]) -> String {
        let value = ["ccw-proxy-scope-v2", proxy.kind, proxy.address, String(proxy.port),
            Set(bundles).sorted().joined(separator: ","), Set(exits).sorted().joined(separator: ","),
            FilterDecisionState.domains.sorted().joined(separator: ","), "Q6L2SF6YDW:com.anthropic.*", "verified-and-sticky-descendants+unknown-provenance-gap"].joined(separator: "\n")
        return digest(Data(value.utf8))
    }
    static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}

/// Deliberately narrow contract. Unknown syntax cannot prove a route.
enum SurgeContract {
    static func validate(profile: String, requirements: RouteRequirements) -> Bool {
        guard requirements.localAuditConfigured, profile.utf8.count <= 2_000_000, let endpoint = requirements.proxy, ["http", "socks"].contains(endpoint.kind),
              ![6152, 6153].contains(endpoint.port),
              !requirements.surgePolicy.isEmpty, !["DIRECT", "REJECT", "PROXY"].contains(requirements.surgePolicy.uppercased()),
              PolicyEvidenceVerifier.digest(Data(profile.utf8)) == requirements.expectedProfileDigest else { return false }
        var sections: [String: [String]] = [:]; var section = ""
        for raw in profile.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") || line.hasPrefix("//") { continue }
            if line.hasPrefix("["), line.hasSuffix("]") {
                section = String(line.dropFirst().dropLast()).lowercased()
                guard sections[section] == nil else { return false }; sections[section] = []; continue
            }
            guard !section.isEmpty, !["!", "$", "%"].contains(String(line.prefix(1))) else { return false }
            sections[section, default: []].append(line)
        }
        guard Set(sections.keys).isSubset(of: ["general", "proxy", "proxy group", "rule", "host"]) else { return false }
        for unsupported in ["script", "url rewrite", "header rewrite", "body rewrite", "module", "mitm", "subnet"] {
            if sections[unsupported]?.isEmpty == false { return false }
        }
        func pairs(_ key: String) -> [String: String]? {
            var result: [String: String] = [:]
            for line in sections[key] ?? [] {
                guard let separator = line.firstIndex(of: "=") else { return nil }
                let name = line[..<separator].trimmingCharacters(in: .whitespaces).lowercased()
                guard result[name] == nil else { return nil }
                result[name] = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
            }
            return result
        }
        func csv(_ value: String) -> [String] { value.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) } }
        guard let general = pairs("general"), let proxies = pairs("proxy"), let groups = pairs("proxy group"),
              let listeners = general[endpoint.kind == "http" ? "http-listen" : "socks5-listen"].map(csv), listeners.count >= 2, listeners.contains(endpoint.label),
              let firstRule = sections["rule"]?.first,
              csv(firstRule) == ["IN-PORT", String(endpoint.port), requirements.surgePolicy] else { return false }
        var node = requirements.surgePolicy.lowercased()
        if let group = groups[node] {
            let fields = csv(group)
            guard fields.count == 2, fields[0].lowercased() == "select", groups[fields[1].lowercased()] == nil else { return false }
            node = fields[1].lowercased()
        }
        guard let definition = proxies[node] else { return false }
        let parts = csv(definition)
        guard parts.count >= 3, parts[0].lowercased() == "hysteria2", !parts[1].isEmpty, !parts[2].isEmpty else { return false }
        var options: [String: String] = [:]
        for option in parts.dropFirst(3) {
            guard let separator = option.firstIndex(of: "=") else { return false }
            let name = option[..<separator].trimmingCharacters(in: .whitespaces).lowercased()
            guard ["password", "sni", "skip-cert-verify", "server-cert-fingerprint-sha256"].contains(name), options[name] == nil else { return false }
            options[name] = option[option.index(after: separator)...].trimmingCharacters(in: .whitespaces)
        }
        return (options["skip-cert-verify"]?.lowercased() ?? "false") == "false"

    }
}

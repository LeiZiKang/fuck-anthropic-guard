import Foundation
import Security

/// Only fixed read-only commands of the signature-verified local Surge CLI.
/// Effective profiles may contain credentials: parse in memory, never log them.
final class LocalSurgeAuditor {
    private let queue = DispatchQueue(label: "CCW.LocalPolicyAudit", qos: .utility)
    private var generation = 0
    private var busy = false
    private var lastAttempt: TimeInterval = -.infinity
    private(set) var evidence: LocalPolicyEvidence?
    private(set) var reason = "waiting"
    var onUpdate: (() -> Void)?
    func invalidate() { generation += 1; evidence = nil; lastAttempt = -.infinity }
    func refresh(requirements: RouteRequirements, challenge: String, scope: String) {
        guard !busy, !challenge.isEmpty, requirements.localAuditConfigured, LeaseClock.now - lastAttempt >= 2 else { return }
        busy = true; lastAttempt = LeaseClock.now; let epoch = generation
        queue.async {
            let result = Self.inspect(requirements: requirements, challenge: challenge, scope: scope)
            DispatchQueue.main.async {
                self.busy = false
                guard self.generation == epoch else { return }
                self.evidence = result.evidence; self.reason = result.reason
                self.onUpdate?()
            }
        }
    }
    private static let cli = "/Applications/Surge.app/Contents/Applications/surge-cli"
    private static let teamRequirement = "anchor apple generic and certificate leaf[subject.OU] = \"YCKFLA6N72\""
    static func verifiedCLI() -> Bool {
        var code: SecStaticCode?; var requirement: SecRequirement?
        return SecStaticCodeCreateWithPath(URL(fileURLWithPath: cli) as CFURL, [], &code) == errSecSuccess
            && SecRequirementCreateWithString((teamRequirement + " and identifier \"surge-cli\"") as CFString, [], &requirement) == errSecSuccess
            && code.map { SecStaticCodeCheckValidity($0, [], requirement) == errSecSuccess } == true
    }
    static func json(_ arguments: [String]) -> [String: Any]? {
        let result = CommandRunner.run(cli, ["--raw"] + arguments, timeout: 3,
            environment: ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LANG": "C"])
        guard result.status == 0, result.output.count <= 4_000_000 else { return nil }
        return (try? JSONSerialization.jsonObject(with: result.output)) as? [String: Any]
    }
    private static func stableStatus(_ json: [String: Any]?) -> Data? {
        guard let json, (json["mode"] as? String)?.lowercased() == "rule",
              let features = json["features"] as? [String: Any],
              ["mitm", "scripting", "rewrite"].allSatisfy({ (features[$0] as? Bool) == false }),
              let profile = json["profile"] as? String, let started = json["start-time"] as? Double else { return nil }
        return try? JSONSerialization.data(withJSONObject: ["profile": profile, "started": started, "mode": "rule", "features": features], options: .sortedKeys)
    }
    private static func temporaryRulesEmpty() -> Bool { (json(["dump", "temp-rule"])?["rules"] as? [Any])?.isEmpty == true }
    static func listener(_ endpoint: ProxyEndpoint) -> ProcessIdentity? {
        let result = CommandRunner.run("/usr/sbin/lsof", ["-nP", "-a", "-iTCP:\(endpoint.port)", "-sTCP:LISTEN", "-Fpn"], timeout: 3)
        guard result.status == 0 else { return nil }
        var pid: Int32?; var matches = Set<Int32>()
        for line in String(decoding: result.output, as: UTF8.self).split(separator: "\n") {
            if line.first == "p" { pid = Int32(line.dropFirst()) }
            if line == "n" + endpoint.label, let pid { matches.insert(pid) }
        }
        guard matches.count == 1, let pid = matches.first, let identity = captureProcessIdentity(pid: pid) else { return nil }
        var code: SecCode?; var requirement: SecRequirement?
        guard SecCodeCopyGuestWithAttributes(nil, [kSecGuestAttributePid as String: NSNumber(value: pid)] as CFDictionary, [], &code) == errSecSuccess,
              SecRequirementCreateWithString((teamRequirement + " and identifier \"com.nssurge.surge-mac\"") as CFString, [], &requirement) == errSecSuccess,
              code.map({ SecCodeCheckValidity($0, [], requirement) == errSecSuccess }) == true,
              captureProcessIdentity(pid: pid) == identity else { return nil }
        return identity
    }
    private static func effectiveRuleMatches(_ requirements: RouteRequirements) -> Bool {
        guard let first = (json(["dump", "rule"])?["rules"] as? [String])?.first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty && !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#") }), let endpoint = requirements.proxy else { return false }
        return first.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) } == ["IN-PORT", String(endpoint.port), requirements.surgePolicy]
    }
    static func inspect(requirements: RouteRequirements, challenge: String, scope: String) -> (evidence: LocalPolicyEvidence?, reason: String) {
        let began = LeaseClock.now
        let wallBegan = Date().timeIntervalSince1970
        guard requirements.localAuditConfigured, let endpoint = requirements.proxy else { return (nil, "requirements-incomplete") }
        guard verifiedCLI() else { return (nil, "cli-signature-unverified") }
        guard let before = stableStatus(json(["status"])) else { return (nil, "mode-or-interception-unverified") }
        guard temporaryRulesEmpty() else { return (nil, "temporary-rules-present-or-unknown") }
        guard let listenerBefore = listener(endpoint) else { return (nil, "dedicated-listener-unverified") }
        guard let profile = json(["dump", "profile", "effective"])?["profile"] as? String,
              SurgeContract.validate(profile: profile, requirements: requirements), effectiveRuleMatches(requirements) else { return (nil, "effective-contract-unverified") }
        guard let afterProfile = json(["dump", "profile", "effective"])?["profile"] as? String,
              PolicyEvidenceVerifier.digest(Data(afterProfile.utf8)) == requirements.expectedProfileDigest,
              temporaryRulesEmpty(), effectiveRuleMatches(requirements), stableStatus(json(["status"])) == before,
              listener(endpoint) == listenerBefore, verifiedCLI() else { return (nil, "runtime-drift-or-read-failure") }
        guard LeaseClock.now - began < 5 else { return (nil, "audit-deadline-exceeded") }
        let evidence = LocalPolicyEvidence(challenge: challenge, scopeDigest: scope, activeProfileDigest: requirements.expectedProfileDigest,
            checkedAt: wallBegan, checkedClock: began, expiresClock: began + 6,
            dedicatedPortVerified: true, listenerVerified: true, runtimeStable: true, surgeOwner: listenerBefore)
        return (evidence, "local-policy-verified")
    }
}

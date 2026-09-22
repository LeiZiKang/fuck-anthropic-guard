import Foundation
import CoreFoundation
import Darwin

/// One launchd endpoint per installed version. Never fall back to the old,
/// unversioned name after a missing or mismatched build metadata value.
enum FilterMachService {
    static let prefix = "Y355LMZA6C.com.leizikang.claude-connection-watcher.filter"
    static func name(version: String?) -> String? {
        guard let version, version.range(of: #"\A[1-9][0-9]{0,3}(\.(0|[1-9][0-9]?)){0,2}\z"#,
                                         options: .regularExpression) != nil else { return nil }
        return prefix + ".v" + version
    }
    static func verifiedName(version: String?, declared: String?) -> String? {
        guard let expected = name(version: version), declared == expected else { return nil }
        return expected
    }
}

enum FilterConstants {
    static let bundleID = "com.leizikang.claude-connection-watcher.filter"
    static let machService: String = {
        let metadata = Bundle.main.infoDictionary ?? [:]
        let declared = Bundle.main.bundleIdentifier == bundleID
            ? (metadata["NetworkExtension"] as? [String: Any])?["NEMachServiceName"] as? String
            : metadata["CCWFilterMachServiceName"] as? String
        guard let name = FilterMachService.verifiedName(version: metadata["CFBundleVersion"] as? String,
                                                      declared: declared) else {
            preconditionFailure("Missing or inconsistent versioned Mach service metadata")
        }
        return name
    }()
    static let hostRequirement = "anchor apple generic and identifier \"com.leizikang.claude-connection-watcher\" and certificate leaf[subject.OU] = \"Y355LMZA6C\""
    static let providerRequirement = "anchor apple generic and identifier \"com.leizikang.claude-connection-watcher.filter\" and certificate leaf[subject.OU] = \"Y355LMZA6C\""
}

@objc protocol FilterControlProtocol {
    func updatePolicy(_ data: Data, reply: @escaping (Bool) -> Void)
    func status(reply: @escaping (Data) -> Void)
}

struct FilterPolicyUpdate: Codable {
    var protocolVersion: Int = 2
    var sequence: UInt64? = nil
    var providerGeneration: Int? = nil
    var policyEvidence: LocalPolicyEvidence? = nil
    var bootID: String? = nil
    var controlSessionID: String? = nil
    let block: Bool
    var validUntil: TimeInterval? = nil
}

struct FilterStatus: Codable {
    let enforcing: Bool
    let blocking: Bool
    let blockedFlows: Int
    var protocolVersion: Int? = nil
    var proxyEndpoint: ProxyEndpoint? = nil
    var routeAllowed: Int? = nil
    var routeDenied: Int? = nil
    var unknownOwnerFlows: Int? = nil
    var networkGeneration: Int? = nil
    var invalidationReason: String? = nil
    var policyChallenge: String? = nil
    var scopeDigest: String? = nil
    var bootID: String? = nil
    var controlSessionID: String? = nil
}

/// Shared pure decision logic. An absent/stale policy never allows a protected flow.
struct FilterDecisionState {
    var shouldBlock = true
    var receivedAt: TimeInterval?
    var validUntil: TimeInterval?
    var protectedBundleIDs = Set<String>()
    static let lease: TimeInterval = 90
    static let domains = ["claude.ai", "claude.com", "anthropic.com", "claudeusercontent.com"]

    func blocking(at uptime: TimeInterval) -> Bool {
        guard let receivedAt, let validUntil, receivedAt.isFinite, validUntil.isFinite,
              uptime >= receivedAt, uptime < validUntil, uptime - receivedAt <= Self.lease else { return true }
        return shouldBlock
    }

    mutating func accept(_ update: FilterPolicyUpdate, at uptime: TimeInterval) {
        receivedAt = uptime
        guard !update.block, let expiry = update.validUntil, expiry.isFinite,
              expiry > uptime, expiry <= uptime + Self.lease else {
            shouldBlock = true; validUntil = nil; return
        }
        shouldBlock = false
        validUntil = expiry
    }

    static func matchesDomain(_ hostname: String?) -> Bool {
        guard let hostname else { return false }
        var host = hostname.lowercased()
        if host.hasSuffix(".") { host.removeLast() }
        guard !host.isEmpty, host.count <= 253,
              host.split(separator: ".", omittingEmptySubsequences: false).allSatisfy({ label in
                  !label.isEmpty && label.count <= 63 && label.first != "-" && label.last != "-"
                  && label.utf8.allSatisfy { (97...122).contains($0) || (48...57).contains($0) || $0 == 45 }
              }) else { return false }
        return domains.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    static func validBundleID(_ identifier: String) -> Bool {
        !identifier.isEmpty && identifier.count <= 200 && identifier.utf8.allSatisfy {
            (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || [45, 46, 95].contains($0)
        }
    }
}

/// Attribution is explicit: unknown ownership is a coverage gap, never "protected".
enum FilterScopeDecision: Equatable { case protectedFlow, outsideScope, unknownOwner, unattributedUserFlow }
struct FilterSourceIdentity {
    let uid: UInt32
    let bundleID: String
    let official: Bool
    let infrastructure: Bool
    var trustedHost = false
}
enum FilterScope {
    static func hasVerifiedOwner(_ owner: UInt32?, source: FilterSourceIdentity?) -> Bool {
        guard let owner, let source else { return false }
        return source.uid == owner
    }
    static func classify(owner: UInt32?, source: FilterSourceIdentity?, hostname: String?,
                         approved: Set<String>, dedicatedEndpoint: Bool = false) -> FilterScopeDecision {
        guard let owner else { return .unknownOwner }
        guard let source else { return dedicatedEndpoint ? .protectedFlow : .unknownOwner }
        guard source.uid == owner else { return .outsideScope }
        // Host probes must remain reachable; no whole-proxy blocking.
        if source.trustedHost || source.infrastructure { return .outsideScope }
        if source.official || (!source.infrastructure && approved.contains(source.bundleID)) { return .protectedFlow }
        if source.infrastructure { return .outsideScope }
        return source.bundleID.isEmpty ? .unattributedUserFlow : .outsideScope
    }
    static func trustedInfrastructure(team: String, identifier: String, signatureValid: Bool) -> Bool {
        guard signatureValid else { return false }
        let identities: [String: Set<String>] = [
            "YCKFLA6N72": ["com.nssurge.surge-mac"],
            "NXELXU5YLW": ["com.initex.proxifier.v3.macos"],
            "JPH3Z7PPBB": ["io.github.clash-verge-rev.clash-verge-rev", "verge-mihomo"]
        ]
        return identities[team]?.contains(identifier) == true
    }
    static func ownerUID(_ number: NSNumber?) -> UInt32? {
        guard let number, CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite,
              number.doubleValue >= 1, number.doubleValue <= Double(UInt32.max),
              number.doubleValue.rounded() == number.doubleValue else { return nil }
        return number.uint32Value
    }
}

/// Bounded retention shared with the provider. EOF is not a full flow close.
struct FilterFlowRegistry<Value> {
    static var limit: Int { 4096 }
    private(set) var entries: [UUID: Value] = [:]
    mutating func insert(_ value: Value, id: UUID) -> Bool {
        guard entries[id] != nil || entries.count < Self.limit else { return false }
        entries[id] = value; return true
    }
    mutating func closed(_ id: UUID) { entries.removeValue(forKey: id) }
    mutating func withdraw() -> [Value] {
        let values = Array(entries.values); entries.removeAll(); return values
    }
}

/// A provider acknowledgement is evidence only while fresh. Configuration alone
/// does not imply that the system is executing the filter.
struct FilterAcknowledgement {
    var status: FilterStatus?
    var receivedAt: TimeInterval?
    mutating func invalidate() { status = nil; receivedAt = nil }
    func current(at uptime: TimeInterval) -> FilterStatus? {
        guard let receivedAt, uptime >= receivedAt, uptime - receivedAt < 10 else { return nil }
        return status
    }
}

/// Used under the monitor lock to discard results from before lifecycle changes.
struct ProbeEpoch {
    private(set) var generation = 0
    private(set) var sleeping = false
    mutating func invalidate(sleeping: Bool? = nil) {
        generation += 1
        if let sleeping { self.sleeping = sleeping }
    }
    func accepts(_ generation: Int) -> Bool { !sleeping && generation == self.generation }
}

struct FilterCallbackGate {
    struct Token: Equatable { let generation: Int; let request: Int }
    private(set) var generation = 0
    private var sequence = 0
    private var pending: Token?
    mutating func reconnect() { generation += 1; pending = nil }
    mutating func begin() -> Token? {
        guard pending == nil else { return nil }
        sequence += 1
        let token = Token(generation: generation, request: sequence)
        pending = token; return token
    }
    mutating func finish(_ token: Token) -> Bool {
        guard token.generation == generation, pending == token else { return false }
        pending = nil; return true
    }
}

/// Provider-only boot/network/control state. No allow state survives restart.
struct ProviderLeaseEpoch {
    let bootID = UUID().uuidString
    private(set) var generation = 0
    private(set) var session: UUID?
    private(set) var reason = "startup"
    private(set) var challenge = UUID().uuidString
    mutating func invalidate(_ reason: String) { generation += 1; self.reason = reason; challenge = UUID().uuidString }
    mutating func claim(_ id: UUID) -> Bool {
        guard session == nil || session == id else { return false }
        if session == nil { connect(id) }; return true
    }
    mutating func connect(_ id: UUID) { session = id; invalidate("control-connected") }
    mutating func disconnect(_ id: UUID) -> Bool {
        guard session == id else { return false }
        session = nil; invalidate("control-lost"); return true
    }
    func accepts(session id: UUID, generation value: Int?) -> Bool {
        session == id && value == generation
    }

    enum RenewalAuthorization { case foreignSession, identityLost, authorized }
    /// A stale controller or observer must neither inspect nor revoke the owner.
    func authorizeRelayRenewal(session id: UUID, identitiesValid: () -> Bool) -> RenewalAuthorization {
        guard session == id else { return .foreignSession }
        return identitiesValid() ? .authorized : .identityLost
    }
}

/// A shared monotonic clock that advances during sleep; leases cannot gain
/// extra lifetime simply because the UI or machine was suspended.
enum LeaseClock {
    private static let secondsPerTick: Double = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return Double(info.numer) / Double(info.denom) / 1_000_000_000
    }()
    static var now: TimeInterval { Double(mach_continuous_time()) * secondsPerTick }
}

struct PolicySequenceGate {
    private(set) var latest: UInt64 = 0
    mutating func accept(_ sequence: UInt64?) -> Bool {
        guard let sequence, sequence > latest else { return false }
        latest = sequence; return true
    }
}

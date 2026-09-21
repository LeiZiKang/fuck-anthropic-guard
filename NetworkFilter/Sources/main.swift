import Foundation
import NetworkExtension
import Network
import SystemConfiguration
import Security
import Darwin
import OSLog

private typealias FlowSource = FilterSourceIdentity

// BEGIN ENCLOSING_IDENTITY_VALIDATION_POLICY
/// Unverified metadata only chooses whether to run the existing full check.
/// It never grants an enclosing identity or a trust exemption.
private enum EnclosingIdentityValidation {
    static func requiresFullCheck(runningID: String, runningTeam: String,
                                  enclosingID: String?, enclosingTeam: String?, approved: Set<String>) -> Bool {
        guard !runningID.isEmpty, !runningTeam.isEmpty,
              let enclosingID, !enclosingID.isEmpty, let enclosingTeam, !enclosingTeam.isEmpty else { return true }
        if approved.contains(runningID) || approved.contains(enclosingID) { return true }
        if runningTeam == "Q6L2SF6YDW" && runningID.hasPrefix("com.anthropic.") { return true }
        if enclosingID == "com.anthropic.claudefordesktop" { return true }
        if FilterScope.trustedInfrastructure(team: runningTeam, identifier: runningID, signatureValid: true)
            || FilterScope.trustedInfrastructure(team: enclosingTeam, identifier: enclosingID, signatureValid: true) { return true }
        return false
    }
    static func metadataChanged(initialID: String?, initialTeam: String?, finalID: String, finalTeam: String) -> Bool {
        guard let initialID, let initialTeam else { return false } // read failure uses the original full-validation path
        return initialID != finalID || initialTeam != finalTeam
    }
}
private enum EnclosingIdentityValidationError: Error { case metadataChanged }
// END ENCLOSING_IDENTITY_VALIDATION_POLICY

/// No packet payloads are parsed, retained, logged, or sent to the host.
@objc(CCWFilterDataProvider)
final class CCWFilterDataProvider: NEFilterDataProvider, NSXPCListenerDelegate {
    private let policyQueue = DispatchQueue(label: "CCW.Filter.Policy")
    private let queueKey = DispatchSpecificKey<Bool>()
    private var policy = FilterDecisionState()
    private var ownerUID: uid_t?
    private var flows = FilterFlowRegistry<NEFilterSocketFlow>()
    private var sourceCache: [Data: FlowSource] = [:]
    private var denied = 0
    private var proxyEndpoint: ProxyEndpoint?
    private var expectedProfileDigest = ""
    private var scopeDigest = ""
    private var routeAllowed = 0
    private var routeDenied = 0
    private var unknownOwnerFlows = 0
    private var listener: NSXPCListener?
    private var expiryTimer: DispatchSourceTimer?
    private var enforcing = false
    private var lifecycleGeneration = 0
    private var leaseEpoch = ProviderLeaseEpoch()
    private var controlConnection: NSXPCConnection?
    private var pathMonitor: NWPathMonitor?
    private var networkStore: SCDynamicStore?
    private let transportLog = Logger(subsystem: "com.leizikang.claude-connection-watcher.filter", category: "TransportLifecycle")
    private var dataDropLogCount = 0
    private var surgeOwner: ProcessIdentity?
    private var sequenceGate = PolicySequenceGate()


    override init() {
        super.init()
        policyQueue.setSpecific(key: queueKey, value: true)
    }

    private func withState<T>(_ body: () -> T) -> T {
        if DispatchQueue.getSpecific(key: queueKey) == true { return body() }
        return policyQueue.sync(execute: body)
    }

    override func startFilter(completionHandler: @escaping (Error?) -> Void) {
        guard let uid = FilterScope.ownerUID(filterConfiguration.vendorConfiguration?["ownerUID"] as? NSNumber) else {
            completionHandler(NSError(domain: "CCWFilter", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing owner UID"]))
            return
        }
        guard let address = filterConfiguration.vendorConfiguration?["proxyAddress"] as? String,
              let port = filterConfiguration.vendorConfiguration?["proxyPort"] as? String,
              let kind = filterConfiguration.vendorConfiguration?["proxyKind"] as? String,
              let endpoint = ProxyEndpoint.parse(address: address, port: port, kind: kind) else {
            completionHandler(NSError(domain: "CCWFilter", code: 3, userInfo: [NSLocalizedDescriptionKey: "Expected local proxy endpoint required"]))
            return
        }
        let approved = filterConfiguration.vendorConfiguration?["protectedBundleIDs"] as? [String] ?? []
        guard approved.count <= 128, approved.allSatisfy(FilterDecisionState.validBundleID) else {
            completionHandler(NSError(domain: "CCWFilter", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid protected-app scope"]))
            return
        }
        guard filterConfiguration.vendorConfiguration?["fixedRelayPolicy"] == nil else {
            completionHandler(NSError(domain: "CCWFilter", code: 5)); return
        }
        guard let profileDigest = filterConfiguration.vendorConfiguration?["expectedProfileDigest"] as? String,
              profileDigest.count == 64, profileDigest.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
              let exits = filterConfiguration.vendorConfiguration?["expectedExits"] as? [String], !exits.isEmpty,
              exits.count <= 16, exits.allSatisfy({ IPAddress.normalize($0) == $0 }) else {
            completionHandler(NSError(domain: "CCWFilter", code: 4, userInfo: [NSLocalizedDescriptionKey: "Trusted policy evidence configuration required"]))
            return
        }
        let generation = withState { () -> Int in
            leaseEpoch.invalidate("filter-start")
            lifecycleGeneration += 1; ownerUID = uid; policy = FilterDecisionState()
            policy.protectedBundleIDs = Set(approved); proxyEndpoint = endpoint; enforcing = false
            expectedProfileDigest = profileDigest; scopeDigest = PolicyEvidenceVerifier.scope(proxy: endpoint, bundles: approved, exits: exits)
            return lifecycleGeneration
        }
        let paths = NWPathMonitor()
        paths.pathUpdateHandler = { [weak self] path in
            self?.withState {
                guard let self else { return }
                // Surge trust is checked by its identity, active rules and
                // process/socket leases, not satisfied-path metadata changes.
                if path.status != .satisfied {
                    self.revoke("network-change")
                }
            }
        }
        paths.start(queue: policyQueue); pathMonitor = paths
        var context = SCDynamicStoreContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        networkStore = SCDynamicStoreCreate(nil, "CCWProviderNetwork" as CFString, { _, _, info in
            guard let info else { return }
            let provider = Unmanaged<CCWFilterDataProvider>.fromOpaque(info).takeUnretainedValue()
            provider.withState {
                // Fixed relay configuration is activated by the signed host;
                // unrelated global DNS/proxy notifications do not change it.
                provider.revoke("configuration-change")
            }
        }, &context)
        if let store = networkStore {
            SCDynamicStoreSetNotificationKeys(store, nil, ["State:/Network/Global/.*", "Setup:/Network/Service/.*/Proxies"] as CFArray)
            SCDynamicStoreSetDispatchQueue(store, policyQueue)
        }
        let listener = NSXPCListener(machServiceName: FilterConstants.machService)
        listener.delegate = self
        listener.resume()
        self.listener = listener
        let timer = DispatchSource.makeTimerSource(queue: policyQueue)
        timer.schedule(deadline: .now(), repeating: 1)
        timer.setEventHandler { [weak self] in if let self { if let owner = self.surgeOwner, KernelIdentity.capture(owner.pid) != owner { self.revoke("surge-process-lost") }; self.dropTrackedFlowsIfNeeded() } }
        expiryTimer = timer
        timer.resume()
        // Loopback is allowed by default by NEFilterSettings. Explicit rules are
        // necessary to cover clients connecting to local HTTP/SOCKS proxy ports.
        let loopback4 = NENetworkRule(destinationNetwork: NWHostEndpoint(hostname: "127.0.0.0", port: "0"), prefix: 8, protocol: .any)
        let loopback6 = NENetworkRule(destinationNetwork: NWHostEndpoint(hostname: "::1", port: "0"), prefix: 128, protocol: .any)
        let rules = [loopback4, loopback6].map { NEFilterRule(networkRule: $0, action: .filterData) }
        apply(NEFilterSettings(rules: rules, defaultAction: .filterData)) { [weak self] error in
            self?.withState {
                guard let self, self.lifecycleGeneration == generation else { return }
                self.enforcing = error == nil
                if error != nil { self.expiryTimer?.cancel(); self.expiryTimer = nil; self.listener?.invalidate(); self.listener = nil }
            }
            completionHandler(error)
        }
    }

    override func sleep(completionHandler: @escaping () -> Void) {
        withState { revoke("sleep") }; completionHandler()
    }
    override func wake() { withState { revoke("wake") } }

    override func stopFilter(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        pathMonitor?.cancel(); pathMonitor = nil
        if let store = networkStore { SCDynamicStoreSetDispatchQueue(store, nil) }; networkStore = nil
        controlConnection?.invalidate(); controlConnection = nil
        expiryTimer?.cancel(); expiryTimer = nil
        listener?.invalidate(); listener = nil
        withState {
            lifecycleGeneration += 1; enforcing = false; _ = flows.withdraw()
            sourceCache.removeAll(); policy = FilterDecisionState(); ownerUID = nil
        }
        completionHandler()
    }

    private func descendantOfOfficial(pid: Int32, uid: UInt32) -> Bool {
        VerifiedAncestry.containsOfficialParent(of: pid, uid: uid) { candidate in
            func info() -> proc_bsdinfo? {
                var value = proc_bsdinfo()
                let size = Int32(MemoryLayout<proc_bsdinfo>.stride)
                guard proc_pidinfo(candidate, PROC_PIDTBSDINFO, 0, &value, size) == size else { return nil }
                return value
            }
            guard let before = info() else { return nil }
            var code: SecCode?; var requirement: SecRequirement?
            let expression = "anchor apple generic and certificate leaf[subject.OU] = \"Q6L2SF6YDW\" and (identifier \"com.anthropic.claude-code\" or identifier \"com.anthropic.claudefordesktop\")"
            let signed = SecCodeCopyGuestWithAttributes(nil, [kSecGuestAttributePid as String: NSNumber(value: candidate)] as CFDictionary, [], &code) == errSecSuccess
                && SecRequirementCreateWithString(expression as CFString, [], &requirement) == errSecSuccess
                && code.map { SecCodeCheckValidity($0, [], requirement) == errSecSuccess } == true
            guard let after = info(), before.pbi_ppid == after.pbi_ppid, before.pbi_uid == after.pbi_uid else { return nil }
            return AncestryNode(pid: candidate, parent: Int32(before.pbi_ppid), uid: before.pbi_uid,
                startedBefore: before.pbi_start_tvsec * 1_000_000 + before.pbi_start_tvusec,
                startedAfter: after.pbi_start_tvsec * 1_000_000 + after.pbi_start_tvusec, officialSignature: signed)
        }
    }

    private func identify(_ token: Data?) throws -> FlowSource? {
        guard let token, token.count == MemoryLayout<audit_token_t>.size else { return nil }
        let uid = token.withUnsafeBytes { ccw_audit_euid($0.baseAddress, $0.count) }
        // Scope rejects a proven different UID before inspecting signature flags.
        // Preserve the UID for fixed-ingress rejection; never cache this shortcut.
        if let owner = ownerUID, uid != owner {
            return FlowSource(uid: uid, bundleID: "", official: false, infrastructure: false)
        }
        // Once proved a descendant, keep this audit-token identity protected
        // across reparenting/exec. Unknown identities are never cached as safe.
        if let cached = sourceCache[token], cached.official { return cached }
        let pid = token.withUnsafeBytes { ccw_audit_pid($0.baseAddress, $0.count) }
        let descendant = uid == ownerUID && descendantOfOfficial(pid: pid, uid: uid)
        let unknown = FlowSource(uid: uid, bundleID: "", official: descendant, infrastructure: false)
        var code: SecCode?
        guard SecCodeCopyGuestWithAttributes(nil, [kSecGuestAttributeAudit as String: token] as CFDictionary, [], &code) == errSecSuccess,
              let code else { return unknown }
        var staticCode: SecStaticCode?
        var information: CFDictionary?
        // TeamIdentifier is a Signing field, not part of flags=0 generic metadata.
        let signingInformationFlags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopySigningInformation(staticCode, signingInformationFlags, &information) == errSecSuccess,
              let info = information as? [String: Any] else { return unknown }
        let signingID = info[kSecCodeInfoIdentifier as String] as? String ?? ""
        let team = info[kSecCodeInfoTeamIdentifier as String] as? String ?? ""
        var url: CFURL?
        _ = SecCodeCopyPath(staticCode, [], &url)
        let path = (url as URL?)?.path ?? ""
        let parts = (path as NSString).pathComponents
        let appPath = parts.firstIndex(where: { $0.hasSuffix(".app") }).map { NSString.path(withComponents: Array(parts[...$0])) }
        var generalAnchor: SecRequirement?
        let signedIdentity = SecRequirementCreateWithString("anchor apple generic" as CFString, [], &generalAnchor) == errSecSuccess
            && SecCodeCheckValidity(code, [], generalAnchor) == errSecSuccess
        var bundleID = signedIdentity ? signingID : ""
        // Enclosing Info.plist is untrusted. Use only an independently valid
        // signed enclosing app of the same team as the actual running code.
        if signedIdentity, let appPath {
            var enclosing: SecStaticCode?
            if SecStaticCodeCreateWithPath(URL(fileURLWithPath: appPath) as CFURL, [], &enclosing) == errSecSuccess,
               let enclosing {
                var candidateInfo: CFDictionary?
                let candidateRead = SecCodeCopySigningInformation(enclosing, signingInformationFlags, &candidateInfo)
                let candidate = candidateRead == errSecSuccess ? candidateInfo as? [String: Any] : nil
                let candidateID = candidate?[kSecCodeInfoIdentifier as String] as? String
                let candidateTeam = candidate?[kSecCodeInfoTeamIdentifier as String] as? String
                if ownerUID == nil || EnclosingIdentityValidation.requiresFullCheck(runningID: signingID, runningTeam: team,
                    enclosingID: candidateID, enclosingTeam: candidateTeam, approved: policy.protectedBundleIDs) {
                    // Retain full validation, then read attribution again from the same object.
                    var enclosingInfo: CFDictionary?
                    if SecStaticCodeCheckValidity(enclosing, [], generalAnchor) == errSecSuccess,
                       SecCodeCopySigningInformation(enclosing, signingInformationFlags, &enclosingInfo) == errSecSuccess,
                       let metadata = enclosingInfo as? [String: Any], let finalTeam = metadata[kSecCodeInfoTeamIdentifier as String] as? String,
                       let identifier = metadata[kSecCodeInfoIdentifier as String] as? String {
                        if EnclosingIdentityValidation.metadataChanged(initialID: candidateID, initialTeam: candidateTeam,
                            finalID: identifier, finalTeam: finalTeam) { throw EnclosingIdentityValidationError.metadataChanged }
                        if finalTeam == team { bundleID = identifier }
                    }
                }
            }
        }
        // audit_token_t's documented effective-UID accessor is provided by a C shim.
        var requirement: SecRequirement?
        let expression = "anchor apple generic and certificate leaf[subject.OU] = \"Q6L2SF6YDW\""
        let official = team == "Q6L2SF6YDW" && (signingID.hasPrefix("com.anthropic.") || bundleID == "com.anthropic.claudefordesktop")
            && SecRequirementCreateWithString(expression as CFString, [], &requirement) == errSecSuccess
            && SecCodeCheckValidity(code, [], requirement) == errSecSuccess
        let infrastructure = FilterScope.trustedInfrastructure(team: team, identifier: bundleID, signatureValid: signedIdentity)
        var hostRequirement: SecRequirement?
        let trustedHost = signingID == "com.leizikang.claude-connection-watcher"
            && SecRequirementCreateWithString(FilterConstants.hostRequirement as CFString, [], &hostRequirement) == errSecSuccess
            && SecCodeCheckValidity(code, [], hostRequirement) == errSecSuccess
        let result = FlowSource(uid: uid, bundleID: bundleID, official: official || descendant, infrastructure: infrastructure, trustedHost: trustedHost)
        if result.official {
            if sourceCache.count < 4096 { sourceCache[token] = result }
            else { revoke("scope-capacity") }
        }
        return result
    }

    override func handleNewFlow(_ flow: NEFilterFlow) -> NEFilterNewFlowVerdict {
        guard let socket = flow as? NEFilterSocketFlow, socket.direction == .outbound else { return .allow() }
        return withState { () -> NEFilterNewFlowVerdict in

            let source: FlowSource?
            do { source = try identify(socket.sourceProcessAuditToken ?? socket.sourceAppAuditToken) }
            catch { unknownOwnerFlows += 1; return .allow() }
            let dedicated = false

            let scope = FilterScope.classify(owner: ownerUID, source: source,
                                             hostname: socket.remoteHostname, approved: policy.protectedBundleIDs, dedicatedEndpoint: dedicated)
            if scope == .unknownOwner {
                unknownOwnerFlows += 1
                // UID cannot be established: don't guess which system/user owns
                // the flow. All identified protected flows are withdrawn.
                return .allow()
            }
            if scope == .unattributedUserFlow {
                unknownOwnerFlows += 1
                // Do not guess that every unsigned user CLI belongs to Claude.
                // Withdraw identified protected flows, leave this unowned flow
                // outside proven coverage and disclose that gap.
                return .allow()
            }
            guard scope == .protectedFlow else { return .allow() }

            if source == nil || source?.bundleID.isEmpty == true { unknownOwnerFlows += 1 }
            // Never apply whole-client proxy routing to infrastructure forwarding.
            // Recognized clients must use the approved Surge TCP endpoint.
            if source?.infrastructure != true || source?.official == true {
                let remote = socket.remoteEndpoint as? NWHostEndpoint
                guard proxyEndpoint?.matches(address: remote?.hostname, port: remote?.port,
                                             tcp: socket.socketProtocol == IPPROTO_TCP) == true else {
                    routeDenied += 1; denied += 1; return .drop()
                }
                routeAllowed += 1
            }
            if policy.blocking(at: LeaseClock.now) || surgeOwner.map({ KernelIdentity.capture($0.pid) != $0 }) != false { denied += 1; return .drop() }
            // Retain bounded flow references so a later risk update can drop an
            // existing protected connection, rather than only blocking new ones.
            guard flows.insert(socket, id: socket.identifier) else { denied += 1; return .drop() }
            let verdict = NEFilterNewFlowVerdict.filterDataVerdict(withFilterInbound: true, peekInboundBytes: 1, filterOutbound: true, peekOutboundBytes: 1)
            verdict.shouldReport = true
            return verdict
        }
    }

    override func handleInboundData(from flow: NEFilterFlow, readBytesStartOffset offset: Int, readBytes: Data) -> NEFilterDataVerdict {
        handleOutboundData(from: flow, readBytesStartOffset: offset, readBytes: readBytes)
    }

    /// Called under policyQueue; only fixed reasons and state booleans are logged.
    private func logDataDrop(_ flow: NEFilterFlow, reason: String) {
        guard dataDropLogCount < 16 else { return }; dataDropLogCount += 1
        transportLog.info("protected-flow-drop reason=\(reason, privacy: .public)")
    }

    override func handleOutboundData(from flow: NEFilterFlow, readBytesStartOffset offset: Int, readBytes: Data) -> NEFilterDataVerdict {
        withState {
            enforceClientTransportExpiry()

            if policy.blocking(at: LeaseClock.now) { logDataDrop(flow, reason: "client-data-policy"); denied += 1; flows.closed(flow.identifier); return .drop() }
            return NEFilterDataVerdict(passBytes: 4096, peekBytes: 1)
        }
    }

    override func handleOutboundDataComplete(for flow: NEFilterFlow) -> NEFilterDataVerdict {
        withState {
            enforceClientTransportExpiry()

            if policy.blocking(at: LeaseClock.now) {
                logDataDrop(flow, reason: "client-complete-policy")
                flows.closed(flow.identifier); denied += 1; return .drop()
            }
            // Outbound EOF is not flowClosed. Retain the reference so a later
            // risk change can still drop a half-closed flow's inbound traffic.
            return .allow()
        }
    }

    override func handle(_ report: NEFilterReport) {
        guard report.event == .flowClosed, let flow = report.flow else { return }
        withState { flows.closed(flow.identifier) }
    }

    private func enforceClientTransportExpiry() {
        if let owner = surgeOwner, KernelIdentity.capture(owner.pid) != owner { revoke("surge-process-lost") }
    }
    private func dropTrackedFlowsIfNeeded() {
        enforceClientTransportExpiry()
        guard policy.blocking(at: LeaseClock.now) else { return }
        let targets = flows.withdraw()
        for flow in targets { update(flow, using: .drop(), for: .any); denied += 1 }
    }

    private func revoke(_ reason: String) {
        surgeOwner = nil
        let knownReasons = ["network-change", "configuration-change", "sleep", "wake", "scope-capacity", "coverage-unknown",
                            "identity-unknown", "relay-control-expired", "control-connected", "control-lost", "user-stopped-relay", "relay-identity-lost"]
        let diagnosticReason = knownReasons.contains(reason) ? reason : "other"
        transportLog.notice("revoke reason=\(diagnosticReason, privacy: .public)")
        leaseEpoch.invalidate(reason)
        policy.accept(FilterPolicyUpdate(block: true), at: LeaseClock.now)
        dropTrackedFlowsIfNeeded()
    }



    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard connection.effectiveUserIdentifier == withState({ ownerUID }) else { return false }
        connection.setCodeSigningRequirement(FilterConstants.hostRequirement)
        let id = UUID()
        let accepted = withState { () -> Bool in
            guard enforcing, leaseEpoch.session == nil else { return false }
            leaseEpoch.connect(id); sequenceGate = PolicySequenceGate(); controlConnection = connection; revoke("control-connected"); return true
        }
        guard accepted else { return false }
        // Only the first authenticated controller owns this provider session.
        connection.exportedInterface = NSXPCInterface(with: FilterControlProtocol.self)
        connection.exportedObject = ProviderControlSession(provider: self, id: id, callerPID: connection.processIdentifier, connection: connection)
        let lost: () -> Void = { [weak self] in
            self?.withState {
                guard let self, self.leaseEpoch.disconnect(id) else { return }
                self.controlConnection = nil; self.revoke("control-lost")
            }
        }
        connection.invalidationHandler = lost; connection.interruptionHandler = lost
        connection.resume(); return true
    }



    func updatePolicy(_ data: Data, session: UUID, reply: @escaping (Bool) -> Void) {
        guard data.count <= 16384, let update = try? JSONDecoder().decode(FilterPolicyUpdate.self, from: data), update.protocolVersion == 2 else { reply(false); return }
        policyQueue.async {
            guard self.enforcing, self.leaseEpoch.session == session, self.sequenceGate.accept(update.sequence) else { reply(false); return }
            if update.block {
                self.policy.accept(update, at: LeaseClock.now)
                self.enforceClientTransportExpiry()
            }
            else {
                guard let listener = update.policyEvidence?.surgeOwner, listener.effectiveUID == self.ownerUID, KernelIdentity.verifiedSurge(listener),
                      self.leaseEpoch.accepts(session: session, generation: update.providerGeneration),
                      update.bootID == self.leaseEpoch.bootID, update.controlSessionID == session.uuidString,
                      PolicyEvidenceVerifier.valid(update.policyEvidence, challenge: self.leaseEpoch.challenge,
                                                   scope: self.scopeDigest, profileDigest: self.expectedProfileDigest, now: Date(), uptime: LeaseClock.now),
                      let evidenceExpiry = update.policyEvidence?.expiresClock else {
                    self.policy.accept(FilterPolicyUpdate(block: true), at: LeaseClock.now)
                    self.dropTrackedFlowsIfNeeded(); reply(false); return
                }
                self.surgeOwner = update.policyEvidence?.surgeOwner
                var bounded = update
                bounded.validUntil = min(update.validUntil ?? 0, evidenceExpiry) - 1
                if let expiry = bounded.validUntil {
                    self.expiryTimer?.schedule(deadline: .now() + max(0, expiry - LeaseClock.now), repeating: .seconds(1), leeway: .milliseconds(10))
                }
                self.policy.accept(bounded, at: LeaseClock.now)
            }
            self.dropTrackedFlowsIfNeeded(); reply(true)
        }
    }




    func status(session: UUID, reply: @escaping (Data) -> Void) {
        policyQueue.async {
            guard self.leaseEpoch.session == session else { reply(Data()); return }
            let status = FilterStatus(enforcing: self.enforcing, blocking: self.policy.blocking(at: LeaseClock.now),
                blockedFlows: self.denied, protocolVersion: 2, proxyEndpoint: self.proxyEndpoint,
                routeAllowed: self.routeAllowed, routeDenied: self.routeDenied, unknownOwnerFlows: self.unknownOwnerFlows,
                networkGeneration: self.leaseEpoch.generation, invalidationReason: self.leaseEpoch.reason,
                policyChallenge: self.leaseEpoch.challenge, scopeDigest: self.scopeDigest,
                bootID: self.leaseEpoch.bootID, controlSessionID: self.leaseEpoch.session?.uuidString)
            reply((try? JSONEncoder().encode(status)) ?? Data())
        }
    }
}

private final class ProviderControlSession: NSObject, FilterControlProtocol {
    weak var provider: CCWFilterDataProvider?
    let id: UUID
    let callerPID: Int32
    weak var connection: NSXPCConnection?
    init(provider: CCWFilterDataProvider, id: UUID, callerPID: Int32, connection: NSXPCConnection) {
        self.provider = provider; self.id = id; self.callerPID = callerPID; self.connection = connection
    }




    func updatePolicy(_ data: Data, reply: @escaping (Bool) -> Void) {
        guard let provider else { reply(false); return }; provider.updatePolicy(data, session: id, reply: reply)
    }
    func status(reply: @escaping (Data) -> Void) {
        guard let provider else { reply(Data()); return }; provider.status(session: id, reply: reply)
    }

}

NEProvider.startSystemExtensionMode()
dispatchMain()

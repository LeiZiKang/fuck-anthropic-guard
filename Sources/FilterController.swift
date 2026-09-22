import AppKit
import NetworkExtension
import SystemExtensions

final class FilterController: NSObject, OSSystemExtensionRequestDelegate {
    var onUpdate: (() -> Void)?
    var onPolicyInvalidated: (() -> Void)?
    private var providerGeneration: Int?
    private var providerBootID: String?
    private var controlSessionID: String?
    private(set) var policyChallenge = ""
    private(set) var policyScopeDigest = ""
    private var policyEvidence: LocalPolicyEvidence?
    private let auditor = LocalSurgeAuditor()
    var onPolicyUpdated: (() -> Void)?
    var policyAuditReason: String { auditor.reason }
    private(set) var invalidationReason = "startup"
    private var acknowledgement = FilterAcknowledgement()
    private(set) var configured: Bool? = nil
    private(set) var extensionApproval = LocalizedMessage("未确认", "Unconfirmed")
    private var callbacks = FilterCallbackGate()
    private var statusTimer: Timer?
    private var reconnectAttempts = 0
    private var retryScheduled = false
    private var policyRequestID = 0
    private(set) var requirements = RouteRequirements()
    private(set) var routeAllowed = 0
    private(set) var routeDenied = 0
    private(set) var unknownOwnerFlows = 0
    private var removalRequest: OSSystemExtensionRequest?
    var routeGate: RouteGateResult = .unconfigured
    override init() {
        super.init()
        auditor.onUpdate = { [weak self] in self?.onPolicyUpdated?() }
        if let data = UserDefaults.standard.data(forKey: "SurgeGuardRequirementsV1"), data.count < 4096,
           let value = try? JSONDecoder().decode(RouteRequirements.self, from: data), value.isConfigured { requirements = value }
    }
    func saveRequirements(_ value: RouteRequirements) -> Bool {
        guard value.isConfigured, !pending, !active, !bundled || configured == false,
              let data = try? JSONEncoder().encode(value) else { return false }
        requirements = value; UserDefaults.standard.set(data, forKey: "SurgeGuardRequirementsV1")
        routeGate = .probeUnavailable; onUpdate?(); return true
    }
    var active: Bool { acknowledgement.current(at: LeaseClock.now)?.enforcing == true }
    private(set) var pending = false
    private(set) var blockedFlows = 0
    private(set) var blocking = true
    private(set) var message: LocalizedMessage?
    private var connection: NSXPCConnection?
    private var selectedBundleIDs: [String] = []

    var bundled: Bool {
        FileManager.default.fileExists(atPath: Bundle.main.bundlePath + "/Contents/Library/SystemExtensions/" + FilterConstants.bundleID + ".systemextension")
    }

    func activate(protectedBundleIDs: [String]) {
        guard bundled else {
            message = LocalizedMessage("过滤扩展尚未安装：需要带 Network Extension 权限的签名版本。", "Filter not bundled: a build signed with Network Extension provisioning is required.")
            onUpdate?(); return
        }
        guard requirements.localAuditConfigured else {
            message = LocalizedMessage("先设置专用代理端口、固定上游与已审阅配置摘要；未发起系统配置。", "Set dedicated proxy port, pinned upstream and reviewed profile digest before setup.")
            onUpdate?(); return
        }
        guard !pending, Set(protectedBundleIDs).count <= 128,
              protectedBundleIDs.allSatisfy(FilterDecisionState.validBundleID) else {
            message = LocalizedMessage("操作进行中或范围无效；未扩大目标。", "Operation pending or invalid scope; targets unchanged.")
            onUpdate?(); return
        }
        selectedBundleIDs = Array(Set(protectedBundleIDs)).sorted()
        pending = true
        extensionApproval = LocalizedMessage("请求中", "Requested")
        let request = OSSystemExtensionRequest.activationRequest(forExtensionWithIdentifier: FilterConstants.bundleID, queue: .main)
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
        onUpdate?()
    }

    func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        extensionApproval = LocalizedMessage("等待用户批准", "Awaiting user approval")
        message = LocalizedMessage("请在系统设置中批准网络过滤扩展。批准前未启用拦截。", "Approve the network extension in System Settings. Protection is not active before approval.")
        onUpdate?()
    }

    func request(_ request: OSSystemExtensionRequest, actionForReplacingExtension existing: OSSystemExtensionProperties,
                 withExtension ext: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction { .replace }

    func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        if request === removalRequest {
            removalRequest = nil; pending = false
            message = LocalizedMessage("系统扩展移除失败；配置已停用，稍后可重试移除。", "Extension removal failed; configuration disabled, removal can be retried.")
            onUpdate?(); return
        }
        removalRequest = nil; pending = false; acknowledgement.invalidate()
        extensionApproval = LocalizedMessage("失败／未确认", "Failed / unconfirmed")
        message = LocalizedMessage("网络过滤器未能启用：\(error.localizedDescription)", "Could not enable the filter: \(error.localizedDescription)")
        onUpdate?()
    }

    func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
        if request === removalRequest {
            removalRequest = nil; pending = false; extensionApproval = LocalizedMessage("已请求移除", "Removal requested")
            message = result == .completed ? LocalizedMessage("扩展移除完成；不再保护连接。", "Extension removal completed; connections are no longer protected.") : LocalizedMessage("停用完成，移除需重启后确认。", "Disabled; confirm removal after restart.")
            onUpdate?(); return
        }
        guard result == .completed else {
            pending = false
            extensionApproval = LocalizedMessage("需要重启", "Restart required")
            message = LocalizedMessage("系统要求重启后才能启用过滤器。", "The system requires a restart before the filter can be enabled.")
            onUpdate?(); return
        }
        extensionApproval = LocalizedMessage("激活请求完成", "Activation request completed")
        let manager = NEFilterManager.shared()
        manager.loadFromPreferences { [weak self] error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let error { self.request(request, didFailWithError: error); return }
                if let identifier = manager.providerConfiguration?.filterDataProviderBundleIdentifier,
                   identifier != FilterConstants.bundleID {
                    self.pending = false
                    self.message = LocalizedMessage("发现其他过滤器配置，已停止，未覆盖它。", "Another filter configuration was found; it was not overwritten.")
                    self.onUpdate?(); return
                }
                if manager.providerConfiguration != nil,
                   FilterScope.ownerUID(manager.providerConfiguration?.vendorConfiguration?["ownerUID"] as? NSNumber) != geteuid() {
                    self.pending = false
                    self.message = LocalizedMessage("现有过滤器不属于当前用户，未修改。", "The existing filter does not belong to this user; it was not changed.")
                    self.onUpdate?(); return
                }
                if manager.isEnabled && manager.providerConfiguration?.vendorConfiguration?["fixedRelayPolicy"] != nil {
                    self.pending = false; self.message = LocalizedMessage("旧版保护仍启用，未覆盖。", "Legacy protection is still enabled; not overwritten."); self.onUpdate?(); return
                }
                let configuration = NEFilterProviderConfiguration()
                configuration.filterSockets = true
                configuration.filterPackets = false
                configuration.filterDataProviderBundleIdentifier = FilterConstants.bundleID
                guard let desiredProxy = self.requirements.proxy else {
                    self.pending = false; self.onUpdate?(); return
                }
                configuration.vendorConfiguration = ["ownerUID": NSNumber(value: geteuid()), "protectedBundleIDs": self.selectedBundleIDs,
                                                     "proxyAddress": desiredProxy.address, "proxyPort": String(desiredProxy.port), "proxyKind": desiredProxy.kind,
                                                     "expectedProfileDigest": self.requirements.expectedProfileDigest, "expectedExits": self.requirements.expectedExitAddresses]

                manager.providerConfiguration = configuration
                manager.localizedDescription = "Claude Connection Protection"
                manager.isEnabled = true
                manager.saveToPreferences { error in
                    DispatchQueue.main.async {
                        self.pending = false
                        if let error { self.request(request, didFailWithError: error); return }
                        self.configured = true
                        self.connect()
                    }
                }
            }
        }
    }

    func connect(resetRetries: Bool = true) {
        guard bundled else { return }
        if resetRetries { reconnectAttempts = 0 }
        callbacks.reconnect()
        providerGeneration = nil; providerBootID = nil; controlSessionID = nil
        policyChallenge = ""; policyScopeDigest = ""; policyEvidence = nil
        auditor.invalidate()
        onPolicyInvalidated?()
        let generation = callbacks.generation
        retryScheduled = false
        acknowledgement.invalidate()
        connection?.invalidate()
        statusTimer?.invalidate()
        statusTimer = GuardianTimer.repeating(2) { [weak self] in
            self?.onUpdate?()
            self?.readStatus()
        }
        let connection = NSXPCConnection(machServiceName: FilterConstants.machService, options: .privileged)
        connection.setCodeSigningRequirement(FilterConstants.providerRequirement)
        connection.remoteObjectInterface = NSXPCInterface(with: FilterControlProtocol.self)
        connection.invalidationHandler = { [weak self] in DispatchQueue.main.async {
            guard let self, self.callbacks.generation == generation else { return }
            self.connectionFailed()
        } }
        connection.interruptionHandler = { [weak self] in DispatchQueue.main.async {
            guard let self, self.callbacks.generation == generation else { return }
            self.connectionFailed()
        } }
        self.connection = connection
        let manager = NEFilterManager.shared()
        manager.loadFromPreferences { [weak self] error in
            DispatchQueue.main.async {
                guard let self, self.callbacks.generation == generation else { return }
                if error != nil { self.configured = nil }
                else if manager.providerConfiguration == nil { self.configured = false }
                else if manager.providerConfiguration?.filterDataProviderBundleIdentifier == FilterConstants.bundleID,
                        FilterScope.ownerUID(manager.providerConfiguration?.vendorConfiguration?["ownerUID"] as? NSNumber) == geteuid() {
                    self.configured = manager.isEnabled
                    if manager.providerConfiguration?.vendorConfiguration?["fixedRelayPolicy"] != nil { self.message = LocalizedMessage("检测到旧版专用代理配置，请保持旧保护停用后重新配置。", "Legacy proxy configuration found. Disable the old protection before setup.") }
                } else { self.configured = nil }
                self.onUpdate?()
            }
        }
        connection.resume()
        readStatus()
    }

    func readConfigurationOnly() {
        let manager = NEFilterManager.shared()
        manager.loadFromPreferences { [weak self] error in
            DispatchQueue.main.async {
                guard let self else { return }
                if error != nil { self.configured = nil }
                else if manager.providerConfiguration == nil { self.configured = false }
                else if manager.providerConfiguration?.filterDataProviderBundleIdentifier == FilterConstants.bundleID,
                        FilterScope.ownerUID(manager.providerConfiguration?.vendorConfiguration?["ownerUID"] as? NSNumber) == geteuid() {
                    self.configured = manager.isEnabled
                    if manager.providerConfiguration?.vendorConfiguration?["fixedRelayPolicy"] != nil { self.message = LocalizedMessage("检测到旧版专用代理配置，请保持旧保护停用后重新配置。", "Legacy proxy configuration found. Disable the old protection before setup.") }

                } else { self.configured = nil }
                self.onUpdate?()
            }
        }
    }
    /// Explicit Refresh retries IPC only; it never installs or enables a filter.
    func retryStatus() {
        guard !pending else { return }
        if connection == nil || !active { connect() } else { readStatus() }
    }

    private func connectionFailed() {
        callbacks.reconnect()
        providerGeneration = nil; providerBootID = nil; controlSessionID = nil
        policyChallenge = ""; policyScopeDigest = ""; policyEvidence = nil
        auditor.invalidate()
        onPolicyInvalidated?()
        let generation = callbacks.generation
        connection?.invalidate(); connection = nil
        statusTimer?.invalidate(); statusTimer = nil
        acknowledgement.invalidate()
        message = LocalizedMessage("扩展失联；执行未知。最多重试三次，可点刷新重试。", "Provider unavailable; enforcement unknown. Up to three retries; Refresh retries manually.")
        onUpdate?()
        guard reconnectAttempts < 3, !retryScheduled else { return }
        reconnectAttempts += 1; retryScheduled = true
        let delay = pow(2.0, Double(reconnectAttempts))
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.callbacks.generation == generation, self.retryScheduled else { return }
            self.retryScheduled = false
            self.connect(resetRetries: false)
        }
    }

    func send(report: RegionReport?) {
        defer { onUpdate?() }
        routeGate = requirements.evaluateProbe(report: report, now: Date(), uptime: LeaseClock.now)
        auditor.refresh(requirements: requirements, challenge: policyChallenge, scope: policyScopeDigest)
        policyEvidence = auditor.evidence
        if routeGate == .matched && !PolicyEvidenceVerifier.valid(policyEvidence, challenge: policyChallenge,
            scope: policyScopeDigest, profileDigest: requirements.expectedProfileDigest, now: Date(), uptime: LeaseClock.now) { routeGate = .policyUnverified }
        if routeGate == .matched && report?.proxyOwner != policyEvidence?.surgeOwner { routeGate = .policyUnverified }
        guard let connection else { return }
        let generation = callbacks.generation
        policyRequestID += 1
        let requestID = policyRequestID
        let block = routeGate != .matched
        // Repeated delivery cannot extend the original report's expiry.
        let expiry = block ? nil : report.map {
            min($0.checkedUptime + FilterDecisionState.lease, policyEvidence?.expiresClock ?? 0)
        }
        guard let data = try? JSONEncoder().encode(FilterPolicyUpdate(sequence: UInt64(requestID), providerGeneration: providerGeneration, policyEvidence: policyEvidence, bootID: providerBootID, controlSessionID: controlSessionID, block: block, validUntil: expiry)) else { return }
        let proxy = connection.remoteObjectProxyWithErrorHandler { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, self.callbacks.generation == generation, self.policyRequestID == requestID else { return }
                self.connectionFailed()
            }
        } as? FilterControlProtocol
        proxy?.updatePolicy(data) { [weak self] accepted in
            DispatchQueue.main.async {
                guard let self, self.callbacks.generation == generation, self.policyRequestID == requestID else { return }
                if !accepted { self.acknowledgement.invalidate() }
                self.readStatus()
            }
        }
    }

    private func readStatus() {
        guard let connection, let token = callbacks.begin() else { return }
        let requestedAt = LeaseClock.now
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self, self.callbacks.finish(token) else { return }
            self.connectionFailed()
        }
        let proxy = connection.remoteObjectProxyWithErrorHandler { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, self.callbacks.finish(token) else { return }
                self.connectionFailed()
            }
        } as? FilterControlProtocol
        proxy?.status { [weak self] data in
            DispatchQueue.main.async {
                // finish checks connection generation AND request ID, consumes
                // once, and rejects late success after an error or timeout.
                guard let self, self.callbacks.finish(token) else { return }
                guard LeaseClock.now - requestedAt < 5,
                      data.count < 4096, let status = try? JSONDecoder().decode(FilterStatus.self, from: data),
                      status.protocolVersion == 2, status.networkGeneration != nil, status.bootID != nil, status.controlSessionID != nil, status.policyChallenge != nil, status.scopeDigest != nil,
                      status.proxyEndpoint == self.requirements.proxy,
                      status.routeAllowed != nil, status.routeDenied != nil, status.unknownOwnerFlows != nil,
                      status.blockedFlows >= 0 else { self.connectionFailed(); return }
                self.policyChallenge = status.policyChallenge ?? ""
                self.policyScopeDigest = status.scopeDigest ?? ""
                if self.providerGeneration != status.networkGeneration || self.providerBootID != status.bootID || self.controlSessionID != status.controlSessionID {
                    self.providerBootID = status.bootID; self.controlSessionID = status.controlSessionID
                    self.providerGeneration = status.networkGeneration
                    self.auditor.invalidate()
                    self.onPolicyInvalidated?()
                }
                self.invalidationReason = status.invalidationReason ?? "unknown"
                self.reconnectAttempts = 0
                self.acknowledgement = FilterAcknowledgement(status: status, receivedAt: LeaseClock.now)
                self.blocking = status.blocking; self.blockedFlows = status.blockedFlows
                self.routeAllowed = status.routeAllowed ?? 0; self.routeDenied = status.routeDenied ?? 0
                self.unknownOwnerFlows = status.unknownOwnerFlows ?? 0
                self.message = nil; self.onUpdate?()
            }
        }
    }

    func disable(completion: ((Bool) -> Void)? = nil) {
        guard !pending else { completion?(false); return }
        pending = true
        message = LocalizedMessage("正在停用过滤器配置…", "Disabling filter configuration…")
        onUpdate?()
        let manager = NEFilterManager.shared()
        manager.loadFromPreferences { [weak self] error in
            if error == nil && manager.providerConfiguration == nil {
                DispatchQueue.main.async {
                    guard let self else { completion?(false); return }
                    self.pending = false; self.finishDisable(); self.onUpdate?(); completion?(true)
                }; return
            }
            guard error == nil, manager.providerConfiguration?.filterDataProviderBundleIdentifier == FilterConstants.bundleID,
                  FilterScope.ownerUID(manager.providerConfiguration?.vendorConfiguration?["ownerUID"] as? NSNumber) == geteuid() else {
                DispatchQueue.main.async {
                    self?.pending = false
                    self?.message = LocalizedMessage("无法确认这是当前用户的过滤器，未修改配置。", "Could not verify ownership of this filter; no settings were changed.")
                    self?.onUpdate?()
                    completion?(false)
                }
                return
            }
            manager.isEnabled = false
            manager.saveToPreferences { error in
                DispatchQueue.main.async {
                    guard let self else { completion?(false); return }
                    self.pending = false
                    if error == nil {
                        self.finishDisable()
                    }
                    else { self.message = LocalizedMessage("关闭过滤器失败，请在系统设置中检查。", "Could not disable the filter; check System Settings.") }
                    self.onUpdate?()
                    completion?(error == nil)
                }
            }
        }
    }
    private func finishDisable() {
        message = nil; configured = false; callbacks.reconnect(); retryScheduled = false
        acknowledgement.invalidate(); connection?.invalidate(); connection = nil
        statusTimer?.invalidate(); statusTimer = nil
    }
    private func requestRemoval() {
        let request = OSSystemExtensionRequest.deactivationRequest(forExtensionWithIdentifier: FilterConstants.bundleID, queue: .main)
        removalRequest = request; request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request); onUpdate?()
    }
    func uninstall() {
        disable { [weak self] success in
            guard let self, success else { return }
            self.pending = true
            let manager = NEFilterManager.shared()
            manager.loadFromPreferences { error in
                if error == nil && manager.providerConfiguration == nil {
                    DispatchQueue.main.async { self.requestRemoval() }; return
                }
                guard error == nil,
                      manager.providerConfiguration?.filterDataProviderBundleIdentifier == FilterConstants.bundleID,
                      FilterScope.ownerUID(manager.providerConfiguration?.vendorConfiguration?["ownerUID"] as? NSNumber) == geteuid() else {
                    DispatchQueue.main.async { self.pending = false; self.onUpdate?() }; return
                }
                manager.removeFromPreferences { error in
                    DispatchQueue.main.async {
                        if error != nil {
                            self.pending = false
                            self.message = LocalizedMessage("配置移除失败；过滤器已停用，可重试。", "Configuration removal failed; filter disabled, retry available.")
                            self.onUpdate?(); return
                        }
                        self.requestRemoval()
                    }
                }
            }
        }
    }

}

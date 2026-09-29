import AppKit
import Foundation
enum GuardUIState: Equatable {
    case checking, disabled, blocked, verified
    static func resolved(configured: Bool?, active: Bool, blocking: Bool, safe: Bool) -> GuardUIState {
        if configured == false { return .disabled }
        if !active { return .checking }
        if blocking { return .blocked }
        return safe ? .verified : .checking
    }
}
enum GuardTheme {
    static func adaptive(_ name: String, light: UInt32, dark: UInt32) -> NSColor {
        NSColor(name: NSColor.Name(name)) { appearance in
            let h = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((h >> 16) & 255)/255, green: CGFloat((h >> 8) & 255)/255, blue: CGFloat(h & 255)/255, alpha: 1)
        }
    }
    static let canvas = adaptive("GuardCanvas", light: 0xF5F3EC, dark: 0x262624)
    static let card = adaptive("GuardPaper", light: 0xFFFEFA, dark: 0x30302E)
    static let ink = adaptive("GuardInk", light: 0x302F29, dark: 0xFAF9F5)
    static let muted = adaptive("GuardMuted", light: 0x746F65, dark: 0xC2C0B6)
    static let line = adaptive("GuardLine", light: 0xDDD8CC, dark: 0x45443F)
    static let clay = adaptive("GuardClay", light: 0xA95438, dark: 0xE39173)
    static let sage = adaptive("GuardSage", light: 0x48624E, dark: 0xA5BEA1)
    static func editorial(_ size: CGFloat) -> NSFont { NSFont(name: "Georgia", size: size) ?? .systemFont(ofSize: size, weight: .medium) }
}
struct GuardUISnapshot {
    var state: GuardUIState = .checking
    var allowed: Int? = nil
    var denied: Int? = nil
    var unknown: Int? = nil
    var reason = ""
    var notifications = ""
    var events: [GuardConnectionEvent] = []
    var journalAvailable = false
    var journalFresh = false
    var configured: Bool? = nil
    var pending = false
    var monitoring = false
    var lastStatusAt: Date? = nil
    var canEdit: Bool { configured == false && !pending }
    var canEnable: Bool { !pending && state != .verified && configured != nil }

}

enum EndpointInputProblem: Error, Equatable {
    case port, reservedPort, exits, policy
    var fieldIndex: Int { switch self { case .port, .reservedPort: return 0; case .exits: return 1; case .policy: return 2 } }
    var message: String {
        switch self {
        case .port: return L10n.text("端口请输入 1–65535 的整数，例如 6154。", "Enter a whole-number port from 1 to 65535, such as 6154.")
        case .reservedPort: return L10n.text("6152、6153、6162、6163 是共享或旧版端口，请使用专用端口。", "6152, 6153, 6162 and 6163 are shared or legacy ports. Use a dedicated port.")
        case .exits: return L10n.text("请输入有效的 IPv4 或 IPv6 出口地址；多个地址用逗号分隔，最多 16 个。", "Enter valid IPv4 or IPv6 egress addresses, separated by commas if needed (up to 16).")
        case .policy: return L10n.text("请输入单节点策略名称；不能为 DIRECT、REJECT、PROXY，也不能包含逗号或换行。", "Enter a single-node policy name without commas or line breaks. DIRECT, REJECT and PROXY are not valid names.")
        }
    }
}
enum EndpointFormInput {
    static func validate(port: String, exits: String, policy: String) -> Result<RouteRequirements, EndpointInputProblem> {
        let port = port.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !port.isEmpty, port.utf8.allSatisfy({ (48...57).contains($0) }), let number = UInt16(port), number > 0 else { return .failure(.port) }
        guard ![6152,6153,6162,6163].contains(number) else { return .failure(.reservedPort) }
        guard var value = RouteRequirements.parse(proxyAddress: "127.0.0.1", proxyPort: String(number), exits: exits) else { return .failure(.exits) }
        let policy = policy.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !policy.isEmpty, !policy.contains(where: { ",\n\r".contains($0) }), !["DIRECT","REJECT","PROXY"].contains(policy.uppercased()) else { return .failure(.policy) }
        value.surgePolicy = policy; value.expectedProfileDigest = String(repeating: "0", count: 64)
        return .success(value)
    }
}
final class EndpointSettingsEditor: NSObject {
    private let alert = NSAlert()
    private var fields: [NSTextField] = []
    private let errorLabel = NSTextField(wrappingLabelWithString: " ")
    private var validated: RouteRequirements?
    init(config: RouteRequirements) {
        super.init()
        alert.messageText = GuardString.settingsTitle.text; alert.informativeText = GuardString.settingsHelp.text
        let view = NSStackView(); view.orientation = .vertical; view.alignment = .leading; view.spacing = 8
        let values = [(GuardString.port.text, String(config.proxy?.port ?? 6154)),
            (GuardString.exitIP.text, config.expectedExitAddresses.joined(separator: ", ")),
            (GuardString.policy.text, config.surgePolicy.isEmpty ? "CLAUDE-LOCKED" : config.surgePolicy)]
        for (label, value) in values {
            view.addArrangedSubview(NSTextField(labelWithString: label))
            let field = NSTextField(string: value); field.widthAnchor.constraint(equalToConstant: 440).isActive = true
            field.setAccessibilityLabel(label); view.addArrangedSubview(field); fields.append(field)
        }
        errorLabel.textColor = GuardTheme.clay; errorLabel.font = .systemFont(ofSize: 12)
        errorLabel.widthAnchor.constraint(equalToConstant: 440).isActive = true
        errorLabel.heightAnchor.constraint(equalToConstant: 48).isActive = true
        view.addArrangedSubview(errorLabel)
        view.frame = NSRect(x: 0, y: 0, width: 440, height: 250); alert.accessoryView = view
        let cancel = alert.addButton(withTitle: GuardString.cancel.text); cancel.keyEquivalent = "\u{1b}"
        let save = alert.addButton(withTitle: GuardString.save.text)
        save.keyEquivalent = "\r"; save.target = self; save.action = #selector(validateAndSubmit)
    }
    @objc private func validateAndSubmit() {
        switch EndpointFormInput.validate(port: fields[0].stringValue, exits: fields[1].stringValue, policy: fields[2].stringValue) {
        case .failure(let issue):
            errorLabel.stringValue = issue.message
            errorLabel.setAccessibilityLabel(issue.message)
            alert.window.makeFirstResponder(fields[issue.fieldIndex]); fields[issue.fieldIndex].selectText(nil)
        case .success(let value):
            validated = value; NSApp.stopModal(withCode: .alertSecondButtonReturn)
        }
    }
    func run() -> RouteRequirements? {
        let result = alert.runModal()
        alert.window.orderOut(nil)
        return result == .alertSecondButtonReturn ? validated : nil
    }
}

enum GuardEventQuery {
    static func apply(_ events: [GuardConnectionEvent], filter: Int, query: String, key: String, ascending: Bool) -> [GuardConnectionEvent] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return events.filter { e in
            (filter == 0 || e.decision == (filter == 1 ? "allow" : "deny")) && (q.isEmpty ||
                [e.client, e.destination, e.transport, String(e.pid), e.reason, e.cause ?? ""].joined(separator: " ").localizedCaseInsensitiveContains(q))
        }.sorted { a, b in
            if key == "time" { return ascending ? a.id < b.id : a.id > b.id }
            func value(_ e: GuardConnectionEvent) -> String {
                switch key { case "client": return e.client; case "destination": return e.destination; case "transport": return e.transport; case "decision": return e.decision; default: return e.reason + (e.cause ?? "") }
            }
            let x = value(a), y = value(b)
            if x == y { return a.id > b.id }
            return ascending ? x < y : x > y
        }
    }
}

class GuardCard: NSView {
    var accent: NSColor? { didSet { needsDisplay = true } }
    override var wantsUpdateLayer: Bool { true }
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.borderWidth = 1
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func updateLayer() {
        layer?.backgroundColor = GuardTheme.card.cgColor
        layer?.borderColor = (accent?.withAlphaComponent(0.24) ?? GuardTheme.line).cgColor
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
}
final class GuardMetric: GuardCard {
    let value = NSTextField(labelWithString: "—")
    let actionButton = NSButton()
    init(title: String, symbol: String, color: NSColor) {
        super.init(frame: .zero)
        let icon = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil) ?? NSImage())
        icon.contentTintColor = color
        icon.widthAnchor.constraint(equalToConstant: 15).isActive = true
        actionButton.title = title + " ›"; actionButton.isBordered = false
        actionButton.font = .systemFont(ofSize: 12, weight: .medium)
        actionButton.setAccessibilityLabel(title)
        let heading = NSStackView(views: [icon, actionButton]); heading.spacing = 7
        value.font = GuardTheme.editorial(26)
        value.textColor = GuardTheme.ink
        let stack = NSStackView(views: [heading, value]); stack.orientation = .vertical
        stack.alignment = .leading; stack.spacing = 9
        stack.translatesAutoresizingMaskIntoConstraints = false; addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 14), stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14)])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

#if !CCW_PREVIEW
import SystemConfiguration
import UserNotifications
import Darwin
#endif

struct ClientRow { let pid: Int32; let name: String }
protocol WatcherModel: AnyObject {
    var onChange: (() -> Void)? { get set }
    var rows: [ClientRow] { get }
    var ipv6: String { get }
    var state: String { get }
    var detail: String { get }
    var isPreview: Bool { get }
    var presentation: GuardUISnapshot { get }
    var config: RouteRequirements { get }
    func refresh()
    func recheck()
    func languageDidChange()
    func configure(_ value: RouteRequirements, completion: @escaping (String?) -> Void)
    func enable()
    func disable(_ completion: @escaping (Bool) -> Void)
    func lock()
    func prepareTermination() -> () -> Void
    func stop()
}
final class PreviewModel: WatcherModel {
    var onChange: (() -> Void)?
    var rows = [ClientRow(pid:10001,name:GuardString.sampleDesktop.text),ClientRow(pid:10002,name:GuardString.sampleCLI.text)]
    var ipv6:String { GuardString.sampleIPv6.text }
    private var stateMessage = GuardString.previewState.message
    var state:String { stateMessage.value }
    var detail:String { GuardString.previewDetail.text }
    let isPreview = true
    private var uiState: GuardUIState = .verified
    var presentation: GuardUISnapshot {
        GuardUISnapshot(state: uiState, allowed: uiState == .disabled ? nil : 18,
            denied: uiState == .disabled ? nil : 4, unknown: uiState == .disabled ? nil : 3,
            reason: GuardString.previewDetail.text,
            notifications: L10n.text("通知 · 示例状态", "Notifications · Sample state"),
            events: sampleEvents, journalAvailable: true, journalFresh: true, configured: uiState != .disabled, monitoring: uiState == .verified, lastStatusAt: Date())
    }
    private var sampleEvents: [GuardConnectionEvent] {
        var journal = GuardConnectionJournal()
        journal.append(pid: 10001, client: "com.anthropic.claudefordesktop", destination: "127.0.0.1:6154", transport: "TCP", allowed: true, reason: "verified-route")
        journal.append(pid: 10002, client: "com.anthropic.claude-code", destination: "127.0.0.1:6152", transport: "TCP", allowed: false, reason: "wrong-endpoint")
        journal.append(pid: 10002, client: "com.anthropic.claude-code", destination: "203.0.113.10:443", transport: "UDP", allowed: false, reason: "wrong-endpoint")
        journal.append(pid: 10001, client: "com.anthropic.claudefordesktop", destination: "127.0.0.1:6154", transport: "TCP", allowed: false, reason: "permission-withdrawn")
        return journal.events
    }
    var config = RouteRequirements()
    init() {
        config = RouteRequirements.parse(proxyAddress: "127.0.0.1", proxyPort: "6154", exits: "203.0.113.10")!
        config.surgePolicy = "CLAUDE-LOCKED"
    }
    func recheck() { onChange?() }
    func showChecking() { uiState = .checking; onChange?() }
    func refresh() { onChange?() }
    func languageDidChange() {
        rows=rows.map { ClientRow(pid:$0.pid,name:$0.pid == 10001 ? GuardString.sampleDesktop.text : GuardString.sampleCLI.text) }
        onChange?()
    }
    func configure(_ value: RouteRequirements, completion: @escaping (String?) -> Void) { config=value; completion(nil); onChange?() }
    func enable() { uiState = .verified; stateMessage=GuardString.sampleAllowed.message; onChange?() }
    func disable(_ completion: @escaping (Bool) -> Void) { uiState = .disabled; stateMessage=GuardString.sampleDisabled.message; completion(true); onChange?() }
    func lock() { uiState = .blocked; stateMessage=GuardString.sampleBlocked.message; onChange?() }
    func prepareTermination() -> () -> Void { let selected=Set(rows.map(\.pid)); return { self.rows.removeAll { selected.contains($0.pid) }; self.onChange?() } }
    func stop() {}
}
#if !CCW_PREVIEW
final class SafetyNotifier: NSObject, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()
    private var statusMessage = GuardString.notifyUnknown.message
    var status:String { statusMessage.value }
    private var authorized = false
    var onChange: (() -> Void)?
    override init() { super.init(); center.delegate = self }
    func requestPermission() {
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] allowed, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.authorized = allowed && error == nil
                self.statusMessage = self.authorized ? GuardString.notifyAllowed.message : GuardString.notifyDenied.message
                self.onChange?()
            }
        }
    }
    func warn() {
        guard authorized else { return }
        let content = UNMutableNotificationContent()
        content.title = GuardString.notifyTitle.text
        content.body = GuardString.notifyBody.text
        content.sound = .default
        center.add(UNNotificationRequest(identifier: "surge-guard-unsafe", content: content, trigger: nil)) { [weak self] error in
            guard error != nil else { return }
            DispatchQueue.main.async { self?.statusMessage = GuardString.notifyFailed.message }
        }
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) { completionHandler([.banner, .sound]) }
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        DispatchQueue.main.async { NSApp.activate(ignoringOtherApps: true); NSApp.windows.first?.makeKeyAndOrderFront(nil) }
        completionHandler()
    }
}
final class LiveModel: WatcherModel {
    var onChange: (() -> Void)?
    private(set) var rows: [ClientRow] = []
    private var ipv6Messages=[GuardString.ipv6Reading.message]
    var ipv6:String { ipv6Messages.map(\.value).joined(separator:"\n") }
    private var stateMessage=GuardString.readingState.message
    var state:String { stateMessage.value }
    private(set) var detail=""
    let isPreview=false
    private(set) var presentation = GuardUISnapshot()
    private let controller=FilterController()
    private let notifier=SafetyNotifier()
    private var alertGate=SafetyAlertGate()
    private let queue=DispatchQueue(label:"Watcher.background",qos:.utility)
    private var timer:Timer?
    private var records:[ProcessRecord]=[]
    private var sampling=false
    private var probing=false
    private var generation=0
    private var report:RegionReport?
    private var monitoring=false
    var config:RouteRequirements { controller.requirements }
    init() {
        notifier.onChange = { [weak self] in self?.alertGate = SafetyAlertGate(); self?.renderState() }
        controller.onUpdate = { [weak self] in self?.renderState() }
        controller.onPolicyInvalidated = { [weak self] in self?.report=nil; self?.renderState() }
        controller.onPolicyUpdated = { [weak self] in guard let self, self.monitoring else { return }; self.controller.send(report:self.report) }
        controller.readConfigurationOnly()
        timer=Timer.scheduledTimer(withTimeInterval:2,repeats:true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer!,forMode:.common)
        refresh()
    }
    private func renderState() {
        let safe = GuardPresentation.isSafe(monitoring:monitoring,routeMatched:controller.routeGate == .matched,probeFresh:report?.canProvideFilterLease(at:Date(),uptime:LeaseClock.now) == true,active:controller.active,blocking:controller.blocking)
        if controller.configured == false { stateMessage=GuardString.disabled.message }
        else if !controller.active { stateMessage=GuardString.unknownEnforcement.message }
        else if controller.blocking { stateMessage=GuardString.blocked.message }
        else if safe { stateMessage=GuardString.allowed.message }
        else { stateMessage=GuardString.awaitingBlock.message }
        detail="\(controller.message?.value ?? ProtectionReason.title(controller.policyAuditReason))\n" + L10n.text("放行判定 \(controller.routeAllowed) · 拒绝判定 \(controller.routeDenied) · 未知归属 \(controller.unknownOwnerFlows)\n未知归属和系统过滤器故障不在已验证覆盖保证内。", "Allowed \(controller.routeAllowed) · Denied \(controller.routeDenied) · Unknown owner \(controller.unknownOwnerFlows)\nUnknown attribution and filter failures are outside verified coverage.")
        detail += "\n" + notifier.status
        let uiState = GuardUIState.resolved(configured: controller.configured, active: controller.active, blocking: controller.blocking, safe: safe)
        presentation = GuardUISnapshot(state: uiState, allowed: controller.connectionAllowed,
            denied: controller.connectionDenied, unknown: controller.unknownOwnerFlows,
            reason: controller.message?.value ?? ProtectionReason.title(controller.policyAuditReason),
            notifications: notifier.status, events: controller.connectionEvents, journalAvailable: controller.journalAvailable, journalFresh: controller.active, configured: controller.configured, pending: controller.pending, monitoring: monitoring, lastStatusAt: controller.lastStatusAt)
        if alertGate.update(monitoring:monitoring,safe:safe) { notifier.warn() }
        onChange?()
    }
    func recheck() {
        guard !controller.pending else { return }
        controller.retryStatus()
        refresh()
        if monitoring { tick() }
    }
    func languageDidChange() { renderState() }
    private func tick() {
        refresh()
        if !monitoring, controller.configured == true, config.localAuditConfigured,
           UserDefaults.standard.bool(forKey:"SurgeGuardProbeConsentV1") {
            monitoring=true; notifier.requestPermission(); controller.connect()
        }
        guard monitoring else { return }
        controller.send(report:report)
        guard !probing, let endpoint=config.proxy else { return }
        probing=true; let epoch=generation
        queue.async {
            let owner=LocalSurgeAuditor.listener(endpoint)
            let result=owner.flatMap { GuardProbe.collect(endpoint:endpoint,owner:$0) }
            DispatchQueue.main.async {
                self.probing=false
                guard self.monitoring,self.generation==epoch else { return }
                self.report=result; self.controller.send(report:result); self.renderState()
            }
        }
    }
    func refresh() {
        guard !sampling else { return }; sampling=true
        queue.async {
            let all=ProcessInventory().collect()
            let selected=all.values.filter { row in
                row.isOfficialClient || VerifiedAncestry.containsOfficialParent(of:row.identity.pid,uid:row.identity.effectiveUID) { pid in
                    guard let node=all[pid],let fresh=captureProcessIdentity(pid:pid),fresh==node.identity else { return nil }
                    var info=proc_bsdinfo(); let size=Int32(MemoryLayout<proc_bsdinfo>.stride)
                    guard proc_pidinfo(pid,PROC_PIDTBSDINFO,0,&info,size)==size else { return nil }
                    return AncestryNode(pid:pid,parent:Int32(info.pbi_ppid),uid:info.pbi_uid,startedBefore:fresh.startSeconds*1_000_000+fresh.startMicroseconds,startedAfter:info.pbi_start_tvsec*1_000_000+info.pbi_start_tvusec,officialSignature:node.isOfficialClient)
                }
            }.sorted { $0.identity.pid < $1.identity.pid }
            let ip=Self.ipv6Status()
            DispatchQueue.main.async { self.records=selected; self.rows=selected.map { ClientRow(pid:$0.identity.pid,name:$0.owner.name) };self.ipv6Messages=ip;self.sampling=false;self.onChange?() }
        }
    }
    static func ipv6Status()->[LocalizedMessage] {
        guard let prefs=SCPreferencesCreate(nil,"Watcher Read Only" as CFString,nil),let set=SCNetworkSetCopyCurrent(prefs),let services=SCNetworkSetCopyServices(set) as? [SCNetworkService] else { return [GuardString.ipv6Unreadable.message] }
        var lines:[LocalizedMessage]=[]
        for service in services {
            guard let iface=SCNetworkServiceGetInterface(service),let kind=SCNetworkInterfaceGetInterfaceType(iface),[kSCNetworkInterfaceTypeIEEE80211,kSCNetworkInterfaceTypeEthernet].contains(kind) else { continue }
            let serviceName=SCNetworkServiceGetName(service) as String?
            let name=serviceName.map { LocalizedMessage($0,$0) } ?? GuardString.physicalNetwork.message
            guard let proto=SCNetworkServiceCopyProtocol(service,kSCNetworkProtocolTypeIPv6) else { lines.append(LocalizedMessage(name.chinese+"：未配置IPv6",name.english+": IPv6 not configured"));continue }
            let value=SCNetworkProtocolGetConfiguration(proto) as? [String:Any]
            let enabled=SCNetworkProtocolGetEnabled(proto) && SCNetworkServiceGetEnabled(service)
            let method=value?[kSCPropNetIPv6ConfigMethod as String] as? String ?? ""
            let mode:LocalizedMessage
            switch method { case "Automatic": mode=GuardString.automatic.message; case "Manual": mode=GuardString.manualMode.message; case "LinkLocal": mode=GuardString.linkLocal.message; default: mode=GuardString.unknown.message }
            lines.append(LocalizedMessage(name.chinese+"："+(enabled ? "已启用（"+mode.chinese+"）" : "已关闭"),name.english+": "+(enabled ? "Enabled ("+mode.english+")" : "Off")))
        }
        return lines.isEmpty ? [GuardString.noServices.message] : lines
    }
    func configure(_ input:RouteRequirements,completion:@escaping(String?)->Void) {
        guard controller.configured == false,!controller.active else { completion(GuardString.disableBeforeConfig.text);return }
        queue.async {
            var value=input
            guard LocalSurgeAuditor.verifiedCLI(),let profile=LocalSurgeAuditor.json(["dump","profile","effective"])?["profile"] as? String else { DispatchQueue.main.async { completion(GuardString.surgeReadFailed.text) };return }
            value.expectedProfileDigest=PolicyEvidenceVerifier.digest(Data(profile.utf8))
            guard SurgeContract.validate(profile:profile,requirements:value) else { DispatchQueue.main.async { completion(GuardString.contractFailed.text) };return }
            DispatchQueue.main.async { completion(self.controller.saveRequirements(value) ? nil : GuardString.changedNotSaved.text) }
        }
    }
    func enable() {
        guard config.localAuditConfigured else { stateMessage=GuardString.configureFirst.message;onChange?();return }
        UserDefaults.standard.set(true,forKey:"SurgeGuardProbeConsentV1")
        generation += 1;report=nil;monitoring=true;notifier.requestPermission();controller.activate(protectedBundleIDs:[])
    }
    func lock() { generation += 1;monitoring=false;report=nil;UserDefaults.standard.set(false,forKey:"SurgeGuardProbeConsentV1");controller.send(report:nil, blockReason:"manual-block");renderState() }
    func disable(_ completion:@escaping(Bool)->Void) { lock();controller.disable(completion:completion) }
    func prepareTermination() -> () -> Void {
        let selected=records
        return { [weak self] in
        guard let self else { return }
        self.queue.async {
            for row in selected where !ProcessInventory.isProtected(row.identity) {
                guard captureProcessIdentity(pid:row.identity.pid)==row.identity else { continue }
                _ = kill(row.identity.pid,SIGTERM)
            }
            DispatchQueue.main.async { self.refresh() }
        }
        }
    }
    func stop() { timer?.invalidate();timer=nil;lock() }
}
#endif

final class TopAlignedStack: NSStackView { override var isFlipped: Bool { true } }

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    var window: NSWindow!
    let model: WatcherModel
    var renderOnly = false
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private let compactState = NSTextField(wrappingLabelWithString: "")
    private let compactProcesses = NSTextField(wrappingLabelWithString: "")
    private var state = NSTextField(wrappingLabelWithString: "")
    private var detail = NSTextField(wrappingLabelWithString: "")
    private var reason = NSTextField(wrappingLabelWithString: "")
    private var notifications = NSTextField(wrappingLabelWithString: "")
    private var ipv6 = NSTextField(wrappingLabelWithString: "")
    private var processCount = NSTextField(labelWithString: "")
    private var emptyProcesses = NSTextField(wrappingLabelWithString: "")
    private var endpoint = NSTextField(labelWithString: "")
    private var policy = NSTextField(labelWithString: "")
    private var stateIcon = NSImageView()
    private var hero = GuardCard()
    private var primary = NSButton()
    private var metrics: [GuardMetric] = []
    private var table = NSTableView()
    private var eventTable = NSTableView()
    private var eventFilter = NSSegmentedControl()
    private var eventNote = NSTextField(wrappingLabelWithString: "")
    private var eventEmpty = NSTextField(wrappingLabelWithString: "")
    private var visibleEvents: [GuardConnectionEvent] = []
    private var eventSignature = ""
    private var search = NSSearchField()
    private var query = ""
    private var sortKey = "time"
    private var sortAscending = false
    private var detailButton = NSButton()
    private var copyButton = NSButton()
    private var configureButton = NSButton()
    private var enableButton = NSButton()
    private var disableButton = NSButton()
    private var checkButton = NSButton()
    private var checkTime = NSTextField(wrappingLabelWithString: "")
    private var selectedEventFilter = 0
    private var tabSelector = NSSegmentedControl()
    private var panels: [NSView] = []
    private var selectedPanel = 0
    private var rowsSignature = ""
    private var contentWidth: NSLayoutConstraint?
    private var contentHeight: NSLayoutConstraint?
    init(model: WatcherModel) { self.model = model; super.init() }
    private func text(_ value: String, size: CGFloat = 13, weight: NSFont.Weight = .regular, secondary: Bool = false) -> NSTextField {
        let v = NSTextField(wrappingLabelWithString: value)
        v.font = .systemFont(ofSize: size, weight: weight)
        v.textColor = secondary ? GuardTheme.muted : GuardTheme.ink
        v.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return v
    }
    private func stack(_ views: [NSView], axis: NSUserInterfaceLayoutOrientation = .vertical, spacing: CGFloat = 12) -> NSStackView {
        let v = NSStackView(views: views); v.orientation = axis; v.spacing = spacing; v.distribution = .fill
        v.alignment = axis == .vertical ? .leading : .centerY
        return v
    }
    private func fill(_ child: NSView, in parent: NSView, padding: CGFloat = 20) {
        child.translatesAutoresizingMaskIntoConstraints = false; parent.addSubview(child)
        NSLayoutConstraint.activate([child.leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: padding),
            child.trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: -padding),
            child.topAnchor.constraint(equalTo: parent.topAnchor, constant: padding),
            child.bottomAnchor.constraint(equalTo: parent.bottomAnchor, constant: -padding)])
    }
    private func button(_ title: String, _ action: Selector, symbol: String? = nil) -> NSButton {
        let b = NSButton(title: title, target: self, action: action); b.bezelStyle = .rounded; b.controlSize = .regular
        if let symbol { b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil); b.imagePosition = .imageLeading }
        b.setContentHuggingPriority(.required, for: .horizontal)
        return b
    }
    private func separator() -> NSBox { let box = NSBox(); box.boxType = .separator; return box }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        if let url = Bundle.main.url(forResource: "Watcher", withExtension: "icns"), let icon = NSImage(contentsOf: url) { NSApp.applicationIconImage = icon }
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1040, height: 820), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.delegate = self; window.isReleasedWhenClosed = false; window.minSize = NSSize(width: 900, height: 740)
        window.backgroundColor = GuardTheme.canvas
        buildInterface(); window.setContentSize(NSSize(width: 1040, height: 820)); window.contentMinSize = NSSize(width: 900, height: 740); window.center(); if !renderOnly { show() }
    }
    private func buildInterface() {
        window.title = model.isPreview ? GuardString.previewTitle.text : "fuck-anthropic guard"
        popover.close(); rowsSignature = ""; eventSignature = ""; panels.removeAll(); metrics.removeAll()
        state = text("", size: 23, weight: .regular); state.font = GuardTheme.editorial(23); detail = text("", size: 13, secondary: true)
        reason = text("", size: 12, secondary: true); notifications = text("", size: 12, secondary: true)
        ipv6 = text("", size: 13); processCount = text("", size: 13, weight: .medium)
        emptyProcesses = text(GuardString.noProcesses.text, size: 14, secondary: true)
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.drawsBackground = true; scroll.backgroundColor = GuardTheme.canvas
        let body = TopAlignedStack(); body.distribution = .fill; body.setHuggingPriority(.required, for: .vertical); body.orientation = .vertical; body.alignment = .leading; body.spacing = 16
        body.edgeInsets = NSEdgeInsets(top: 22, left: 26, bottom: 20, right: 26)
        body.translatesAutoresizingMaskIntoConstraints = false; scroll.documentView = body
        let container = NSView(frame: NSRect(origin: .zero, size: window.contentLayoutRect.size))
        container.autoresizingMask = [.width, .height]
        window.contentView = container
        contentWidth = container.widthAnchor.constraint(equalToConstant: window.contentLayoutRect.width)
        contentHeight = container.heightAnchor.constraint(equalToConstant: window.contentLayoutRect.height)
        contentWidth?.isActive = true; contentHeight?.isActive = true
        fill(scroll, in: container, padding: 0)
        NSLayoutConstraint.activate([body.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor), body.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor), body.topAnchor.constraint(equalTo: scroll.contentView.topAnchor)])
        func add(_ v: NSView) { body.addArrangedSubview(v); v.widthAnchor.constraint(equalTo: body.widthAnchor, constant: -52).isActive = true }
        let wordmark = text("Guard", size: 32); wordmark.font = GuardTheme.editorial(32)
        let titleBlock = stack([wordmark, text(L10n.text("Claude 连接保护", "Claude connection protection"), size: 12, secondary: true)], spacing: 2)
        let picker = NSPopUpButton(); picker.addItems(withTitles: ["简体中文", "English"]); picker.selectItem(at: L10n.language == .chinese ? 0 : 1)
        picker.controlSize = .small; picker.target = self; picker.action = #selector(changeLanguage(_:)); picker.setAccessibilityLabel(GuardString.language.text)
        let head = stack([titleBlock, NSView(), picker, button(L10n.text("外观", "Theme"), #selector(toggleTheme), symbol: "circle.lefthalf.filled"), button(GuardString.manual.text, #selector(manual), symbol: "questionmark.circle")], axis: .horizontal)
        titleBlock.setContentHuggingPriority(.required, for: .horizontal); add(head)
        if model.isPreview {
            let demo = text(L10n.text("界面预览 · 以下均为示例数据，不代表本机防护状态", "UI PREVIEW · Sample data only. This is not your Mac’s protection status."), size: 12, weight: .medium)
            demo.textColor = GuardTheme.clay; add(demo)
        }
        hero = GuardCard()
        stateIcon = NSImageView(); stateIcon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 30, weight: .regular)
        stateIcon.widthAnchor.constraint(equalToConstant: 48).isActive = true; stateIcon.heightAnchor.constraint(equalToConstant: 48).isActive = true
        primary = button("", #selector(enable))
        let stateBlock = stack([state, detail], spacing: 6)
        let top = stack([stateIcon, stateBlock, primary], axis: .horizontal, spacing: 16)
        endpoint = text("", size: 12, weight: .medium); policy = text("", size: 12, weight: .medium)
        let route = stack([text("Claude", size: 12, weight: .semibold), text("→", secondary: true), endpoint, text("→", secondary: true), policy], axis: .horizontal, spacing: 10)
        let heroBody = stack([top, separator(), route], spacing: 17)
        for v in [top, heroBody.arrangedSubviews[1]] { v.widthAnchor.constraint(equalTo: heroBody.widthAnchor).isActive = true }
        fill(heroBody, in: hero); add(hero)
        metrics = [GuardMetric(title: L10n.text("允许连接", "ALLOWED"), symbol: "arrow.up.right", color: GuardTheme.sage),
            GuardMetric(title: L10n.text("拒绝 / 撤销", "DENIED / REVOKED"), symbol: "hand.raised", color: GuardTheme.clay),
            GuardMetric(title: L10n.text("归属未知", "UNKNOWN OWNER"), symbol: "questionmark.circle", color: GuardTheme.muted)]
        metrics[0].actionButton.target = self; metrics[0].actionButton.action = #selector(showAllowed)
        metrics[1].actionButton.target = self; metrics[1].actionButton.action = #selector(showDenied)
        metrics[2].actionButton.target = self; metrics[2].actionButton.action = #selector(explainUnknown)
        metrics[0].toolTip = L10n.text("查看允许记录", "View allowed connections")
        metrics[1].toolTip = L10n.text("查看拒绝与撤销记录", "View denied and revoked connections")
        let counts = stack(metrics, axis: .horizontal, spacing: 12); counts.distribution = .fillEqually; add(counts)
        let caveat = text(L10n.text("仅保护已识别的客户端及可追溯子进程；未知归属与系统过滤故障不在已验证覆盖内。", "Coverage is limited to recognized clients and traceable children. Unknown owners and filter failures are not verified."), size: 11, secondary: true)
        add(caveat)
        let panelCard = GuardCard()
        tabSelector = NSSegmentedControl(labels: [L10n.text("连接记录", "Connections"), L10n.text("客户端", "Clients"), L10n.text("工作原理", "How it works"), L10n.text("设置与诊断", "Settings & diagnostics")], trackingMode: .selectOne, target: self, action: #selector(changePanel(_:)))
        tabSelector.selectedSegment = selectedPanel; tabSelector.segmentStyle = .rounded; tabSelector.setAccessibilityLabel(L10n.text("详情类别", "Detail category"))
        let content = NSView(); content.heightAnchor.constraint(equalToConstant: 294).isActive = true
        panels = [connectionsPanel(), processPanel(), networkPanel(), settingsPanel()]
        for (i, panel) in panels.enumerated() { fill(panel, in: content, padding: 0); panel.isHidden = i != selectedPanel }
        let panelBody = stack([tabSelector, content], spacing: 18); content.widthAnchor.constraint(equalTo: panelBody.widthAnchor).isActive = true
        fill(panelBody, in: panelCard); add(panelCard)
        let footer = text(L10n.text("由 Surge 转发流量 · Guard 负责连接许可 · 关闭窗口后继续运行", "Surge routes traffic · Guard controls connection permission · Closing this window keeps Guard running"), size: 11, secondary: true)
        add(footer)
        buildMenus(); buildPopover()
        model.onChange = { [weak self] in self?.render() }; render()
    }
    private func connectionsPanel() -> NSView {
        eventFilter = NSSegmentedControl(labels: [L10n.text("全部", "All"), L10n.text("允许", "Allowed"), L10n.text("拒绝", "Denied")], trackingMode: .selectOne, target: self, action: #selector(filterEvents(_:)))
        eventFilter.selectedSegment = selectedEventFilter
        eventNote = text("", size: 12, secondary: true)
        eventEmpty = text("", size: 13, secondary: true)
        eventTable = NSTableView(); eventTable.rowHeight = 49; eventTable.backgroundColor = .clear
        eventTable.dataSource = self; eventTable.delegate = self; eventTable.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        eventTable.intercellSpacing = NSSize(width: 10, height: 1)
        eventTable.target = self; eventTable.doubleAction = #selector(eventDetails)
        let columns: [(String, String, CGFloat)] = [
            ("time", L10n.text("时间", "Time"), 64), ("decision", L10n.text("判定", "Decision"), 68),
            ("client", L10n.text("进程", "Process"), 150), ("destination", L10n.text("连接目标", "Destination"), 190),
            ("transport", L10n.text("协议", "Protocol"), 50), ("reason", L10n.text("原因", "Reason"), 210)]
        for (id, title, width) in columns { let c = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id)); c.title = title; c.width = width; c.minWidth = 45; c.sortDescriptorPrototype = NSSortDescriptor(key: id, ascending: id != "time"); eventTable.addTableColumn(c) }
        eventTable.sortDescriptors = [NSSortDescriptor(key: sortKey, ascending: sortAscending)]
        let scroller = NSScrollView(); scroller.documentView = eventTable; scroller.hasVerticalScroller = true; scroller.hasHorizontalScroller = true; scroller.autohidesScrollers = true; scroller.drawsBackground = false
        let list = NSView(); fill(scroller, in: list, padding: 0)
        eventEmpty.translatesAutoresizingMaskIntoConstraints = false; list.addSubview(eventEmpty)
        NSLayoutConstraint.activate([eventEmpty.centerXAnchor.constraint(equalTo: list.centerXAnchor), eventEmpty.centerYAnchor.constraint(equalTo: list.centerYAnchor), eventEmpty.widthAnchor.constraint(lessThanOrEqualTo: list.widthAnchor, constant: -24)])
        search = NSSearchField(); search.placeholderString = L10n.text("搜索进程、PID 或目标", "Search process, PID or endpoint"); search.stringValue = query; search.delegate = self; search.target = self; search.action = #selector(searchChanged); search.sendsSearchStringImmediately = true
        search.widthAnchor.constraint(equalToConstant: 240).isActive = true
        detailButton = button(L10n.text("详情…", "Details…"), #selector(eventDetails))
        copyButton = button(L10n.text("复制", "Copy"), #selector(copyEvent))
        let toolbar = stack([eventFilter, NSView(), search, detailButton, copyButton], axis: .horizontal, spacing: 8)
        let v = stack([toolbar, list, eventNote], spacing: 10)
        toolbar.widthAnchor.constraint(equalTo: v.widthAnchor).isActive = true
        list.widthAnchor.constraint(equalTo: v.widthAnchor).isActive = true; list.heightAnchor.constraint(greaterThanOrEqualToConstant: 155).isActive = true
        eventNote.widthAnchor.constraint(equalTo: v.widthAnchor).isActive = true
        return v
    }
    private func eventReason(_ reason: String) -> String {
        switch reason {
        case "verified-route": return L10n.text("专用入口和许可有效", "Verified endpoint and lease")
        case "wrong-endpoint": return L10n.text("未使用专用 TCP 入口", "Outside dedicated TCP endpoint")
        case "permission-unavailable": return L10n.text("连接许可无效或已过期", "Connection lease unavailable")
        case "flow-capacity": return L10n.text("已达可跟踪连接上限", "Flow tracking capacity reached")
        default: return L10n.text("许可撤销，关闭已有连接", "Lease withdrawn; flow closed")
        }
    }
    private func renderEvents(_ snapshot: GuardUISnapshot) {
        let selectedID = visibleEvents.indices.contains(eventTable.selectedRow) ? visibleEvents[eventTable.selectedRow].id : nil
        visibleEvents = GuardEventQuery.apply(snapshot.events, filter: selectedEventFilter, query: query, key: sortKey, ascending: sortAscending)
        let signature = String(selectedEventFilter) + query + sortKey + String(sortAscending) + L10n.language.rawValue + String(describing: snapshot.events)
        if signature != eventSignature {
            eventSignature = signature; eventTable.reloadData()
            if let id = selectedID, let index = visibleEvents.firstIndex(where: { $0.id == id }) { eventTable.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false) }
            else { eventTable.deselectAll(nil) }
        }
        detailButton.isEnabled = visibleEvents.indices.contains(eventTable.selectedRow); copyButton.isEnabled = detailButton.isEnabled
        eventEmpty.isHidden = !visibleEvents.isEmpty
        eventEmpty.stringValue = !snapshot.journalAvailable ? L10n.text("当前过滤扩展尚未提供连接明细。", "The current filter does not provide connection details yet.") : (query.isEmpty ? L10n.text("暂无此类记录；等待已识别客户端产生新连接。", "No records in this category yet.") : L10n.text("没有匹配结果。试试其他关键词或清空搜索。", "No matches. Try another search or clear it."))
        eventNote.stringValue = (!snapshot.journalFresh ? L10n.text("状态未同步 · ", "Status not current · ") : "") + L10n.text("最近 80 条，仅存过滤器内存；重启扩展后重置。计数含已有连接被撤销。允许不代表网站请求成功；未知归属只计数，不记录其他应用。", "Latest 80 events, held only in filter memory; reset on extension restart. Denials include revoked flows. Allowed does not mean website success. Unknown owners are counted without unrelated app history.")
    }
    @objc private func filterEvents(_ sender: NSSegmentedControl) { selectedEventFilter = sender.selectedSegment; renderEvents(model.presentation) }
    private func selectEvents(_ filter: Int) { selectedEventFilter = filter; selectedPanel = 0; tabSelector.selectedSegment = 0; eventFilter.selectedSegment = filter; for (i, panel) in panels.enumerated() { panel.isHidden = i != 0 }; renderEvents(model.presentation) }
    @objc private func showAllowed() { selectEvents(1) }
    @objc private func showDenied() { selectEvents(2) }
    @objc private func toggleTheme() {
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) != .darkAqua
        NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        if !model.isPreview { UserDefaults.standard.set(dark ? "dark" : "light", forKey: "GuardAppearance") }
    }
    @objc private func explainUnknown() { message(L10n.text("归属未知不是泄漏次数，也不是拦截次数。\n\n过滤器无法可靠确定部分连接是否属于受保护客户端，因此只累计次数，不把它们算作已保护，也不保存其他应用的连接明细。计数在过滤扩展重启后重置。", "Unknown ownership is neither a leak count nor a blocked count.\n\nSome connections cannot be reliably attributed to protected clients. They are counted as a coverage gap; other applications’ connection details are not retained. This counter resets when the filter restarts.")) }
    @objc private func searchChanged() { query = search.stringValue; renderEvents(model.presentation) }
    func controlTextDidChange(_ notification: Notification) { guard notification.object as? NSSearchField === search else { return }; query = search.stringValue; renderEvents(model.presentation) }
    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        guard tableView === eventTable, let descriptor = tableView.sortDescriptors.first else { return }
        sortKey = descriptor.key ?? "time"; sortAscending = descriptor.ascending; renderEvents(model.presentation)
    }
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard notification.object as? NSTableView === eventTable else { return }
        detailButton.isEnabled = visibleEvents.indices.contains(eventTable.selectedRow); copyButton.isEnabled = detailButton.isEnabled
    }
    private func eventText(_ event: GuardConnectionEvent) -> String {
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        return [formatter.string(from: Date(timeIntervalSince1970: event.timestamp)),
            "PID: \(event.pid) · \(event.client)", "\(event.transport) → \(event.destination)",
            (event.decision == "allow" ? L10n.text("允许", "Allowed") : L10n.text("拒绝 / 撤销", "Denied / revoked")) + " · " + eventReason(event.reason),
            L10n.text("触发依据：", "Trigger: ") + causeTitle(event.cause)].joined(separator: "\n")
    }
    @objc private func eventDetails() { guard visibleEvents.indices.contains(eventTable.selectedRow) else { return }; message(eventText(visibleEvents[eventTable.selectedRow])) }
    @objc private func copyEvent() {
        guard visibleEvents.indices.contains(eventTable.selectedRow) else { return }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(eventText(visibleEvents[eventTable.selectedRow]), forType: .string)
        copyButton.title = L10n.text("已复制", "Copied")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.copyButton.title = L10n.text("复制", "Copy") }
    }
    private func causeTitle(_ cause: String?) -> String {
        guard let cause else { return L10n.text("该记录未提供额外触发原因", "No additional trigger recorded") }
        switch cause {
        case "manual-block": return L10n.text("用户主动阻断连接", "Connections blocked by user")
        case "lease-expired": return L10n.text("许可有效期结束，未及时取得新许可", "Lease expired before renewal")
        case "probe-unavailable": return L10n.text("出口探测未取得有效结果", "No valid egress probe result")
        case "exit-mismatch": return L10n.text("出口IP与预期不符", "Egress IP differs from expected")
        case "exit-unknown": return L10n.text("出口IP无法确认", "Egress IP could not be established")
        case "policy-unverified": return L10n.text("本地策略证据未通过或已过期", "Local policy evidence invalid or expired")
        case "policy-rejected": return L10n.text("过滤扩展拒绝了策略证明", "Filter rejected policy evidence")
        case "surge-process-lost": return L10n.text("Surge进程身份已变化或退出", "Surge process changed or exited")
        case "host-blocked": return L10n.text("主程序未发放许可，细项不可用", "Host withheld permission; no finer detail")
        default: return ProtectionReason.title(cause)
        }
    }

    private func processPanel() -> NSView {
        table = NSTableView(); table.headerView = nil; table.rowHeight = 27; table.backgroundColor = .clear
        table.intercellSpacing = NSSize(width: 0, height: 3); table.focusRingType = .none
        table.dataSource = self; table.delegate = self; table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        for (id, width) in [("name", CGFloat(440)), ("pid", CGFloat(120))] { let c = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id)); c.width = width; c.minWidth = 100; table.addTableColumn(c) }
        let scroller = NSScrollView(); scroller.documentView = table; scroller.hasVerticalScroller = true; scroller.autohidesScrollers = true; scroller.drawsBackground = false
        let list = NSView(); fill(scroller, in: list, padding: 0); emptyProcesses.translatesAutoresizingMaskIntoConstraints = false; list.addSubview(emptyProcesses)
        NSLayoutConstraint.activate([emptyProcesses.centerXAnchor.constraint(equalTo: list.centerXAnchor), emptyProcesses.centerYAnchor.constraint(equalTo: list.centerYAnchor)])
        let heading = stack([processCount, NSView(), button(GuardString.refresh.text, #selector(refresh), symbol: "arrow.clockwise"), button(L10n.text("退出客户端…", "Quit clients…"), #selector(quitClients))], axis: .horizontal, spacing: 10)
        let result = stack([heading, list], spacing: 8)
        heading.widthAnchor.constraint(equalTo: result.widthAnchor).isActive = true; list.widthAnchor.constraint(equalTo: result.widthAnchor).isActive = true
        list.heightAnchor.constraint(greaterThanOrEqualToConstant: 140).isActive = true
        return result
    }
    private func networkPanel() -> NSView {
        let title = text(L10n.text("Guard 不提供 VPN 连接", "Guard does not provide a VPN"), size: 18, weight: .medium)
        let architecture = text(L10n.text("Claude → Guard 系统过滤 → 本机 Surge :6154 → 代理节点 → 网站\n\nSurge 负责加密传输与出口。Guard 核对入口、固定策略与出口证明；许可失效时拦截已识别连接。记录中的 127.0.0.1 是本机代理入口，不是最终网站。", "Claude → Guard system filter → local Surge :6154 → proxy node → website\n\nSurge provides transport and egress. Guard verifies the endpoint, pinned policy and egress evidence; an invalid lease blocks recognized connections. 127.0.0.1 in the journal is the local proxy, not the final website."), size: 12)
        let help = text(GuardString.ipv6Help.text, size: 11, secondary: true)
        let v = stack([title, architecture, ipv6, help], spacing: 10)
        for child in v.arrangedSubviews { child.widthAnchor.constraint(equalTo: v.widthAnchor).isActive = true }
        return v
    }
    private func settingsPanel() -> NSView {
        configureButton = button("", #selector(settings), symbol: "slider.horizontal.3")
        enableButton = button("", #selector(enable)); disableButton = button(GuardString.disable.text, #selector(disable))
        checkButton = button(L10n.text("重新检查", "Recheck"), #selector(recheck), symbol: "arrow.clockwise")
        checkTime = text("", size: 12, secondary: true)
        let controls = stack([configureButton, checkButton, enableButton, disableButton], axis: .horizontal, spacing: 10)
        let version = text("Guard " + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Preview") + " · " + L10n.text("构建 ", "Build ") + (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"), size: 13, weight: .medium)
        let v = stack([version, controls, reason, checkTime, notifications, text(L10n.text("入口配置、启用或停用均需明确操作。此面板不修改 Surge，也不提供 VPN 或 SSH 通道。", "Configuration, enable and disable are explicit actions. This panel does not modify Surge or provide a VPN or SSH tunnel."), size: 11, secondary: true)], spacing: 12)
        for child in v.arrangedSubviews { child.widthAnchor.constraint(equalTo: v.widthAnchor).isActive = true }
        return v
    }
    private func buildMenus() {
        let menu = NSMenu(); let appItem = NSMenuItem(); menu.addItem(appItem); let items = NSMenu(); appItem.submenu = items
        let open = items.addItem(withTitle: GuardString.open.text, action: #selector(show), keyEquivalent: "1"); open.target = self
        items.addItem(.separator()); items.addItem(withTitle: GuardString.quitMenu.text, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let editItem = NSMenuItem(); menu.addItem(editItem); let edit = NSMenu(title: GuardString.edit.text); editItem.submenu = edit
        for (name, action, key) in [(GuardString.copy.text,"copy:","c"),(GuardString.paste.text,"paste:","v"),(GuardString.selectAll.text,"selectAll:","a")] { edit.addItem(withTitle: name, action: Selector(action), keyEquivalent: key) }
        let wItem = NSMenuItem(); menu.addItem(wItem); let wm = NSMenu(title: GuardString.window.text); wItem.submenu = wm
        wm.addItem(withTitle: GuardString.closeWindow.text, action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"); NSApp.mainMenu = menu; NSApp.windowsMenu = wm
        if statusItem == nil { statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength) }
        statusItem?.button?.image = NSImage(systemSymbolName: "shield.lefthalf.filled", accessibilityDescription: "Guard")
        statusItem?.button?.toolTip = L10n.text("查看连接保护", "View connection protection")
        statusItem?.button?.target = self; statusItem?.button?.action = #selector(togglePopover)
    }
    private func buildPopover() {
        compactState.font = .systemFont(ofSize: 16, weight: .semibold); compactProcesses.font = .systemFont(ofSize: 12); compactProcesses.textColor = GuardTheme.muted
        let v = stack([text(model.isPreview ? L10n.text("Guard · 预览", "Guard · Preview") : "Guard", size: 20, weight: .bold), compactState, compactProcesses,
            stack([button(L10n.text("打开主窗口", "Open window"), #selector(show)), button(GuardString.refresh.text, #selector(refresh))], axis: .horizontal)], spacing: 14)
        v.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        for view in v.arrangedSubviews { view.widthAnchor.constraint(equalToConstant: 300).isActive = true }
        let vc = NSViewController(); vc.view = v; popover.contentViewController = vc; popover.behavior = .transient; popover.contentSize = NSSize(width: 340, height: 205)
    }
    private func render() {
        let snapshot = model.presentation
        let title: String; let subtitle: String; let symbol: String; let color: NSColor
        switch snapshot.state {
        case .verified:
            title = L10n.text("连接保护已就绪", "Connection protection is ready")
            subtitle = L10n.text("已识别客户端可通过已验证的 Surge 路径连接。", "Recognized clients may use the verified Surge route.")
            symbol = "checkmark.shield"; color = GuardTheme.sage
        case .blocked:
            title = L10n.text("已识别连接已阻断", "Recognized connections are blocked")
            subtitle = L10n.text("当前没有发放连接许可。确认入口后再启用保护。", "Connection permission is withheld. Verify the endpoint before enabling.")
            symbol = "hand.raised"; color = GuardTheme.clay
        case .disabled:
            title = L10n.text("保护尚未开启", "Protection is not enabled")
            subtitle = L10n.text("先配置专用入口，再启用系统连接保护。", "Configure a dedicated endpoint, then enable system protection.")
            symbol = "shield.slash"; color = GuardTheme.muted
        case .checking:
            title = L10n.text("正在确认保护状态", "Confirming protection status")
            subtitle = L10n.text("系统过滤执行或路径条件尚未确认，请勿视为已保护。", "Filter enforcement or route conditions are unconfirmed.")
            symbol = "exclamationmark.shield"; color = GuardTheme.clay
        }
        state.stringValue = title; detail.stringValue = subtitle; stateIcon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        stateIcon.contentTintColor = color; hero.accent = color
        compactState.stringValue = title; compactState.textColor = color
        compactProcesses.stringValue = L10n.text("已识别进程：", "Recognized processes: ") + String(model.rows.count) + "\n" + L10n.text("专用入口 · ", "Dedicated endpoint · ") + String(model.config.proxy?.port ?? 6154)
        let resumeTitle = snapshot.configured == true ? L10n.text("恢复连接检查…", "Resume checks…") : GuardString.enable.text
        if snapshot.state == .verified { primary.title = L10n.text("阻断Claude连接…", "Block Claude connections…"); primary.action = #selector(lock) }
        else if snapshot.state == .checking { primary.title = L10n.text("重新检查", "Recheck"); primary.action = #selector(recheck) }
        else { primary.title = resumeTitle; primary.action = #selector(enable) }
        primary.isEnabled = !snapshot.pending
        configureButton.title = snapshot.canEdit ? L10n.text("配置入口…", "Configure endpoint…") : L10n.text("查看入口…", "View endpoint…")
        configureButton.isEnabled = !snapshot.pending
        enableButton.title = snapshot.state == .verified ? L10n.text("保护已启用", "Protection enabled") : resumeTitle
        enableButton.isEnabled = snapshot.canEnable
        disableButton.isEnabled = !snapshot.pending && snapshot.configured == true
        checkButton.isEnabled = !snapshot.pending
        if let date = snapshot.lastStatusAt { let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; checkTime.stringValue = L10n.text("最后收到过滤器状态：", "Last filter status: ") + f.string(from: date) + (snapshot.journalFresh ? "" : L10n.text("（已过期）", " (stale)")) }
        else { checkTime.stringValue = L10n.text("尚未收到过滤器状态", "No filter status received yet") }
        endpoint.stringValue = model.config.proxy.map { "Surge · \($0.port)" } ?? L10n.text("Surge · 待配置", "Surge · Not configured")
        policy.stringValue = model.config.surgePolicy.isEmpty ? L10n.text("固定上游 · 待配置", "Pinned upstream · Not configured") : model.config.surgePolicy
        for (view, value) in zip(metrics, [snapshot.allowed, snapshot.denied, snapshot.unknown]) { view.value.stringValue = value.map(String.init) ?? "—" }
        processCount.stringValue = L10n.text("已识别 \(model.rows.count) 个进程", "\(model.rows.count) recognized processes")
        emptyProcesses.isHidden = !model.rows.isEmpty
        let signature = model.rows.map { "\($0.pid):\($0.name)" }.joined(separator: "|")
        if signature != rowsSignature { rowsSignature = signature; table.reloadData() }
        ipv6.stringValue = model.ipv6; reason.stringValue = snapshot.reason.isEmpty ? model.state : snapshot.reason
        notifications.stringValue = snapshot.notifications
        renderEvents(snapshot)
    }
    func numberOfRows(in tableView: NSTableView) -> Int { tableView === eventTable ? visibleEvents.count : model.rows.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if tableView === eventTable {
            guard visibleEvents.indices.contains(row) else { return nil }
            let event = visibleEvents[row]; let key = tableColumn?.identifier.rawValue ?? ""
            let label: String
            switch key {
            case "time": let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; label = f.string(from: Date(timeIntervalSince1970: event.timestamp))
            case "decision": label = event.decision == "allow" ? L10n.text("允许", "Allowed") : L10n.text("拒绝", "Denied")
            case "client":
                let name = event.client.contains("claude-code") ? "Claude Code" : event.client.contains("claudefordesktop") ? "Claude Desktop" : (event.client.isEmpty ? L10n.text("身份未命名", "Unnamed identity") : event.client.split(separator: ".").last.map(String.init) ?? event.client)
                label = name + "\nPID " + String(event.pid)
            case "destination": label = event.destination
            case "transport": label = event.transport
            default: label = eventReason(event.reason) + (event.cause.map { "\n" + causeTitle($0) } ?? "")
            }
            let field = text(label, size: 12)
            field.maximumNumberOfLines = 2; field.lineBreakMode = .byTruncatingTail
            field.toolTip = key == "client" ? event.client + " · PID " + String(event.pid) : label
            if key == "decision" { field.textColor = event.decision == "allow" ? GuardTheme.sage : GuardTheme.clay }
            return field
        }
        guard model.rows.indices.contains(row) else { return nil }
        let item = model.rows[row]; let pid = tableColumn?.identifier.rawValue == "pid"
        let v = NSTextField(labelWithString: pid ? "PID \(item.pid)" : item.name)
        v.font = pid ? .monospacedDigitSystemFont(ofSize: 12, weight: .regular) : .systemFont(ofSize: 13, weight: .medium)
        v.textColor = pid ? GuardTheme.muted : GuardTheme.ink; v.lineBreakMode = .byTruncatingTail
        return v
    }
    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        contentWidth?.constant = frameSize.width
        contentHeight?.constant = frameSize.height - (sender.frame.height - sender.contentLayoutRect.height)
        return frameSize
    }
    func windowDidResize(_ notification: Notification) {
        contentWidth?.constant = window.contentLayoutRect.width
        contentHeight?.constant = window.contentLayoutRect.height
    }
    @objc private func changePanel(_ sender: NSSegmentedControl) {
        selectedPanel = sender.selectedSegment
        for (i, panel) in panels.enumerated() { panel.isHidden = i != selectedPanel }
    }
    @objc private func changeLanguage(_ sender: NSPopUpButton) {
        L10n.language = sender.indexOfSelectedItem == 0 ? .chinese : .english
        model.languageDidChange(); buildInterface()
    }
    private func confirm(_ title:String,_ text:String)->Bool { let a=NSAlert();a.messageText=title;a.informativeText=text;a.addButton(withTitle:GuardString.cancel.text);a.addButton(withTitle:GuardString.proceed.text);return a.runModal() == .alertSecondButtonReturn }
    private func message(_ text:String) { let a=NSAlert();a.messageText=text;a.addButton(withTitle:L10n.text("好","OK"));a.runModal() }
    @objc func togglePopover() {
        guard let button=statusItem?.button else { return }
        if popover.isShown { popover.close() } else { render();popover.show(relativeTo:button.bounds,of:button,preferredEdge:.minY);NSApp.activate(ignoringOtherApps:true) }
    }
    @objc func show() { popover.close();window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true) }
    @objc func refresh() { model.refresh() }
    @objc func recheck() { model.recheck() }
    @objc func quitClients() { let terminate=model.prepareTermination(); if confirm(GuardString.quitTitle.text,GuardString.quitHelp.text) { terminate() } }
    @objc func enable() { if confirm(GuardString.enableTitle.text,GuardString.enableHelp.text) { model.enable() } }
    @objc func lock() {
        if confirm(L10n.text("阻断Claude连接？", "Block Claude connections?"), L10n.text("这会撤销连接许可，并中断已识别客户端的现有连接。Surge继续运行。稍后可用“恢复连接检查”重新验证后放行。", "This withdraws permission and interrupts existing recognized connections. Surge stays running. Resume checks later to verify the route and allow connections again.")) { model.lock() }
    }
    @objc func disable() { if confirm(GuardString.disableTitle.text,GuardString.disableHelp.text) { model.disable { [weak self] ok in if !ok { self?.message(GuardString.disableFailed.text) } } } }
    @objc func manual() { if let url=Bundle.main.url(forResource:L10n.language == .english ? "UserGuide.en" : "UserGuide",withExtension:"html") { NSWorkspace.shared.open(url) } }
    @objc func settings() {
        guard model.presentation.canEdit else {
            message(L10n.text("当前入口（只读）\n", "Current endpoint (read-only)\n") + (model.config.proxy?.label ?? "—") + "\n" + model.config.surgePolicy + "\n" + L10n.text("保护已开启或状态尚未确认，不能编辑配置。需要修改时，请先明确停用保护。", "Configuration cannot be edited while protection is enabled or unconfirmed. Explicitly disable protection first if a change is needed.")); return
        }
        guard let value = EndpointSettingsEditor(config: model.config).run() else { return }
        model.configure(value) { [weak self] error in self?.message(error ?? GuardString.saved.text) }
    }
    func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows flag:Bool)->Bool { show();return false }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool { false }
    func applicationShouldTerminate(_ sender:NSApplication)->NSApplication.TerminateReply {
        if model.isPreview { return .terminateNow }
        let a=NSAlert();a.messageText=GuardString.quitApp.text;a.informativeText=GuardString.quitAppHelp.text;a.addButton(withTitle:GuardString.cancel.text);a.addButton(withTitle:GuardString.quitKeep.text);a.addButton(withTitle:GuardString.quitDisable.text)
        let choice=a.runModal();if choice == .alertFirstButtonReturn { return .terminateCancel }
        if choice == .alertSecondButtonReturn { model.stop();return .terminateNow }
        model.disable { ok in sender.reply(toApplicationShouldTerminate:ok) };return .terminateLater
    }
    func applicationWillTerminate(_ notification:Notification) { model.stop() }
}
if CommandLine.arguments.contains("--self-test") { runGuardTests();exit(0) }
let app=NSApplication.shared
app.appearance = NSAppearance(named: UserDefaults.standard.string(forKey: "GuardAppearance") == "light" ? .aqua : .darkAqua)
#if CCW_PREVIEW
if let i=CommandLine.arguments.firstIndex(of:"--language"),CommandLine.arguments.indices.contains(i+1),let language=AppLanguage(rawValue:CommandLine.arguments[i+1]) { L10n.language=language }
let previewModel = PreviewModel()
if let i = CommandLine.arguments.firstIndex(of: "--preview-state"), CommandLine.arguments.indices.contains(i + 1) {
    switch CommandLine.arguments[i + 1] {
    case "blocked": previewModel.lock()
    case "disabled": previewModel.disable { _ in }
    case "checking": previewModel.showChecking()
    default: previewModel.enable()
    }
}
if let i = CommandLine.arguments.firstIndex(of: "--appearance"), CommandLine.arguments.indices.contains(i + 1) {
    app.appearance = NSAppearance(named: CommandLine.arguments[i + 1] == "dark" ? .darkAqua : .aqua)
}
let delegate=AppDelegate(model:previewModel)
#else
guard geteuid() != 0 else { fputs("Run Watcher as the logged-in user, not root.\n",stderr);exit(2) }
let delegate=AppDelegate(model:LiveModel())
#endif
app.delegate=delegate
#if CCW_PREVIEW
if let index=CommandLine.arguments.firstIndex(of:"--render-preview"),CommandLine.arguments.indices.contains(index+1) {
 delegate.renderOnly=true
 delegate.applicationDidFinishLaunching(Notification(name:NSApplication.didFinishLaunchingNotification))
 print("PREVIEW_BEFORE", NSStringFromRect(delegate.window.frame), NSStringFromRect(delegate.window.contentView!.bounds), NSStringFromSize(delegate.window.contentMinSize))
 if let i=CommandLine.arguments.firstIndex(of:"--preview-size"),CommandLine.arguments.indices.contains(i+1) {
  let parts=CommandLine.arguments[i+1].split(separator:"x").compactMap { Double($0) };if parts.count==2 { delegate.window.setContentSize(NSSize(width:parts[0],height:parts[1]));delegate.windowDidResize(Notification(name:NSWindow.didResizeNotification)) }
 }
 delegate.window.contentView?.layoutSubtreeIfNeeded()
 print("PREVIEW_AFTER", NSStringFromRect(delegate.window.frame), NSStringFromRect(delegate.window.contentView!.bounds))
 guard let view=delegate.window.contentView,let rep=view.bitmapImageRepForCachingDisplay(in:view.bounds) else { exit(2) }
 view.cacheDisplay(in:view.bounds,to:rep)
 try rep.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:CommandLine.arguments[index+1]));exit(0)
}
#endif
app.run()

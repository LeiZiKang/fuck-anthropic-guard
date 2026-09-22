import AppKit
import Foundation
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
    var config: RouteRequirements { get }
    func refresh()
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
    var config = RouteRequirements()
    func refresh() { onChange?() }
    func languageDidChange() {
        rows=rows.map { ClientRow(pid:$0.pid,name:$0.pid == 10001 ? GuardString.sampleDesktop.text : GuardString.sampleCLI.text) }
        onChange?()
    }
    func configure(_ value: RouteRequirements, completion: @escaping (String?) -> Void) { config=value; completion(nil); onChange?() }
    func enable() { stateMessage=GuardString.sampleAllowed.message; onChange?() }
    func disable(_ completion: @escaping (Bool) -> Void) { stateMessage=GuardString.sampleDisabled.message; completion(true); onChange?() }
    func lock() { stateMessage=GuardString.sampleBlocked.message; onChange?() }
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
        if alertGate.update(monitoring:monitoring,safe:safe) { notifier.warn() }
        onChange?()
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
    func lock() { generation += 1;monitoring=false;report=nil;UserDefaults.standard.set(false,forKey:"SurgeGuardProbeConsentV1");controller.send(report:nil);renderState() }
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

final class TopAlignedStack:NSStackView { override var isFlipped:Bool { true } }

final class AppDelegate:NSObject,NSApplicationDelegate {
    var window:NSWindow!
    let model:WatcherModel
    var renderOnly=false
    private var state=NSTextField(wrappingLabelWithString:"")
    private var detail=NSTextField(wrappingLabelWithString:"")
    private var processes=NSTextField(wrappingLabelWithString:"")
    private var ipv6=NSTextField(wrappingLabelWithString:"")
    private var statusItem:NSStatusItem?
    init(model:WatcherModel) { self.model=model;super.init() }
    func applicationDidFinishLaunching(_ notification:Notification) {
        NSApp.setActivationPolicy(.regular)
        if let url=Bundle.main.url(forResource:"Watcher",withExtension:"icns"),let icon=NSImage(contentsOf:url) { NSApp.applicationIconImage=icon }
        window=NSWindow(contentRect:NSRect(x:0,y:0,width:760,height:720),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
        window.title=model.isPreview ? GuardString.previewTitle.text : "fuck-anthropic guard"
        window.isReleasedWhenClosed=false;window.minSize=NSSize(width:660,height:600)
        buildInterface();window.center();if !renderOnly { show() }
    }
    private func buildInterface() {
        window.title=model.isPreview ? GuardString.previewTitle.text : "fuck-anthropic guard"
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        let scroll=NSScrollView();scroll.hasVerticalScroller=true;scroll.drawsBackground=false
        let body=TopAlignedStack();body.distribution = .fill;body.setHuggingPriority(.required,for:.vertical);body.orientation = .vertical;body.alignment = .leading;body.spacing=16;body.edgeInsets=NSEdgeInsets(top:28,left:28,bottom:28,right:28)
        body.translatesAutoresizingMaskIntoConstraints=false;scroll.documentView=body;window.contentView=scroll
        NSLayoutConstraint.activate([body.leadingAnchor.constraint(equalTo:scroll.contentView.leadingAnchor),body.trailingAnchor.constraint(equalTo:scroll.contentView.trailingAnchor),body.topAnchor.constraint(equalTo:scroll.contentView.topAnchor)])
        func title(_ text:String)->NSTextField { let x=NSTextField(labelWithString:text);x.font = .systemFont(ofSize:21,weight:.semibold);return x }
        func add(_ view:NSView) { body.addView(view,in:.top);view.widthAnchor.constraint(equalTo:body.widthAnchor,constant:-56).isActive=true }
        let languageRow=NSStackView();languageRow.spacing=10
        languageRow.addArrangedSubview(NSTextField(labelWithString:GuardString.language.text))
        let picker=NSPopUpButton();picker.addItems(withTitles:["简体中文","English"]);picker.selectItem(at:L10n.language == .chinese ? 0 : 1);picker.target=self;picker.action=#selector(changeLanguage(_:));languageRow.addArrangedSubview(picker);add(languageRow)
        add(title(GuardString.heading.text))
        add(NSTextField(wrappingLabelWithString:GuardString.subtitle.text))
        state.font = .systemFont(ofSize:17,weight:.semibold);add(state);detail.textColor = .secondaryLabelColor;add(detail)
        add(title(GuardString.processHeading.text));add(processes)
        add(buttons([(GuardString.refresh.text,#selector(refresh)),(GuardString.quitListed.text,#selector(quitClients))]));add(ipv6)
        add(NSTextField(wrappingLabelWithString:GuardString.ipv6Help.text))
        add(title(GuardString.guardHeading.text))
        add(NSTextField(wrappingLabelWithString:GuardString.guardHelp.text))
        add(buttons([(GuardString.configure.text,#selector(settings)),(GuardString.enable.text,#selector(enable))]))
        add(buttons([(GuardString.hold.text,#selector(lock)),(GuardString.disable.text,#selector(disable)),(GuardString.manual.text,#selector(manual))]))
        add(NSTextField(wrappingLabelWithString:GuardString.closeHelp.text))
        let menu=NSMenu();let appItem=NSMenuItem();menu.addItem(appItem);let items=NSMenu();appItem.submenu=items
        let open=items.addItem(withTitle:GuardString.open.text,action:#selector(show),keyEquivalent:"1");open.target=self
        items.addItem(.separator());items.addItem(withTitle:GuardString.quitMenu.text,action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q")
        let editItem=NSMenuItem();menu.addItem(editItem);let edit=NSMenu(title:GuardString.edit.text);editItem.submenu=edit
        for (name,action,key) in [(GuardString.copy.text,"copy:","c"),(GuardString.paste.text,"paste:","v"),(GuardString.selectAll.text,"selectAll:","a")] { edit.addItem(withTitle:name,action:Selector(action),keyEquivalent:key) }
        let wItem=NSMenuItem();menu.addItem(wItem);let wm=NSMenu(title:GuardString.window.text);wItem.submenu=wm;wm.addItem(withTitle:GuardString.closeWindow.text,action:#selector(NSWindow.performClose(_:)),keyEquivalent:"w");NSApp.mainMenu=menu;NSApp.windowsMenu=wm
        statusItem=NSStatusBar.system.statusItem(withLength:NSStatusItem.squareLength);statusItem?.button?.image=NSImage(systemSymbolName:"shield.lefthalf.filled",accessibilityDescription:"Watcher");statusItem?.button?.target=self;statusItem?.button?.action=#selector(show)
        model.onChange={ [weak self] in self?.render() };render()
    }
    @objc private func changeLanguage(_ sender:NSPopUpButton) {
        L10n.language=sender.indexOfSelectedItem == 0 ? .chinese : .english
        model.languageDidChange();buildInterface()
    }
    private func buttons(_ values:[(String,Selector)])->NSView { let stack=NSStackView();stack.orientation = .horizontal;stack.spacing=10;for (name,action) in values { let b=NSButton(title:name,target:self,action:action);b.bezelStyle = .rounded;stack.addArrangedSubview(b) };return stack }
    private func render() { state.stringValue=model.state;detail.stringValue=model.detail;processes.stringValue=model.rows.isEmpty ? GuardString.noProcesses.text : model.rows.map { "\($0.name) · PID \($0.pid)" }.joined(separator:"\n");ipv6.stringValue=model.ipv6 }
    private func confirm(_ title:String,_ text:String)->Bool { let a=NSAlert();a.messageText=title;a.informativeText=text;a.addButton(withTitle:GuardString.cancel.text);a.addButton(withTitle:GuardString.proceed.text);return a.runModal() == .alertSecondButtonReturn }
    private func message(_ text:String) { let a=NSAlert();a.messageText=text;a.addButton(withTitle:L10n.text("好","OK"));a.runModal() }
    @objc func show() { window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true) }
    @objc func refresh() { model.refresh() }
    @objc func quitClients() { let terminate=model.prepareTermination(); if confirm(GuardString.quitTitle.text,GuardString.quitHelp.text) { terminate() } }
    @objc func enable() { if confirm(GuardString.enableTitle.text,GuardString.enableHelp.text) { model.enable() } }
    @objc func lock() { model.lock() }
    @objc func disable() { if confirm(GuardString.disableTitle.text,GuardString.disableHelp.text) { model.disable { [weak self] ok in if !ok { self?.message(GuardString.disableFailed.text) } } } }
    @objc func manual() { if let url=Bundle.main.url(forResource:L10n.language == .english ? "UserGuide.en" : "UserGuide",withExtension:"html") { NSWorkspace.shared.open(url) } }
    @objc func settings() {
        let a=NSAlert();a.messageText=GuardString.settingsTitle.text;a.informativeText=GuardString.settingsHelp.text
        let view=NSStackView();view.orientation = .vertical;view.alignment = .leading;view.spacing=8
        let values=[(GuardString.port.text,String(model.config.proxy?.port ?? 6154)),(GuardString.exitIP.text,model.config.expectedExitAddresses.first ?? ""),(GuardString.policy.text,model.config.surgePolicy.isEmpty ? "CLAUDE-LOCKED" : model.config.surgePolicy)]
        var fields:[NSTextField]=[]
        for (label,value) in values { view.addArrangedSubview(NSTextField(labelWithString:label));let f=NSTextField(string:value);f.widthAnchor.constraint(equalToConstant:440).isActive=true;view.addArrangedSubview(f);fields.append(f) }
        view.frame=NSRect(x:0,y:0,width:440,height:180)
        a.accessoryView=view;a.addButton(withTitle:GuardString.cancel.text);a.addButton(withTitle:GuardString.save.text)
        guard a.runModal() == .alertSecondButtonReturn, var value=RouteRequirements.parse(proxyAddress:"127.0.0.1",proxyPort:fields[0].stringValue,exits:fields[1].stringValue) else { return }
        value.surgePolicy=fields[2].stringValue;value.expectedProfileDigest=String(repeating:"0",count:64)
        guard value.localAuditConfigured else { message(GuardString.configIncomplete.text);return }
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
#if CCW_PREVIEW
if let i=CommandLine.arguments.firstIndex(of:"--language"),CommandLine.arguments.indices.contains(i+1),let language=AppLanguage(rawValue:CommandLine.arguments[i+1]) { L10n.language=language }
let delegate=AppDelegate(model:PreviewModel())
#else
guard geteuid() != 0 else { fputs("Run Watcher as the logged-in user, not root.\n",stderr);exit(2) }
let delegate=AppDelegate(model:LiveModel())
#endif
app.delegate=delegate
#if CCW_PREVIEW
if let index=CommandLine.arguments.firstIndex(of:"--render-preview"),CommandLine.arguments.indices.contains(index+1) {
 delegate.renderOnly=true
 delegate.applicationDidFinishLaunching(Notification(name:NSApplication.didFinishLaunchingNotification))
 delegate.window.contentView?.layoutSubtreeIfNeeded()
 guard let view=delegate.window.contentView,let rep=view.bitmapImageRepForCachingDisplay(in:view.bounds) else { exit(2) }
 view.cacheDisplay(in:view.bounds,to:rep)
 try rep.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:CommandLine.arguments[index+1]));exit(0)
}
#endif
app.run()

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
    func configure(_ value: RouteRequirements, completion: @escaping (String?) -> Void)
    func enable()
    func disable(_ completion: @escaping (Bool) -> Void)
    func lock()
    func prepareTermination() -> () -> Void
    func stop()
}
final class PreviewModel: WatcherModel {
    var onChange: (() -> Void)?
    var rows = [ClientRow(pid:10001,name:"Claude Desktop（示例）"),ClientRow(pid:10002,name:"Claude Code（示例）")]
    var ipv6 = "Wi-Fi：已关闭（示例）\n以太网：自动（示例）"
    var state = "离线预览 · 不操作真实进程或网络"
    var detail = "这是可审阅的模拟界面。Preview不包含监测后端、系统授权、Surge CLI或联网探针。"
    let isPreview = true
    var config = RouteRequirements()
    func refresh() { onChange?() }
    func configure(_ value: RouteRequirements, completion: @escaping (String?) -> Void) { config=value; completion(nil); onChange?() }
    func enable() { state="示例：已验证Surge专用入口"; onChange?() }
    func disable(_ completion: @escaping (Bool) -> Void) { state="示例：保护未启用"; completion(true); onChange?() }
    func lock() { state="示例：验证失效，保持阻断"; onChange?() }
    func prepareTermination() -> () -> Void { let selected=Set(rows.map(\.pid)); return { self.rows.removeAll { selected.contains($0.pid) }; self.onChange?() } }
    func stop() {}
}
#if !CCW_PREVIEW
final class SafetyNotifier: NSObject, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()
    private(set) var status = "系统通知：尚未授权"
    private var authorized = false
    var onChange: (() -> Void)?
    override init() { super.init(); center.delegate = self }
    func requestPermission() {
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] allowed, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.authorized = allowed && error == nil
                self.status = self.authorized ? "系统通知：已授权（受专注模式和系统设置影响）" : "系统通知：不可用，请在系统设置中允许通知；请查看App状态"
                self.onChange?()
            }
        }
    }
    func warn() {
        guard authorized else { return }
        let content = UNMutableNotificationContent()
        content.title = "Claude连接保护需要注意"
        content.body = "无法确认安全路径，Watcher已撤销放行许可。请打开App查看过滤器状态与原因；执行未确认时不能视为已阻断。"
        content.sound = .default
        center.add(UNNotificationRequest(identifier: "surge-guard-unsafe", content: content, trigger: nil)) { [weak self] error in
            guard error != nil else { return }
            DispatchQueue.main.async { self?.status = "系统通知发送失败，请查看App状态" }
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
    private(set) var ipv6="IPv6：读取中"
    private(set) var state="正在读取配置；尚未确认保护"
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
        if controller.configured == false { state="系统保护未启用" }
        else if !controller.active { state="系统过滤执行未确认" }
        else if controller.blocking { state="已识别的Claude连接：阻断中" }
        else if safe { state="已验证Surge专用路径 · 允许已识别连接" }
        else { state="放行条件失效 · 等待阻断执行确认" }
        detail="\(controller.message?.value ?? controller.policyAuditReason)\n放行判定 \(controller.routeAllowed) · 拒绝判定 \(controller.routeDenied) · 未知归属 \(controller.unknownOwnerFlows)\n未知归属和系统过滤器故障不在已验证覆盖保证内。"
        detail += "\n" + notifier.status
        if alertGate.update(monitoring:monitoring,safe:safe) { notifier.warn() }
        onChange?()
    }
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
            DispatchQueue.main.async { self.records=selected; self.rows=selected.map { ClientRow(pid:$0.identity.pid,name:$0.owner.name) };self.ipv6=ip;self.sampling=false;self.onChange?() }
        }
    }
    static func ipv6Status()->String {
        guard let prefs=SCPreferencesCreate(nil,"Watcher Read Only" as CFString,nil),let set=SCNetworkSetCopyCurrent(prefs),let services=SCNetworkSetCopyServices(set) as? [SCNetworkService] else { return "IPv6：无法读取" }
        var lines:[String]=[]
        for service in services {
            guard let iface=SCNetworkServiceGetInterface(service),let kind=SCNetworkInterfaceGetInterfaceType(iface),[kSCNetworkInterfaceTypeIEEE80211,kSCNetworkInterfaceTypeEthernet].contains(kind) else { continue }
            let name=SCNetworkServiceGetName(service) as String? ?? "物理网络"
            guard let proto=SCNetworkServiceCopyProtocol(service,kSCNetworkProtocolTypeIPv6) else { lines.append(name+"：未配置IPv6");continue }
            let value=SCNetworkProtocolGetConfiguration(proto) as? [String:Any]
            let enabled=SCNetworkProtocolGetEnabled(proto) && SCNetworkServiceGetEnabled(service)
            lines.append(name+"："+(enabled ? "已启用（\(value?[kSCPropNetIPv6ConfigMethod as String] as? String ?? "未知")）" : "已关闭"))
        }
        return lines.isEmpty ? "未找到Wi-Fi/以太网服务" : lines.joined(separator:"\n")
    }
    func configure(_ input:RouteRequirements,completion:@escaping(String?)->Void) {
        guard controller.configured == false,!controller.active else { completion("请先停用本App的保护，或等待配置状态确认。");return }
        queue.async {
            var value=input
            guard LocalSurgeAuditor.verifiedCLI(),let profile=LocalSurgeAuditor.json(["dump","profile","effective"])?["profile"] as? String else { DispatchQueue.main.async { completion("无法只读验证Surge；设置未保存。") };return }
            value.expectedProfileDigest=PolicyEvidenceVerifier.digest(Data(profile.utf8))
            guard SurgeContract.validate(profile:profile,requirements:value) else { DispatchQueue.main.async { completion("Surge配置尚不满足专用入口、置顶规则和单节点要求。请查看使用说明；本App不会替你修改Surge。") };return }
            DispatchQueue.main.async { completion(self.controller.saveRequirements(value) ? nil : "状态已变化，未保存。") }
        }
    }
    func enable() {
        guard config.localAuditConfigured else { state="请先配置并验证Surge专用入口";onChange?();return }
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
        window=NSWindow(contentRect:NSRect(x:0,y:0,width:760,height:720),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
        window.title=model.isPreview ? "Watcher · 离线预览" : "Claude Connection Watcher"
        window.isReleasedWhenClosed=false;window.minSize=NSSize(width:600,height:560)
        let scroll=NSScrollView();scroll.hasVerticalScroller=true;scroll.drawsBackground=false
        let body=TopAlignedStack();body.distribution = .fill;body.setHuggingPriority(.required,for:.vertical);body.orientation = .vertical;body.alignment = .leading;body.spacing=16;body.edgeInsets=NSEdgeInsets(top:28,left:28,bottom:28,right:28)
        body.translatesAutoresizingMaskIntoConstraints=false;scroll.documentView=body;window.contentView=scroll
        NSLayoutConstraint.activate([body.leadingAnchor.constraint(equalTo:scroll.contentView.leadingAnchor),body.trailingAnchor.constraint(equalTo:scroll.contentView.trailingAnchor),body.topAnchor.constraint(equalTo:scroll.contentView.topAnchor)])
        func title(_ text:String)->NSTextField { let x=NSTextField(labelWithString:text);x.font = .systemFont(ofSize:21,weight:.semibold);return x }
        func add(_ view:NSView) { body.addView(view,in:.top);view.widthAnchor.constraint(equalTo:body.widthAnchor,constant:-56).isActive=true }
        add(title("Claude 进程与连接保护"))
        add(NSTextField(wrappingLabelWithString:"联网由Surge负责。Watcher不提供代理/VPN，不建立SSH，不读取VPS私钥。"))
        state.font = .systemFont(ofSize:17,weight:.semibold);add(state);detail.textColor = .secondaryLabelColor;add(detail)
        add(title("1 · 进程与IPv6状态"));add(processes)
        add(buttons([("刷新",#selector(refresh)),("退出所列Claude进程…",#selector(quitClients))]));add(ipv6)
        add(NSTextField(wrappingLabelWithString:"只显示物理网络服务的IPv6设置；不改设置、不等于测试IPv6外网连通。"))
        add(title("2 · Surge路径拦截"))
        add(NSTextField(wrappingLabelWithString:"只允许已识别客户端连接已验证的Surge专用入口。识别不明、开机首包及过滤器自身故障仍有覆盖边界。"))
        add(buttons([("配置Surge检查…",#selector(settings)),("启用保护…",#selector(enable))]))
        add(buttons([("保持阻断",#selector(lock)),("停用保护…",#selector(disable)),("使用说明",#selector(manual))]))
        add(NSTextField(wrappingLabelWithString:"关闭窗口不会退出App。退出App并保留过滤器时，已识别连接会转为阻断。"))
        let menu=NSMenu();let appItem=NSMenuItem();menu.addItem(appItem);let items=NSMenu();appItem.submenu=items
        let open=items.addItem(withTitle:"打开Watcher",action:#selector(show),keyEquivalent:"1");open.target=self
        items.addItem(.separator());items.addItem(withTitle:"退出Watcher…",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q")
        let editItem=NSMenuItem();menu.addItem(editItem);let edit=NSMenu(title:"编辑");editItem.submenu=edit
        for (name,action,key) in [("复制","copy:","c"),("粘贴","paste:","v"),("全选","selectAll:","a")] { edit.addItem(withTitle:name,action:Selector(action),keyEquivalent:key) }
        let wItem=NSMenuItem();menu.addItem(wItem);let wm=NSMenu(title:"窗口");wItem.submenu=wm;wm.addItem(withTitle:"关闭窗口",action:#selector(NSWindow.performClose(_:)),keyEquivalent:"w");NSApp.mainMenu=menu;NSApp.windowsMenu=wm
        statusItem=NSStatusBar.system.statusItem(withLength:NSStatusItem.squareLength);statusItem?.button?.image=NSImage(systemSymbolName:"shield.lefthalf.filled",accessibilityDescription:"Watcher");statusItem?.button?.target=self;statusItem?.button?.action=#selector(show)
        model.onChange={ [weak self] in self?.render() };render();window.center();if !renderOnly { show() }
    }
    private func buttons(_ values:[(String,Selector)])->NSView { let stack=NSStackView();stack.orientation = .horizontal;stack.spacing=10;for (name,action) in values { let b=NSButton(title:name,target:self,action:action);b.bezelStyle = .rounded;stack.addArrangedSubview(b) };return stack }
    private func render() { state.stringValue=model.state;detail.stringValue=model.detail;processes.stringValue=model.rows.isEmpty ? "未发现可可靠识别的Claude进程。" : model.rows.map { "\($0.name) · PID \($0.pid)" }.joined(separator:"\n");ipv6.stringValue=model.ipv6 }
    private func confirm(_ title:String,_ text:String)->Bool { let a=NSAlert();a.messageText=title;a.informativeText=text;a.addButton(withTitle:"取消");a.addButton(withTitle:"继续");return a.runModal() == .alertSecondButtonReturn }
    private func message(_ text:String) { let a=NSAlert();a.messageText=text;a.runModal() }
    @objc func show() { window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true) }
    @objc func refresh() { model.refresh() }
    @objc func quitClients() { let terminate=model.prepareTermination(); if confirm("退出所列Claude进程？","仅退出打开本确认框前列出的进程。会重新核对每个PID的用户、启动时间和路径，再发送SIGTERM；不操作Surge，不自动强杀。请先保存工作。") { terminate() } }
    @objc func enable() { if confirm("启用系统级连接保护？","需要macOS授权。验证不通过时已识别Claude连接将被阻断。验证会通过Surge向api.ipify.org发送不含账号的出口探针；不会修改Surge配置。") { model.enable() } }
    @objc func lock() { model.lock() }
    @objc func disable() { if confirm("停用系统保护？","停用后Watcher不再阻止Claude直连。") { model.disable { [weak self] ok in if !ok { self?.message("未确认停用，请检查系统设置。") } } } }
    @objc func manual() { if let url=Bundle.main.url(forResource:"UserGuide",withExtension:"html") { NSWorkspace.shared.open(url) } }
    @objc func settings() {
        let a=NSAlert();a.messageText="验证Surge专用入口";a.informativeText="这不是Watcher代理。请先阅读使用说明，并手动在Surge添加专用入口及置顶IN-PORT规则；共享6152/6153不支持，原有Xcode直连规则保持不变。保存会只读查询Surge并记录配置摘要，不保存代理密码。"
        let view=NSStackView();view.orientation = .vertical;view.alignment = .leading;view.spacing=8
        let values=[("Surge专用HTTP端口",String(model.config.proxy?.port ?? 6154)),("预期VPS出口IP",model.config.expectedExitAddresses.first ?? ""),("单节点策略组",model.config.surgePolicy.isEmpty ? "CLAUDE-LOCKED" : model.config.surgePolicy)]
        var fields:[NSTextField]=[]
        for (label,value) in values { view.addArrangedSubview(NSTextField(labelWithString:label));let f=NSTextField(string:value);f.widthAnchor.constraint(equalToConstant:440).isActive=true;view.addArrangedSubview(f);fields.append(f) }
        a.accessoryView=view;a.addButton(withTitle:"取消");a.addButton(withTitle:"验证并保存")
        guard a.runModal() == .alertSecondButtonReturn, var value=RouteRequirements.parse(proxyAddress:"127.0.0.1",proxyPort:fields[0].stringValue,exits:fields[1].stringValue) else { return }
        value.surgePolicy=fields[2].stringValue;value.expectedProfileDigest=String(repeating:"0",count:64)
        guard value.localAuditConfigured else { message("配置不完整，或使用了共享代理端口。");return }
        model.configure(value) { [weak self] error in self?.message(error ?? "配置已保存；系统保护尚需明确启用。") }
    }
    func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows flag:Bool)->Bool { show();return false }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool { false }
    func applicationShouldTerminate(_ sender:NSApplication)->NSApplication.TerminateReply {
        if model.isPreview { return .terminateNow }
        let a=NSAlert();a.messageText="退出Watcher";a.informativeText="保留系统过滤器会停止放行；停用后则不再提供拦截。";a.addButton(withTitle:"取消");a.addButton(withTitle:"保持阻断并退出");a.addButton(withTitle:"停用保护并退出")
        let choice=a.runModal();if choice == .alertFirstButtonReturn { return .terminateCancel }
        if choice == .alertSecondButtonReturn { model.stop();return .terminateNow }
        model.disable { ok in sender.reply(toApplicationShouldTerminate:ok) };return .terminateLater
    }
    func applicationWillTerminate(_ notification:Notification) { model.stop() }
}
if CommandLine.arguments.contains("--self-test") { runGuardTests();exit(0) }
let app=NSApplication.shared
#if CCW_PREVIEW
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

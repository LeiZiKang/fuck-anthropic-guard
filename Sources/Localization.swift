import Foundation

enum AppLanguage: String {
    case chinese = "zh-Hans"
    case english = "en"

    static func resolve(saved: String?, preferred: [String]) -> AppLanguage {
        if let saved, let language = AppLanguage(rawValue: saved) { return language }
        return preferred.first?.lowercased().hasPrefix("zh") == true ? .chinese : .english
    }
}

enum L10n {
    private static let lock = NSLock()
    #if CCW_PREVIEW || CCW_RELAY
    private static var selected = AppLanguage.resolve(saved: nil, preferred: Locale.preferredLanguages)
    #else
    private static var selected = AppLanguage.resolve(saved: CommandLine.arguments.contains("--self-test") ? nil : UserDefaults.standard.string(forKey: "AppLanguage"),
                                                      preferred: Locale.preferredLanguages)
    #endif
    static var language: AppLanguage {
        get { lock.lock(); defer { lock.unlock() }; return selected }
        set {
            lock.lock(); selected = newValue; lock.unlock()
            #if !CCW_PREVIEW && !CCW_RELAY
            if !CommandLine.arguments.contains("--self-test") { UserDefaults.standard.set(newValue.rawValue, forKey: "AppLanguage") }
            #endif
        }
    }
    static func text(_ chinese: String, _ english: String) -> String {
        language == .chinese ? chinese : english
    }
}

/// Store both variants so an existing warning changes language immediately.
struct LocalizedMessage {
    let chinese: String
    let english: String
    init(_ chinese: String, _ english: String) { self.chinese = chinese; self.english = english }
    var value: String { L10n.text(chinese, english) }
}

final class RefreshGate {
    private let lock = NSLock()
    private var pending = false
    func begin() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !pending else { return false }
        pending = true
        return true
    }
    func finish() { lock.lock(); pending = false; lock.unlock() }
}

/// Complete bilingual application copy. Values are resolved at display time.
enum GuardString: CaseIterable {
 case sampleDesktop,sampleCLI,sampleIPv6,previewState,previewDetail,sampleAllowed,sampleDisabled,sampleBlocked,notifyUnknown,notifyAllowed,notifyDenied,notifyTitle,notifyBody,notifyFailed,ipv6Reading,readingState,disabled,unknownEnforcement,blocked,allowed,awaitingBlock,ipv6Unreadable,physicalNetwork,ipv6Unconfigured,off,noServices,disableBeforeConfig,surgeReadFailed,contractFailed,changedNotSaved,configureFirst,previewTitle,heading,subtitle,processHeading,refresh,quitListed,ipv6Help,guardHeading,guardHelp,configure,enable,hold,disable,manual,closeHelp,open,quitMenu,edit,copy,paste,selectAll,window,closeWindow,noProcesses,cancel,proceed,quitTitle,quitHelp,enableTitle,enableHelp,disableTitle,disableHelp,disableFailed,settingsTitle,settingsHelp,port,exitIP,policy,save,configIncomplete,saved,quitApp,quitAppHelp,quitKeep,quitDisable,language,unknown,automatic,manualMode,linkLocal
 var message: LocalizedMessage {
  switch self {
  case .sampleDesktop: return LocalizedMessage("Claude Desktop（示例）","Claude Desktop (sample)")
  case .sampleCLI: return LocalizedMessage("Claude Code（示例）","Claude Code (sample)")
  case .sampleIPv6: return LocalizedMessage("Wi-Fi：已关闭（示例）\n以太网：自动（示例）","Wi-Fi: Off (sample)\nEthernet: Automatic (sample)")
  case .previewState: return LocalizedMessage("离线预览 · 不操作真实进程或网络","Offline preview · No real process or network operations")
  case .previewDetail: return LocalizedMessage("这是可审阅的模拟界面。Preview不包含监测后端、系统授权、Surge CLI或联网探针。","This preview uses sample data only. It contains no live monitoring, system approval, Surge CLI, or network probes.")
  case .sampleAllowed: return LocalizedMessage("示例：已验证Surge专用入口","Sample: Dedicated Surge endpoint verified")
  case .sampleDisabled: return LocalizedMessage("示例：保护未启用","Sample: Protection disabled")
  case .sampleBlocked: return LocalizedMessage("示例：验证失效，保持阻断","Sample: Verification failed; keep blocking")
  case .notifyUnknown: return LocalizedMessage("系统通知：尚未授权","Notifications: Permission not yet granted")
  case .notifyAllowed: return LocalizedMessage("系统通知：已授权（受专注模式和系统设置影响）","Notifications: Allowed (subject to Focus and system settings)")
  case .notifyDenied: return LocalizedMessage("系统通知：不可用，请在系统设置中允许通知；请查看App状态","Notifications: Unavailable. Allow them in System Settings and check the app status.")
  case .notifyTitle: return LocalizedMessage("Claude连接保护需要注意","Claude connection protection needs attention")
  case .notifyBody: return LocalizedMessage("无法确认安全路径，Guard已撤销放行许可。请打开App查看过滤器状态与原因；执行未确认时不能视为已阻断。","The safe route could not be confirmed. Guard has withdrawn permission to connect. Open the app for filter status and details; unconfirmed enforcement does not mean traffic is blocked.")
  case .notifyFailed: return LocalizedMessage("系统通知发送失败，请查看App状态","Notification delivery failed. Check the app status.")
  case .ipv6Reading: return LocalizedMessage("IPv6：读取中","IPv6: Reading settings")
  case .readingState: return LocalizedMessage("正在读取配置；尚未确认保护","Reading configuration; protection is not confirmed")
  case .disabled: return LocalizedMessage("系统保护未启用","System protection is not enabled")
  case .unknownEnforcement: return LocalizedMessage("系统过滤执行未确认","Filter enforcement is unconfirmed")
  case .blocked: return LocalizedMessage("已识别的Claude连接：阻断中","Recognized Claude connections: Blocking")
  case .allowed: return LocalizedMessage("已验证Surge专用路径 · 允许已识别连接","Dedicated Surge route verified · Recognized connections allowed")
  case .awaitingBlock: return LocalizedMessage("放行条件失效 · 等待阻断执行确认","Allow conditions failed · Waiting for blocking confirmation")
  case .ipv6Unreadable: return LocalizedMessage("IPv6：无法读取","IPv6: Could not read settings")
  case .physicalNetwork: return LocalizedMessage("物理网络","Physical network")
  case .ipv6Unconfigured: return LocalizedMessage("：未配置IPv6",": IPv6 not configured")
  case .off: return LocalizedMessage("已关闭","Off")
  case .noServices: return LocalizedMessage("未找到Wi-Fi/以太网服务","No Wi-Fi or Ethernet services found")
  case .disableBeforeConfig: return LocalizedMessage("请先停用本App的保护，或等待配置状态确认。","Disable protection in this app first, or wait for configuration status to be confirmed.")
  case .surgeReadFailed: return LocalizedMessage("无法只读验证Surge；设置未保存。","Could not verify Surge in read-only mode. Settings were not saved.")
  case .contractFailed: return LocalizedMessage("Surge配置尚不满足专用入口、置顶规则和单节点要求。请查看使用说明；本App不会替你修改Surge。","Surge does not meet the dedicated endpoint, first-rule, and single-node requirements. Read the user guide; this app will not change Surge for you.")
  case .changedNotSaved: return LocalizedMessage("状态已变化，未保存。","The state changed. Settings were not saved.")
  case .configureFirst: return LocalizedMessage("请先配置并验证Surge专用入口","Configure and verify the dedicated Surge endpoint first")
  case .previewTitle: return LocalizedMessage("fuck-anthropic guard · 离线预览","fuck-anthropic guard · Offline Preview")
  case .heading: return LocalizedMessage("Claude 进程与连接保护","Claude processes and connection protection")
  case .subtitle: return LocalizedMessage("联网由Surge负责。Guard不提供代理/VPN，不建立SSH，不读取VPS私钥。","Surge handles network traffic. Guard provides no proxy, VPN, or SSH tunnel and does not read VPS private keys.")
  case .processHeading: return LocalizedMessage("1 · 进程与IPv6状态","1 · Processes and IPv6")
  case .refresh: return LocalizedMessage("刷新","Refresh")
  case .quitListed: return LocalizedMessage("退出所列Claude进程…","Quit listed Claude processes…")
  case .ipv6Help: return LocalizedMessage("只显示物理网络服务的IPv6设置；不改设置、不等于测试IPv6外网连通。","Displays IPv6 settings for physical network services only. It does not change settings or test IPv6 internet connectivity.")
  case .guardHeading: return LocalizedMessage("2 · Surge路径拦截","2 · Surge connection guard")
  case .guardHelp: return LocalizedMessage("只允许已识别客户端连接已验证的Surge专用入口。识别不明、开机首包及过滤器自身故障仍有覆盖边界。","Only recognized clients using the verified Surge endpoint may connect. Unknown identities, early boot traffic, and filter failures remain outside verified coverage.")
  case .configure: return LocalizedMessage("配置Surge检查…","Configure Surge checks…")
  case .enable: return LocalizedMessage("启用保护…","Enable protection…")
  case .hold: return LocalizedMessage("保持阻断","Keep blocking")
  case .disable: return LocalizedMessage("停用保护…","Disable protection…")
  case .manual: return LocalizedMessage("使用说明","User guide")
  case .closeHelp: return LocalizedMessage("关闭窗口不会退出App。退出App并保留过滤器时，已识别连接会转为阻断。","Closing the window keeps the app running. Quitting with the filter retained withdraws permission for recognized connections.")
  case .open: return LocalizedMessage("打开Guard","Open Guard")
  case .quitMenu: return LocalizedMessage("退出Guard…","Quit Guard…")
  case .edit: return LocalizedMessage("编辑","Edit")
  case .copy: return LocalizedMessage("复制","Copy")
  case .paste: return LocalizedMessage("粘贴","Paste")
  case .selectAll: return LocalizedMessage("全选","Select All")
  case .window: return LocalizedMessage("窗口","Window")
  case .closeWindow: return LocalizedMessage("关闭窗口","Close Window")
  case .noProcesses: return LocalizedMessage("未发现可可靠识别的Claude进程。","No reliably identified Claude processes found.")
  case .cancel: return LocalizedMessage("取消","Cancel")
  case .proceed: return LocalizedMessage("继续","Continue")
  case .quitTitle: return LocalizedMessage("退出所列Claude进程？","Quit the listed Claude processes?")
  case .quitHelp: return LocalizedMessage("仅退出打开本确认框前列出的进程。会重新核对每个PID的用户、启动时间和路径，再发送SIGTERM；不操作Surge，不自动强杀。请先保存工作。","Only processes listed before this dialog opened will be targeted. Each PID, user, start time, and path is rechecked before SIGTERM. Surge is excluded; there is no automatic force quit. Save your work first.")
  case .enableTitle: return LocalizedMessage("启用系统级连接保护？","Enable system connection protection?")
  case .enableHelp: return LocalizedMessage("需要macOS授权。验证不通过时已识别Claude连接将被阻断。验证会通过Surge向api.ipify.org发送不含账号的出口探针；不会修改Surge配置。","macOS approval is required. Recognized Claude connections will be blocked when verification fails. Checks send an account-free exit probe through Surge to api.ipify.org; Surge settings are not changed.")
  case .disableTitle: return LocalizedMessage("停用系统保护？","Disable system protection?")
  case .disableHelp: return LocalizedMessage("停用后Guard不再阻止Claude直连。","After disabling, Guard will no longer prevent Claude from connecting directly.")
  case .disableFailed: return LocalizedMessage("未确认停用，请检查系统设置。","Disabling is unconfirmed. Check System Settings.")
  case .settingsTitle: return LocalizedMessage("验证Surge专用入口","Verify the dedicated Surge endpoint")
  case .settingsHelp: return LocalizedMessage("这不是Guard代理。请先阅读使用说明，并手动在Surge添加专用入口及置顶IN-PORT规则；共享6152/6153不支持，原有Xcode直连规则保持不变。保存会只读查询Surge并记录配置摘要，不保存代理密码。","This is not a Guard proxy. Read the guide, then manually add a dedicated listener and first IN-PORT rule in Surge. Shared ports 6152/6153 are unsupported. Keep existing Xcode direct rules. Saving reads Surge and records a configuration digest, not proxy passwords.")
  case .port: return LocalizedMessage("Surge专用HTTP端口","Dedicated Surge HTTP port")
  case .exitIP: return LocalizedMessage("预期VPS出口IP","Expected VPS exit IP")
  case .policy: return LocalizedMessage("单节点策略组","Single-node policy group")
  case .save: return LocalizedMessage("验证并保存","Verify and save")
  case .configIncomplete: return LocalizedMessage("配置不完整，或使用了共享代理端口。","Configuration is incomplete or uses a shared proxy port.")
  case .saved: return LocalizedMessage("配置已保存；系统保护尚需明确启用。","Configuration saved. System protection still needs to be explicitly enabled.")
  case .quitApp: return LocalizedMessage("退出Guard","Quit Guard")
  case .quitAppHelp: return LocalizedMessage("保留系统过滤器会停止放行；停用后则不再提供拦截。","Keeping the system filter withdraws connection permission. Disabling it removes blocking protection.")
  case .quitKeep: return LocalizedMessage("保持阻断并退出","Keep blocking and quit")
  case .quitDisable: return LocalizedMessage("停用保护并退出","Disable protection and quit")
  case .language: return LocalizedMessage("语言","Language")
  case .unknown: return LocalizedMessage("未知","Unknown")
  case .automatic: return LocalizedMessage("自动","Automatic")
  case .manualMode: return LocalizedMessage("手动","Manual")
  case .linkLocal: return LocalizedMessage("仅本地链路","Link-local only")
  }
 }
 var text:String { message.value }
}

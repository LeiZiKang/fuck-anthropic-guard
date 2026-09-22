# PRD — Claude Connection Watcher 0.4.0

## 产品目标

给使用 Surge 的 macOS 用户提供两个清晰能力：识别并管理 Claude 进程、查看 IPv6 设置；在可验证范围内阻止 Claude 绕过指定 Surge 路径。Surge 始终负责数据转发，Watcher 不做代理或VPN。

## 用户故事

- 我能看到已识别的 Desktop/原生CLI/相关后代，一次确认后退出它们；其他应用尤其是Surge不受退出操作影响。
- 我能看到物理网络服务的IPv6设置，不需要App替我修改网络。
- 我明确开启保护后，只允许已识别客户端使用验证过的Surge专用入口；过期或失联时拒绝连接。
- 我能看清未启用、执行未知、阻断中和短期检查通过，不把未知显示成安全。

## 范围

| 功能 | 要求 |
|---|---|
| 进程识别 | 校验官方签名或稳定的同用户后代链，不以名称代替身份 |
| 退出 | 用户确认，信号前核对PID/UID/启动时间/路径；默认SIGTERM，无自动强杀 |
| IPv6 | 按当前Wi-Fi/以太网服务只读显示，未知明确标记 |
| 路径保护 | 系统过滤器约束已识别客户端的TCP代理入口；验证Surge签名、端口、有效规则、短时配置证据和出口 |
| 生命周期 | 过期、控制失联或Surge进程变化时撤销许可；已有跟踪连接可撤销 |
| 配置 | 专用Surge端口，不改变系统代理/Surge/路由；保存非秘密检查条件与摘要 |
| 分发 | 默认离线Preview，生产target只Build；源码公开，正式过滤需签名和macOS授权 |

## 不做

代理/VPN/SSH、读取VPS私钥、自动改Surge、自动故障切换、账号凭据清理、IPv6开关、后台代操作真实Claude、账号风控保证。

## 关键约束

共享6152可能合法DIRECT，因此严格模式要求Surge专用入口及首条IN-PORT固定单节点策略。客户端需要显式使用该入口。健康探针通过Surge访问api.ipify.org，无账号数据；不设置DIRECT回退。

短时快照不等于逐包出口证明。未知进程、过滤器故障、重启首包与物理网络变化仍需专项实测。详细限制必须在UI/说明书/发布说明保持一致。

## 验收

- 离线测试覆盖直连/错误端口/UDP拒绝、Surge豁免、同用户与未知边界、许可过期/未来时间/nonce和身份变化。
- Preview与生产/过滤器均能独立构建；Preview不链接生产后端。
- 使用说明书为离线HTML，随App及源码提供。
- 当前用户网络保持不变；真实系统启用和故障注入另行安排。
- 功能分支发布前独立审查代码、可达历史与精确产物；合并等待维护者验收。


## 后台提醒

启用保护时请求 macOS 通知权限。自动监测期间进入不安全或执行未确认状态会发出一次系统提醒，持续失败不会每次轮询重复提醒；恢复后再次失效会重新提醒。手动保持阻断不触发故障提醒。点击通知可打开 App。

未授权、专注模式和 macOS 通知设置可能阻止横幅出现，App 内仍显示状态。通知表示放行许可被撤销，不把过滤执行未知说成已经阻断。离线验证覆盖提醒去重/恢复逻辑；系统通知投递与真实过滤仍需实机验收。


Bilingual update: Simplified Chinese and English UI, confirmations, status text and future notifications; instant in-app switching preserves monitoring state. Production remembers the choice; Preview is memory-only. Both offline HTML guides are bundled. System permission dialogs follow macOS language. README screenshots use the running offline Preview with sample data, not live-filter evidence.

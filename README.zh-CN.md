<div align="center">
  <img src="Resources/AppIcon.png" width="80" alt="fuck-anthropic guard 图标">
  <h1>fuck-anthropic guard</h1>
  <p><strong>看清 Claude 在运行什么，也看住它的网络连接。</strong></p>
  <p>配合 Surge 使用的本地 macOS 工具：进程管理、连接检查与异常提醒。</p>
  <p><a href="README.md">English</a> · <strong>简体中文</strong></p>
  <p><a href="docs/UserGuide.md">使用说明</a> · <a href="docs/FEATURE-STATUS.zh-CN.md">验证状态</a> · <a href="SECURITY.zh-CN.md">安全边界</a> · <a href="CONTRIBUTING.zh-CN.md">参与贡献</a></p>
  <p><code>macOS 14+</code> &nbsp; <code>Apple Silicon + Intel</code> &nbsp; <code>MIT</code></p>
</div>

> **实验版本 · 仅发布源码。** 本候选暂无正式签名安装包，真实故障场景仍待验收；不保证零 IP 泄漏或账号安全。

<p align="center">
  <a href="docs/images/preview-zh.png"><img src="docs/images/preview-zh.png" width="640" alt="中文主界面：可识别进程、IPv6 状态与 Surge 保护操作"></a>
  <br><sub>实际运行的离线 Preview · 示例数据 · 不是真实过滤证据</sub>
</p>

## 一个窗口，三件事

| 看清进程 | 检查连接 | 关代理前先退出 |
|---|---|---|
| 查看可识别的 Claude Desktop、原生 CLI、可追溯后代，以及只读 IPv6 状态。 | 主动启用过滤后，将可识别客户端限制到已验证的 Surge 入口；检查失败或许可过期时撤销放行。 | 一次确认退出所列进程。确认它们真正退出后，再关闭代理。 |

流量由 Surge 转发。Guard 不提供 VPN 或 SSH 隧道，不读取 VPS 私钥，也不修改网络设置；目标是在代理或网络变化时降低意外直连风险。

<details>
<summary><strong>查看退出确认与阻断状态示例</strong></summary>

退出操作会先冻结待处理的进程集合，再请求确认。Preview 只操作示例进程。

<p align="center"><img src="docs/images/quit-confirmation-zh.png" width="280" alt="退出所列示例进程前的中文确认框"></p>

下方阻断状态是模拟展示；切换语言会保留该状态。

<p align="center"><img src="docs/images/blocked-preview-zh.png" width="640" alt="中文 Preview 中的模拟阻断状态"></p>

</details>

## 先体验离线 Preview

需要 Xcode 或兼容的 Command Line Tools，以及 Python 3。Preview 不操作真实进程、不发送探针，也不启用过滤器。

```bash
git clone --branch codex/feature-surge-guard-public https://github.com/LeiZiKang/fuck-anthropic-guard.git
cd fuck-anthropic-guard
bash scripts/build.sh
open "dist/guard/fuck-anthropic guard Preview.app"
```

窗口内可选择 **简体中文 / English**。正式版记住选择，Preview 仅在内存保存。

## 启用真实保护前

当前版本需要 **Surge 专用监听入口**、固定到单个受支持 Hysteria2 节点的首条 `IN-PORT` 规则、有效签名和 macOS 过滤授权。共享代理端口或普通 Dock 启动不一定采用该路径，请先阅读[配置说明](docs/UserGuide.md)。

未知进程、过滤器崩溃、开机首包和网络切换存在覆盖边界；变化被发现前有时间窗口，不能保证即时阻断。详见[验证状态](docs/FEATURE-STATUS.zh-CN.md)与[安全模型](SECURITY.zh-CN.md)。

<details>
<summary><strong>构建主程序与过滤器 · 贡献者说明</strong></summary>

```bash
bash scripts/test.sh
CCW_BUILD_MODE=host bash scripts/build.sh
```

这些命令只构建，不安装。ad-hoc 签名不代表保护生效。`ClaudeConnectionWatcher.xcodeproj` 默认运行 **01 Preview (Safe)**，生产方案仅用于构建；设置 `CCW_ARCHITECTURES='arm64 x86_64'` 可构建双架构版本。

进一步阅读[贡献指南](CONTRIBUTING.zh-CN.md)、[设计与范围](docs/PRD.md)和[发布说明](docs/RELEASE-NOTES.zh-CN.md)。源码也包含[离线 HTML 手册](docs/UserGuide.html)，下载后可用浏览器阅读；GitHub 会将 HTML 文件显示为源代码。

</details>

---

进程信息留在本机。经同意的出口检查通过 Surge 访问 `api.ipify.org`，不携带 Claude 凭据；无遥测，不自动回退直连。[MIT 许可证](LICENSE)。

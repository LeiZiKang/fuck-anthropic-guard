# Guard 待办

## 发布流程 Skill 复用（暂缓）

- [ ] 评估并复用现成发布 skill，按需补充 Guard 项目适配。

记录：2026-09-29 · author: codex。用户要求先记入待办，暂不实施、安装或发布 skill。

候选：
- [release-codexbar](https://github.com/steipete/CodexBar/blob/main/.agents/skills/release-codexbar/SKILL.md)：覆盖公证、GitHub Release、Homebrew 与本机更新验证；需调整 CodexBar 专属路径、凭据和 Sparkle 流程。
- [release-mac-app](https://github.com/steipete/agent-scripts/blob/main/skills/release-mac-app/SKILL.md)：通用 macOS 发布流程，但依赖 Sparkle 配置；Guard 当前未使用 Sparkle。

后续范围：优先复用上游流程，保留现有发布脚本，补充仓库/cask 映射、独立审查、最终 ZIP 哈希核验，以及过滤扩展升级和保护恢复验收。实施前重新核对上游内容、许可证和依赖，不照搬凭据或进程终止操作。

验收：分别确认 GitHub、Homebrew 和获准的本机更新结果；保留备份及现有 Surge/网络保护。此待办不代表未来上传或安装的常设授权。

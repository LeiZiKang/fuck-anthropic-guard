# 发布说明 — 0.4.0 beta / build 12.0

[English](RELEASE-NOTES.md) | **简体中文**

## 功能

- 可识别的 Claude 进程管理及只读 IPv6 设置。
- 配合单独配置的 Surge 入口提供实验性系统过滤，以及去重的 macOS 安全提醒。
- 即时切换简体中文／英文，双语手册与 README 语言导航。
- 原生 Xcode 目标、Dock／菜单栏界面和独立离线 Preview。
- 新名称 **fuck-anthropic guard** 与新图标；内部 bundle／签名标识保持不变。

## 使用前须知

保护需要主动启用，并配置说明书要求的 Surge 专用入口、有效签名和 macOS 授权。App 不提供代理／SSH 服务，不读取 VPS 私钥、不清理凭据，也不自动修改 Surge。

本次仅公开实验性源码，不是正式签名安装包或自动更新。真实代理中断、重启、过滤器崩溃和客户端覆盖验收仍待完成。详见[验证状态](FEATURE-STATUS.zh-CN.md)和[安全模型](../SECURITY.zh-CN.md)，不保证零 IP 泄漏或账号安全。

# 贡献指南

[English](CONTRIBUTING.md) | **简体中文**

请将产品范围保持在进程管理、只读 IPv6 状态和 Surge 配套过滤。不要增加代理转发、SSH／VPS 凭据、自动修改网络配置或账号清理。开发界面时使用默认的离线 Preview。

运行 `bash scripts/test.sh`，并以 `CCW_BUILD_MODE=host bash scripts/build.sh` 编译主程序及过滤器。自动测试不得启用生产过滤器、修改代理或终止真实应用。集成测试需要隔离且明确获准的 macOS 环境；说明尚未验证的部分，不宣称零泄漏。

使用功能分支和经审阅的 PR。公开分发前，冻结产物及其可达历史需要独立的发布／安全审查。

# 0.4.4 正式版 / build 13.0

将现有Developer ID签名、Apple公证的Universal 2 build13.0发布为正式版。ZIP内容与v0.4.4-beta.1完全相同，仅发布通道、标签及下载文件名变化，没有重新编译或修改运行代码。

## 主要功能

- 可查看进程、目标、允许/拒绝及原因的连接记录。
- 深浅色界面、配置输入校验与共用菜单栏状态面板。
- 已识别Claude客户端经验证的Surge专用TCP入口连接；Surge仍独立管理。
- GitHub与Homebrew使用同一份校验过的安装包。

## 验证与边界

现有版本通过271项Preview/273项主程序离线检查（覆盖重叠）、Universal2编译、Developer ID验签、Apple公证和Gatekeeper检查。build13.0已通过Homebrew安装到本机，过滤扩展启用、界面保护就绪；签名CLI及子进程本机6154允许、错误端口拒绝实测通过。Intel仅编译验证。

维护者明确选择暂缓物理断网/恢复、重启/唤醒、过滤器崩溃、开机早期、未知归属以及完整原生菜单栏交互验收，直接正式发布。这些项仍未验证，不因正式版标记而成为通过。Guard不是VPN，不保证账号安全。

## 安装

下载本版ZIP，或在tap更新后通过Homebrew安装`leizikang/tap/fuck-anthropic-guard`，要求macOS14+。已安装build13.0的用户运行的是相同二进制，此次通道变更无需重启App或过滤器。其他版本升级请遵循使用说明，替换后确认保护恢复。

SHA-256：`2e2e00db1c591100a22bb3a716cd070cc493b110bd89b6900207abb869c9049d`

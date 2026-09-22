# 0.4.0 / build 12.0 — validation status

## Implemented

- Signed-client/verified descendant process discovery and confirmed termination with fresh identity checks.
- Read-only physical-service IPv6 display.
- Explicit Surge setup, bounded policy/exit checks, provider boot/session/challenge validation and ordered updates.
- System-filter endpoint constraints, expiry and tracked-flow revocation; no SSH/relay target or listener.
- Native Xcode Preview / Watcher / Filter targets, Dock window and offline HTML manual.

## Validation

Build/test records will be bound to the frozen source and archive hashes in the
release review. Pure tests and compilation do not mean the production filter has
been installed or tested against real clients.

## Not validated in this release workflow

Production system approval/activation, every live client wrapper or descendant,
physical reboot first packets, provider crash recovery, physical network loss,
and all IPv6 transitions. Existing user proxies and clients are not changed during
this workflow. Review the manual and SECURITY.md before enabling experimental filtering.


## 后台提醒

启用保护时请求 macOS 通知权限。自动监测期间进入不安全或执行未确认状态会发出一次系统提醒，持续失败不会每次轮询重复提醒；恢复后再次失效会重新提醒。手动保持阻断不触发故障提醒。点击通知可打开 App。

未授权、专注模式和 macOS 通知设置可能阻止横幅出现，App 内仍显示状态。通知表示放行许可被撤销，不把过滤执行未知说成已经阻断。离线验证覆盖提醒去重/恢复逻辑；系统通知投递与真实过滤仍需实机验收。

## Local verification, 2026-09-22

51 offline checks passed, including immediate unsafe presentation and notification episode deduplication. Native Xcode host/filter build succeeded before the final UI corrections; final frozen build results are recorded in the independent release review. No production app was installed or activated.

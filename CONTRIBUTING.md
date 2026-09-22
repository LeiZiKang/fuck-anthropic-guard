# Contributing

**English** | [简体中文](CONTRIBUTING.zh-CN.md)

Keep the product scoped to process management/read-only IPv6 and Surge filtering.
Do not add proxy forwarding, SSH/VPS credentials, automatic configuration writes,
or account cleanup. Use the default offline Preview to develop the UI.

Run `bash scripts/test.sh` and compile `CCW_BUILD_MODE=host bash scripts/build.sh`.
Do not activate a production filter, alter proxies or terminate real applications
in automated tests. Integration tests require an isolated, explicitly approved
macOS environment. Describe remaining uncertainty rather than claiming zero leaks.

Use a feature branch and a reviewed PR. Frozen release artifacts and reachable
history require a separate release/security review before public distribution.

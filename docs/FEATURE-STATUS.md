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

# Development and release contract

This app has two purposes: process management/read-only IPv6 visibility, and
connection filtering for recognized Claude clients using a separately managed Surge.
It must not become a proxy, SSH tunnel, credential cleaner, or network configurator.

- Default builds and Xcode Run use an isolated offline Preview.
- Do not alter system proxies, Surge, routes, DNS or live filters during tests.
- Do not terminate real user applications during development tests.
- Maintain README, HTML UserGuide, PRD and feature/test status when behavior changes.
- Distinguish implemented, built, tested, signed, installed and live-validated.
- Before public push/release, a separate agent/reviewer must audit the frozen
  source, reachable history, exact downloadable artifacts and release text.
- Never publish private keys, API tokens, cookies, private profiles/configuration,
  credential archives or personal machine paths. Developer ID public certificates
  and required public Team/Bundle identifiers are not private keys.
- Publish with scripts/publish-release.sh; its audit gate is a workflow check,
  not proof of an exhaustive security review.
- No account-safety, zero-IP-leak or fail-closed-under-all-OS-failures claims.
- Keep changes on the feature branch until the owner accepts the review.

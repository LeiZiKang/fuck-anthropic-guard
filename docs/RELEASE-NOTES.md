# Release notes — 0.4.0 beta / build 12.0

**English** | [简体中文](RELEASE-NOTES.zh-CN.md)

## Features

- Recognized Claude process management and read-only IPv6 settings.
- Experimental system filtering through a separately configured Surge endpoint, with deduplicated macOS safety notifications.
- Instant Simplified Chinese/English UI switching, bilingual guides and README language navigation.
- Native Xcode targets, Dock/menu-bar UI and an isolated offline Preview.
- New name: **fuck-anthropic guard**, with a new icon. Internal bundle/signing identifiers remain stable.

## Before use

Protection is opt-in and requires the documented dedicated Surge listener, valid signing and macOS approval. The app does not provide a proxy/SSH service, read VPS keys, clean credentials or automatically edit Surge.

This beta includes a Developer ID signed, notarized Universal 2 app and a new Homebrew cask. Installation does not activate the filter or update the old 0.2.2 cask automatically. Live proxy-loss, boot, provider-crash and client coverage acceptance remains pending. See [validation status](FEATURE-STATUS.md) and [security model](../SECURITY.md); no zero-IP-leak or account-safety guarantee is made.

Install with `brew install --cask leizikang/tap/fuck-anthropic-guard`, or download this release ZIP. Disable protection, confirm disablement and quit before migration, upgrade or uninstall. Old and new apps share bundle identifiers; do not run both.

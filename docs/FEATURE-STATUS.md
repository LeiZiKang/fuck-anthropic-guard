# Validation status — 0.4.0 / build 12.0

**English** | [简体中文](FEATURE-STATUS.zh-CN.md)

## Implemented

Recognized-process discovery and confirmed termination, read-only IPv6, opt-in Surge path checks and system filtering, safety notifications, bilingual UI/guides, native Xcode targets, Dock/menu-bar entry and isolated Preview.

## Verified locally

- 222 host offline assertions and 220 Preview assertions passed. They share coverage and must not be added together.
- Intel/Apple Silicon host and filter builds, strict ad-hoc signature checks, and a native Xcode build passed.
- The running offline Preview was checked in both languages: language switching retained the sample blocking state, cancellation retained sample processes, configuration fields were visible, and the new icon appeared in confirmation dialogs.
- README screenshots use sample data from that Preview. They are not live-filter evidence.
- Independent source-publication review covered frozen source/history, images and the exact local archive. It does not certify production safety.

## Still unverified

Production approval/activation, real client traffic and every wrapper/descendant, notification delivery, reboot first packets, provider-crash recovery, physical network loss and all IPv6 transitions.

## Distribution status

A Developer ID signed and Apple-notarized experimental beta is packaged for distribution. Secure timestamps, stapled ticket, Gatekeeper assessment and signed-host offline checks passed. Homebrew installation is not live filtering acceptance. No production filter was installed or activated during this workflow. Existing user proxies and clients were not changed. Read the [security model](../SECURITY.md) and [guide](UserGuide.en.md) before planning isolated live acceptance.

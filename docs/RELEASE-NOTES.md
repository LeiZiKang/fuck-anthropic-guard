# 0.4.4 beta / build 13.0

**English** | [简体中文](RELEASE-NOTES.zh-CN.md)

This release adds an inspectable connection journal and a redesigned dark/light interface while retaining the scoped Surge companion model.

- Latest 80 recognized-client decisions in memory, with process/PID, endpoint, protocol and recorded cause; search, sorting, details and copy.
- Clear confirmation before manual blocking, actual IPC recheck, state-aware settings and inline configuration validation that preserves invalid input.
- Menu panel with padding, status-specific symbols, last-status time and the real recheck action. Four Xcode Canvas previews share the production AppKit panel.
- Organized Xcode navigator and a safe default Preview scheme. Canvas-only macros are excluded from the standalone command-line build.
- Corrected native Claude launcher signature verification and macOS Desktop launching.

## Package and upgrade

The ZIP contains a Developer ID signed, Apple-notarized Universal 2 app for macOS 14+. Host and filter use build 13.0; this differs from the earlier local-only12.2 packages. Intel is compile-verified, not hardware-tested. The Homebrew tap is unchanged; use this versioned ZIP for 0.4.4.

Save work and quit Claude clients first. Keep Surge running. Quit Guard with its filter retained, replace the app, reopen it and explicitly resume/enable checks; complete any macOS extension approval. Keep clients closed until protection is verified. If the system asks for a restart, treat protection as unconfirmed until checked after restart. Do not run old and new app copies together. See the [guide](UserGuide.en.md).

## Validation and limits

271 Preview and 273 host offline checks passed (shared coverage, not additive), plus release-gate tests and dual-architecture compilation. Local development builds passed dedicated-port allow/deny tests. Xcode Canvas checked four menu states in English/Chinese; that does not prove physical menu placement/click behavior.

The exact build 13.0 distribution is not a new live reboot/wake/provider-crash acceptance result. Unknown process attribution remains a coverage gap. Guard is not a VPN and does not guarantee zero IP exposure or freedom from account restrictions. See [validation status](FEATURE-STATUS.md) and [security model](../SECURITY.md).

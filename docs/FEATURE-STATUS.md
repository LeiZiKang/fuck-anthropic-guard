# Feature and validation status

## Local 0.4.2 / build 12.2

Implemented: scoped Claude connection protection, process inventory, read-only IPv6,
Surge route checks, bounded in-memory journal and safety notifications. The dark
bilingual UI now adds confirmed blocking, actual IPC recheck, state-aware read-only
configuration, recorded trigger details, search/sort/details/copy, accessible
summary buttons, stronger text contrast and persistent appearance.

Validation: Xcode MCP Preview and Watcher Build Only builds passed; 249 Preview
and 251 host offline checks passed (shared coverage, not additive). Native preview
checks passed for block/cancel, endpoint search/clear, sorting and event details.
Default1040x820 and small900x740 renders inspected; smaller content scrolls.

The exact Xcode-built candidate was Apple notarized, stapled, verified by Gatekeeper and installed locally. Filter12.2 is activated enabled; UI ready, read-only endpoint and disabled redundant enable verified. Recheck updates the real filter status. Local-only signed CLI child acceptance again allowed6154 and denied8776 with matching journal entries. Surge profile unchanged. No public0.4.2 release or remote push.
Live fault recovery, OS restart/wake and unknown-attribution coverage remain
separate acceptance gaps. Diagnostics do not change authorization predicates.

## Project workflow

Xcode navigator groups and existing source paths/target memberships are organized.
Default scheme remains 01 Preview (Safe); the host scheme is build-only. Prefer
Xcode MCP for incremental build/diagnostics; shell scripts remain packaging/CI
fallbacks. See [branch workflow](BRANCHES.md).

## 0.4.3 host-only installation
Configuration validation now keeps invalid fields open with specific inline errors. Invalid port/IP/policy and corrected-save paths passed in native Preview; 271 Preview / 273 host offline checks and both Xcode MCP builds passed. Apple notarization, stapling and Gatekeeper passed; installed host0.4.3 with the original filter0.4.2/build12.2 tree preserved byte-for-byte. Live protection ready; Surge unchanged.

## 0.4.4 menu-bar candidate
Same AppKit panel shared by the menu popover and four Xcode Canvas#Preview states. English/Chinese RenderPreview snapshots passed; padding, state symbols, last-status time and recheck wiring updated. Candidate not installed yet; retain the current signed filter. Actual system menu placement/click coverage remains distinct from Canvas snapshots.

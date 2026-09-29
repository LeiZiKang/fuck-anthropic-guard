# Feature and validation status

## Local 0.4.2 / build 12.2 candidate

Implemented: scoped Claude connection protection, process inventory, read-only IPv6,
Surge route checks, bounded in-memory journal and safety notifications. The dark
bilingual UI now adds confirmed blocking, actual IPC recheck, state-aware read-only
configuration, recorded trigger details, search/sort/details/copy, accessible
summary buttons, stronger text contrast and persistent appearance.

Validation: Xcode MCP Preview and Watcher Build Only builds passed; 249 Preview
and 251 host offline checks passed (shared coverage, not additive). Native preview
checks passed for block/cancel, endpoint search/clear, sorting and event details.
Default1040x820 and small900x740 renders inspected; smaller content scrolls.

Candidate is not installed yet. Installed local0.4.1 remains active until the new
signed/notarized package is deployed. No public0.4.2 release or remote push.
Live fault recovery, OS restart/wake and unknown-attribution coverage remain
separate acceptance gaps. Diagnostics do not change authorization predicates.

## Project workflow

Xcode navigator groups and existing source paths/target memberships are organized.
Default scheme remains 01 Preview (Safe); the host scheme is build-only. Prefer
Xcode MCP for incremental build/diagnostics; shell scripts remain packaging/CI
fallbacks. See [branch workflow](BRANCHES.md).

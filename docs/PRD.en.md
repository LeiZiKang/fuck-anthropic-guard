# Product requirements — fuck-anthropic guard

**English** | [简体中文](PRD.md)

## Goal

Give macOS users who already use Surge two clear capabilities: manage recognized Claude processes and view IPv6 settings; restrict recognized clients to a verified Surge path. Surge forwards traffic. Guard provides no proxy or VPN.

## User needs

- See recognized Desktop, native CLI and reliably traced descendants, then confirm quitting the listed processes without targeting Surge.
- Read physical-network IPv6 settings without changing them.
- Explicitly enable protection; allow the verified dedicated Surge path and withdraw permission when checks fail, expire or lose contact.
- Distinguish disabled, unconfirmed, blocking and recently verified states. Unknown must not look safe.
- Switch between Simplified Chinese and English without restarting monitoring or changing protection state.

## Requirements

| Area | Requirement |
|---|---|
| Identity | Official signature or stable same-user ancestry; names alone are not identity. |
| Quit | Freeze targets before confirmation; recheck PID, UID, start time and path before SIGTERM. No automatic force quit. |
| IPv6 | Read-only current Wi-Fi/Ethernet service settings; explicitly show unknown. |
| Filtering | Restrict recognized clients to the configured TCP endpoint; check Surge signature, listener, effective rules, bounded configuration evidence and exit. |
| Lifecycle | Expiry, control loss and Surge identity change revoke permission; tracked flows can be withdrawn. |
| Configuration | A dedicated Surge port; no changes to system proxy, Surge or routes. Persist non-secret conditions and a digest. |
| Notifications | One safety notification per unsafe episode during monitoring; recovery rearms alerts. Manual holds do not trigger failure alarms. |
| Language | Bilingual UI, dialogs, statuses, future notifications and guides. Production saves selection; Preview is memory-only. |
| Distribution | Default offline Preview; production targets build only. A real filter requires valid signing and macOS approval. |

## Out of scope

Proxy/VPN/SSH forwarding, VPS private-key access, automatic Surge changes or fallback, credential cleanup, IPv6 toggles, background operation of real Claude sessions, and account-safety guarantees.

## Constraints and acceptance

Shared port 6152 can legitimately select DIRECT. Strict protection requires a dedicated Surge listener and first IN-PORT rule pinned to one supported Hysteria2 node; the client must use that endpoint explicitly. Consented exit probes reach api.ipify.org through Surge without account data or DIRECT fallback.

A snapshot is not per-packet proof. Unknown processes, provider failures, early boot traffic and physical-network transitions need live validation. The app, guide and release notes must present these limits consistently.

Offline acceptance covers wrong endpoints/direct traffic/UDP, infrastructure exclusions, user and unknown-identity boundaries, expiry, replay and identity change. Preview, host and filter must build independently, and Preview must not link production backends. Use isolated live tests outside important sessions; see [validation status](FEATURE-STATUS.md).

Notification permission, Focus and macOS settings can suppress banners. An alert says permission was withdrawn, not that unknown enforcement is confirmed blocking. Previously delivered notifications keep their original language; system dialogs follow macOS settings.

# fuck-anthropic guard — User guide

**English** | [简体中文](UserGuide.md)

Applies to 0.4.4 stable / build 13.0. Requires macOS 14+. This is an experimental Surge companion, not the older SSH-relay app.

## 1. Scope

Guard recognizes signed Claude Desktop, native Claude Code and reliably traceable same-user descendants. Its optional system filter restricts these clients to a verified local Surge TCP endpoint. Other users, infrastructure proxies and unknown attribution are outside this proven scope.

**Surge forwards the traffic. Guard is not a VPN/proxy/SSH tunnel and does not modify system networking or read VPS keys.**

```text
Claude -> Guard system filter -> dedicated local Surge endpoint -> proxy node -> website
```

## 2. Install and upgrade

Download the versioned notarized Universal 2 ZIP, extract it and put one copy of the app in Applications. Apple Silicon and Intel are compiled; Intel hardware is not live-tested. Installing is separate from enabling protection.

For an upgrade, save work and quit Claude clients first; leave Surge running. Quit Guard with the filter retained, replace the app, open it and explicitly resume/enable checks. Approve the system extension if macOS asks. Do not reopen clients until the UI is ready. If macOS requires reboot, verify protection after reboot before use. Do not run multiple old/new copies with the same bundle identifier.

Legacy SSH-relay migrations need separate planning with clients closed. Do not restart an archived relay or disable protections merely to make a status indicator green. To uninstall, first close protected clients, explicitly disable protection, confirm disablement and quit.

## 3. Prepare the Surge endpoint

A shared proxy may legitimately route unrelated traffic DIRECT. Protection therefore uses a dedicated HTTP listener such as127.0.0.1:6154 and a first `IN-PORT` rule pinned to one supported Hysteria2 node.

Merge this example with your own configuration; do not overwrite it or duplicate groups. Guard does not perform these edits.

```ini
[General]
http-listen = 127.0.0.1:6152, 127.0.0.1:6154

[Proxy Group]
CLAUDE-LOCKED = select, Hysteria2

[Rule]
IN-PORT,6154,CLAUDE-LOCKED
# Must be the first effective rule. Keep other rules below it.
```

Configure the Hysteria2 node in Surge. The dedicated policy must select one node, without DIRECT fallback or nested/script groups. MITM, scripting, rewrites and temporary rules must be disabled/empty. Unsupported or changed configurations do not receive permission. Surge manages TLS configuration; Guard does not bypass redaction of hidden node fields.

## 4. Configure and enable

1. With protection disabled, open **Configure endpoint…** in Settings & diagnostics.
2. Enter a dedicated port, expected egress IPv4/IPv6 addresses and the single-node policy name. Invalid fields show inline errors and remain editable; cancel does not save.
3. Verify and save reads the signed Surge CLI and effective profile, then stores non-secret endpoint/exit/policy conditions and a profile digest. It does not store node passwords.
4. Enable protection and complete macOS approval. Consented account-free probes reach `api.ipify.org` through Surge.
5. Readiness requires recent matching exit evidence, stable rules, verified listener ownership and current filter acknowledgment. While configured or unconfirmed, the endpoint is read-only. Recheck retries the control connection; it does not silently enable protection or rewrite Surge.

## 5. Launch clients

Recognized clients must use the dedicated loopback TCP endpoint. Direct remote connections, other ports and direct UDP/QUIC are denied. Surge's own upstream protocol is excluded from client filtering. A normal Dock launch may use a shared proxy and be blocked.

The optional launcher verifies the native client's signature and sets proxy configuration only for the new process. It does not quit an existing Desktop, start a proxy or change system settings.

```bash
bash scripts/launch-claude-via-surge.sh desktop 6154
bash scripts/launch-claude-via-surge.sh cli 6154
```

If the client is not the recognized signed native executable, do not treat a matching process name or successful launch as proof of coverage. Independently started wrappers and orphaned children may not be attributable.

## 6. Read states and records

| State/action | Meaning |
|---|---|
| Protection ready | Recognized clients may use the recently verified route; not website success or universal coverage. |
| Connections blocked | Permission is withheld. Resume checks explicitly to revalidate. |
| Checking protection | Enforcement or evidence is unconfirmed; do not assume protected. |
| Protection off | System filtering is not enabled. |
| Block Claude connections… | Confirms before withdrawing permission and interrupting tracked connections. |
| Disable protection… | Explicitly removes blocking protection after confirmation. |
| Close window | Keeps the host running; use Dock or menu bar to reopen. |
| Keep blocking and quit | Quits the host while retaining the system filter; permission is withdrawn. |

The journal keeps the latest 80 protected-client metadata events in filter memory, reset when the extension restarts. Search by identity/PID/endpoint, sort columns, select details or copy a record. Allowed means admission checks passed; denied counts also include later revocation, not necessarily unique connections. `127.0.0.1:6154` is the local proxy, not the final website. Available trigger codes explain the observed failure category; absent historical details are not inferred.

Unknown owner is neither a leak count nor a blocked count. It discloses attribution gaps without retaining unrelated apps' connection histories. No payloads, chats, URL paths or credentials are recorded.

## 7. UI, menu bar and notifications

Language changes preserve protection state. Production saves language and appearance; network/process names and macOS dialogs retain their own language. The menu panel shows status, recognized process count, endpoint and last filter acknowledgment; its symbol changes by state. Recheck uses the actual check path; Open window opens the main UI.

The Clients tab lists recognized processes and provides confirmed termination, rechecking identity before SIGTERM. Save work first; there is no automatic force quit. IPv6 settings are read-only and do not prove internet reachability.

Notification permission, Focus and macOS settings can suppress banners. Alerts report loss of safe permission rather than claiming unknown enforcement is confirmed blocked. The app remains the status source.

## 8. Validation limits and development

A periodic profile/exit check is not per-request cryptographic route proof; configuration changes have an observation window. Provider crashes, physical network changes, early boot, full reboot/wake and unknown ownership need dedicated live acceptance. Signing and notarization do not establish zero IP exposure or account eligibility. See [security](../SECURITY.md) and [validation status](FEATURE-STATUS.md).

Use **01 Preview (Safe)** to develop with offline data. Four `#Preview` macros in `App/main.swift` render the same menu AppKit view through Xcode Canvas, enabled only with `CCW_CANVAS`. Canvas checks content layout, not physical menu placement or full real-system click behavior. Production schemes are build-only. See [contributing](../CONTRIBUTING.md).

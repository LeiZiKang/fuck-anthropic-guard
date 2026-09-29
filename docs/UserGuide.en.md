# fuck-anthropic guard — User Guide

**English** | [简体中文](UserGuide.md)

Applies to 0.4.0 / build 12.0, the experimental Surge companion. Source is available for review; production filter activation and live failure scenarios have not been accepted. This is not the older SSH-relay version.

## 1. What Guard does

Guard lists reliably recognized Claude processes, offers confirmed termination, and displays read-only IPv6 settings. Its optional macOS system filter restricts recognized clients to a verified Surge endpoint.

**Surge forwards the traffic. Guard is not a proxy, VPN, or SSH tunnel and does not read VPS private keys.**

```text
Claude → dedicated local HTTP endpoint owned by Surge → Hysteria2 → VPS
                ↑
Guard checks the endpoint, rules, and exit, then permits or blocks recognized connections
```

## 2. Preview and production

| Build | Purpose |
|---|---|
| Guard Preview | Offline sample data. No real process termination, probes, or system-filter activation. |
| fuck-anthropic guard | Production code. Process and IPv6 viewing can be used separately; protection needs configuration, signing, and macOS approval. |
| Production Xcode schemes | Build only; they do not automatically install or activate a filter. |

Requires macOS 14 or later. Apple Silicon and Intel builds are supported. A production filter needs valid, matching Developer ID signing and Network Extension provisioning. A successful build or ad-hoc signature is not permission to load a system extension.

Do not run old and new production versions together. The new app does not inherit or restart the old SSH relay. Disable any active legacy protection explicitly before arranging migration.

## 3. Language, processes, and IPv6

On first launch, the app follows the system's preferred language: Chinese uses Simplified Chinese; other languages use English. The Language selector switches the interface immediately. Production saves your choice for future launches; Preview keeps it only in memory. Switching language does not restart monitoring, change Surge, alter filtering, or restore processes you have removed from the sample list.

Buttons, menus, confirmations, app-generated statuses, and future safety notifications follow the selected language. Network service names and process names retain their original names. macOS permission dialogs and system-provided error messages follow macOS language settings. Previously delivered notifications keep their original text.

The process list covers official Desktop, native CLI, and descendants whose identity can be reliably traced. A matching name alone is insufficient.

Choose **Quit listed Claude processes…** and confirm. The target identities are frozen before the dialog opens. Immediately before SIGTERM, the app rechecks each PID, user, start time, and executable path. Newly appearing processes are not added to the confirmed set. Save your work first; there is no automatic force quit. Processes that do not exit may remain listed.

IPv6 is shown for physical Wi-Fi and Ethernet services. Settings do not establish internet reachability. Turning IPv6 off on Wi-Fi does not mean loopback, AWDL, or VPN interfaces have no IPv6. Guard does not modify these settings.

## 4. Why a dedicated Surge endpoint is required

A shared Surge endpoint may legitimately route Xcode or other traffic DIRECT. Merely reaching that endpoint cannot establish VPS routing.

Strict protection requires a separate HTTP listener owned by Surge, such as 127.0.0.1:6154. Guard does not listen on this port. A first IN-PORT rule must pin that listener to one Hysteria2 node.

**The app does not edit Surge.** Merge the following example with your own configuration, retaining existing listeners and rules. Do not overwrite the whole profile or duplicate existing group names.

```ini
[General]
http-listen = 127.0.0.1:6152, 127.0.0.1:6154

[Proxy Group]
CLAUDE-LOCKED = select, Hysteria2

[Rule]
IN-PORT,6154,CLAUDE-LOCKED
# Must be the first effective rule.
# Keep existing Xcode DIRECT and other rules after it.
```

Configure your Hysteria2 node within Surge. The dedicated policy must have one node, no DIRECT fallback, no nested groups, and no script routing. MITM, scripting, rewrites, and temporary rules must be disabled or empty. Unsupported configurations do not receive an allow lease.

## 5. Configure protection

1. Arrange setup outside important Claude sessions and back up your Surge configuration.
2. Choose **Configure Surge checks…** and enter the dedicated HTTP port, expected VPS exit IP, and policy group.
3. **Verify and save** reads the signed Surge CLI and effective policy, then stores non-secret conditions and a digest. It does not save node passwords.
4. Choose **Enable protection…**, read the notice, and complete macOS network-filter approval.
5. Consented checks reach api.ipify.org through Surge without Claude credentials, cookies, or API keys. A recent exit match, stable policy, verified listener ownership, and confirmed filter execution are needed before the UI reports permission to connect.

Surge hides some node fields in CLI output. Guard does not bypass redaction or independently verify every hidden field. Surge manages the node's TLS configuration.

## 6. Launch Claude through the correct endpoint

When protection is enabled, recognized clients are limited to the configured loopback TCP endpoint. Direct remote connections, UDP, and other proxy ports are rejected by the policy. A normal Dock launch may still use the shared system proxy and therefore be blocked.

The optional source script configures only the new client process. It does not start a proxy, change the system proxy, or enable the filter:

```bash
bash scripts/launch-claude-via-surge.sh desktop 6154
bash scripts/launch-claude-via-surge.sh cli 6154
```

The script requires a verified official client. It refuses to reuse an already running Desktop. Quit the existing client normally before launching with new parameters. Process viewing alone does not require this script.

## 7. Status and quitting

| Status or action | Meaning |
|---|---|
| System protection is not enabled | Viewing only; do not rely on blocking. |
| Filter enforcement is unconfirmed | Execution is unknown; do not interpret it as protected. |
| Recognized connections: Blocking | No effective allow lease for recognized clients. |
| Dedicated route verified | A recent, bounded check passed; not a guarantee for every future request. |
| Waiting for blocking confirmation | Local allow conditions failed, but blocking execution is not yet confirmed. |
| Keep blocking | Withdraw allow permission while retaining the filter. |
| Disable protection… | Turn off system filtering; blocking no longer applies. |
| Close window | Keep the app running; reopen from the Dock or menu bar. |
| Keep blocking and quit | Quit the controller and retain the filter; its lease expires. |
| Disable protection and quit | Disable the filter, then quit. Components may remain installed. |

Reconfirm configuration after changes. Do not interpret a failed check as a safe connection merely because you changed ports or disabled filtering.

## 8. Safety notifications

Enabling protection requests macOS notification permission. During automatic monitoring, an unsafe or unconfirmed state triggers one notification per episode. Repeated polling does not flood notifications; recovery rearms the next alert. A manual hold does not trigger a failure alarm. Click a notification to open the app.

Denied permission, Focus, and system settings may suppress banners. The app still displays status. A notification means permission was withdrawn; it does not claim blocking is confirmed when filter execution is unknown. Real notification delivery still needs live acceptance.

## 9. Coverage limits

This is experimental protection, not a mature production security product.

- Only reliably identified clients and descendants are covered. Unknown identities, orphan processes, and third-party wrappers may be outside scope.
- Provider crashes, disabled extensions, early boot packets, physical network changes, and every IPv6 transition have not been fully accepted.
- Checks and leases have bounded lifetimes. There is a detection window after Surge rules change; an exit probe is not proof of every application's route.
- Socket-data filtering is not a guarantee that a remote peer has never seen any IP packet. Do not assume all DNS, TCP first packets, UDP, or system-owned connections are covered.
- Process termination can interrupt work. It is not a substitute for filtering.
- Signing, notarization, source availability, and offline tests do not guarantee account safety or zero IP leakage.

Use isolated, account-free fixtures for fault tests. Do not disable Surge, switch networks, or install an experimental filter during important work.

## 10. Troubleshooting and updates

| Problem | Check |
|---|---|
| Endpoint unverified | Is the port owned by the signed Surge process? Shared 6152/6153 are unsupported. |
| Policy failed | Is the dedicated IN-PORT rule first, with exactly one supported node and no temporary/script rules? |
| Exit mismatch or timeout | Inspect Surge and the node. Do not add DIRECT as a fallback. |
| Execution unknown | Check system approval and matching signatures. An open app window is not proof. |
| Claude cannot connect | Check whether it still uses a shared endpoint or old launch parameters. |
| Missing processes | Verify client identity and ancestry. Unknown processes are not terminated by name alone. |

Build offline Preview with `bash scripts/build.sh` or Xcode's `01 Preview (Safe)`. `CCW_BUILD_MODE=host` builds the host and filter without installing. Production signing requires your own valid developer configuration; never commit signing private keys.

The repository includes no VPS credentials or private runtime profile. Do not submit proxy passwords, SSH keys, cookies, Keychain exports, or personal logs. Review [PRD](PRD.en.md), [validation status](FEATURE-STATUS.md), and [security model](../SECURITY.md).

## Interface refresh (local UI revision)

- The overview shows connection state, the dedicated endpoint and pinned policy. A ready state applies only to currently verified recognized connections.
- Allowed, denied and unknown-owner decisions have separate counters; these are not unique connection counts or a security score.
- Clients lists processes; Local network shows read-only IPv6 settings; Settings & diagnostics contains configuration, enable/disable actions and diagnostic details.
- The menu-bar icon opens a compact status panel. English, Chinese and system light/dark appearance are supported. Language changes preserve protection state.
- This presentation revision does not change the filter, routing rules, lease lifetime or action confirmations.

## Connection journal and appearance (0.4.1)

Warm paper, clay accents, editorial headings and an original G shield. Anthropic-inspired dark appearance by default: charcoal, warm gray, ivory and clay. Theme switches to light.

Connections shows time, PID, destination, protocol, verdict and reason for recognized clients. All/Allowed/Denied filters and summary counters navigate the journal. Allowed means the endpoint and lease checks passed, not website success; later revocation remains possible. Denials include rejected new flows and revoked existing flows, not necessarily unique connections. Endpoint-match counts are no longer shown as total allowed decisions.

Only the latest 80 events are retained in filter memory and reset on extension restart. No chat, payload, URL paths or credentials. Unknown owners are counted without unrelated app histories. Stale status is labeled; retained events are not current permission. Pre-upgrade history cannot be recovered.

How it works: Claude -> Guard system filter -> dedicated Surge endpoint -> proxy node -> website. Guard does not provide a VPN, subscription or SSH tunnel. Surge provides transport. 127.0.0.1:6154 is the proxy endpoint, not the final website. This version upgrades filter metadata reporting while retaining route predicates and lease enforcement.

## 0.4.2 usability

Block Claude connections now confirms its impact; cancel preserves permission. Resume checks verifies before allowing connections. Settings reflects the actual state and offers a read-only endpoint view while enabled or unconfirmed. Recheck retries the filter control connection; the client refresh only updates process inventory.

Search connections by identity, PID or endpoint; clearing search restores the category. Click column headers to sort, then select an event for details or copying. Details include full time, signing identity, destination and recorded trigger. Missing historical causes are disclosed rather than inferred. Unknown ownership has an explanation and is not a leak count.

Summary actions are native buttons, denied text has stronger contrast, appearance persists in the live app, and smaller windows scroll.

## 0.4.3 input validation
Invalid ports, egress IPs or policy names show a specific error inside the existing dialog and preserve entered values. Correct them to save, or cancel without changing configuration. Shared/legacy ports and reserved policy names are rejected. Existing Surge configuration verification remains unchanged.

## 0.4.4 menu bar
The menu popover and Xcode Canvas share the same AppKit content view with20pt padding, protection state, recognized processes, endpoint and last filter status time. Recheck invokes the main recheck path; Open window shows the full panel. The menu symbol distinguishes ready, blocked, checking and disabled states. Filtering rules are unchanged.

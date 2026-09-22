# Security model

**English** | [简体中文](SECURITY.zh-CN.md)

This is an experimental macOS process manager and Surge connection guard, not a VPN.

## Scope

The data filter uses signed identities and verified same-user ancestry to identify
Claude clients. Unattributed or orphaned processes are a coverage gap. Surge and
other users' ordinary flows are excluded. Broad process-name termination is not used.

Recognized clients are constrained to the approved Surge loopback TCP endpoint.
Short-lived permits bind runtime configuration, a signed Surge listener process,
an expected exit probe, provider generation, boot/session and a fresh challenge.
Stale or malformed evidence does not allow a protected flow. Sequenced updates
prevent a delayed old permit overriding a newer blocking request.

## Limits

- Data-filter verdicts do not prove no IP packet ever reached a peer.
- A periodic profile/exit check is not a per-request cryptographic route proof.
- There is a bounded observation window for configuration changes.
- Provider crashes, disablement, OS upgrades and boot restoration need dedicated
  live validation. A running window is not evidence of enforcement.
- Positive signed identity caching and descendant tracking are bounded. Unknown
  ownership is disclosed, not represented as universally protected.
- Source visibility, code signing and notarization are not a comprehensive audit.

## Data

No VPS private keys, account secrets, cookies or chats are required. The active
Surge profile is handled in memory; persisted settings contain non-secret endpoint,
expected exit, policy name and configuration digest. Never commit real profiles,
logs, credentials, provisioning/private signing exports or user directories.

Report issues privately through the repository's available security reporting
channel. Do not include credentials or complete personal logs in public issues.

# Validation status — 0.4.4 beta / build 13.0

**English** | [简体中文](FEATURE-STATUS.zh-CN.md)

| Area | Evidence | Boundary |
|---|---|---|
| Source and builds | 271 Preview / 273 host offline checks; Xcode schemes and standalone builds; Universal 2 compilation | Counts overlap; Intel hardware not tested |
| Local filtering | Earlier development build 12.2 allowed the dedicated 6154 TCP endpoint and denied wrong loopback ports and sampled child UDP paths | Local fixtures, not every external protocol or OS failure |
| UI | Search/clear/sort/details/copy, block cancellation, language and appearance; invalid form input/corrected save | Not a full accessibility audit |
| Menu content | Actual Xcode Canvas#Preview for four states, English/Chinese; shared production AppKit view | System menu targeting, arrow placement and full click flow not automated |
| Distribution | Versioned signed/notarized ZIP, frozen source/artifact/release-text review required | Public build 13.0 has not been installed as a new live acceptance test |

## Still pending

Physical network loss/recovery, full machine reboot/wake, provider crashes, early boot and complete unknown-attribution coverage. A running app or a notarization receipt does not prove these cases.

## Data and controls

The journal retains only the latest 80 protected-client metadata events in provider memory. It resets when the extension restarts. It contains no packet payloads, chat, URL paths or account credentials. Unknown owners are counted without recording unrelated application histories. Egress checks use the consented Surge path; no direct fallback is provided.

Production activation is explicit. Default Xcode Run is 01 Preview (Safe); host/filter schemes build without activating system filtering. See [security](../SECURITY.md), [guide](UserGuide.en.md) and [release notes](RELEASE-NOTES.md).

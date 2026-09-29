# 0.4.4 / build 13.0

Stable release of the existing Developer ID-signed, Apple-notarized Universal 2 build 13.0. This is the same ZIP content as v0.4.4-beta.1; only the release channel, tag and download filename change. There is no new runtime code or binary rebuild.

## Highlights

- Inspectable connection journal with process, destination, verdict and reason.
- Refined dark/light interface, input validation and shared menu-bar status panel.
- Recognized Claude clients use a verified dedicated Surge TCP endpoint; Surge remains separately managed.
- Homebrew distribution uses the exact same verified archive as the GitHub download.

## Verification and remaining limits

The existing build passed 271 Preview / 273 host offline checks (overlapping coverage), Universal 2 compilation, Developer ID signature checks, Apple notarization and Gatekeeper assessment. Build 13.0 was installed through Homebrew: the filter is active, the UI reports protection ready, and local signed CLI/child tests allowed port 6154 and denied incorrect loopback ports. Intel is compile-verified only.

The maintainer chose to publish this stable release while deferring physical network-loss/recovery, reboot/wake, provider-crash, early-boot, unknown-attribution and full native menu interaction checks. These remain unverified; stable is a distribution channel, not a claim that those tests passed. Guard is not a VPN or an account-safety guarantee.

## Installation

Download the versioned ZIP or install `leizikang/tap/fuck-anthropic-guard` through Homebrew after the tap update. macOS 14 or later is required. Existing build 13.0 users already have identical executables and need no app/filter restart for this channel change. For other upgrades, follow the setup guide and confirm protection after replacement.

SHA-256: `2e2e00db1c591100a22bb3a716cd070cc493b110bd89b6900207abb869c9049d`

# Automatic Guard releases

The `Release Guard` GitHub Actions workflow runs on GitHub-hosted macOS workers. A push to `main` that changes `Info.plist` starts a version check; `workflow_dispatch` on main can resume/reconcile a release. Other branches and fork repositories cannot release.

## Version contract

For a new release, increase `CFBundleShortVersionString` to a new stable `X.Y.Z` and increase `CFBundleVersion` above the last released build. Host and filter metadata are generated from this source. The first line of `docs/RELEASE-NOTES.md` must be `# X.Y.Z / build N.N`. Commit the real release notes and relevant validation limits with the version change. No existing tag or public asset is overwritten.

Stages: plan -> credential-free Universal 2 build/tests -> ephemeral-keychain signing and Apple notarization -> separate signature, metadata, architecture, icon and ticket verification -> GitHub Release/Latest -> exact-hash Homebrew cask update.

A completed stable version is not rebuilt. A main dispatch downloads and verifies its existing signed archive, then reconciles the tap. The pipeline binds the tap to the verified manifest and checks for newer releases before every publication write. Concurrent runs queue; an older run cannot downgrade a newer version.

## Secrets

Configure the following in this repository (or its `release` environment). Never put values in files committed to Git, workflow YAML, PR text or logs.

| Secret | Required material |
|---|---|
| `MACOS_CERTIFICATE_P12_BASE64` | Encrypted P12 containing only the approved Developer ID Application identity |
| `MACOS_CERTIFICATE_PASSWORD` | Password for that P12 |
| `MACOS_HOST_PROFILE_BASE64` | Developer ID host provisioning profile |
| `MACOS_FILTER_PROFILE_BASE64` | Developer ID content-filter provisioning profile |
| `APPLE_ID` | Apple account used for notarization |
| `APPLE_APP_PASSWORD` | Its app-specific notarization password |
| `HOMEBREW_TAP_SSH_KEY` | Dedicated SSH deploy key with write access only to homebrew-tap; respect branch protections |

The built-in workflow token publishes the Guard release. The tap uses a repository-scoped deploy key, not a broad personal `gh` OAuth token. Host keys come from GitHub's HTTPS metadata API and are checked strictly. Certificate/password extraction may require macOS user-presence authorization even after task approval; do not alter key ACLs to bypass it.

The signing job creates and deletes its own temporary keychain. It validates ZIP entries before extraction, never runs the application, and deletes certificate/profile input files on exit. The verification job has no signing/notary secrets. Restoring a notary attempt uses the exact signed submission ZIP and its saved submission ID; it never trusts a separate mutable app copy.

## Recovery

- Notarization timeout: rerun failed jobs within artifact retention. The saved submission ID and input ZIP are reused; no duplicate submission is made merely because waiting timed out.
- Missing/expired/unreadable recovery state: stop and inspect the previous attempt. A fresh dispatch is appropriate only after confirming the previous submission outcome; do not assume a network error means no submission happened.
- Apple rejection: inspect Apple's submission log privately, fix the source and create a new version/build; do not publish the rejected package.
- Release succeeded but tap failed: dispatch from main at the same version. It verifies the original public asset before retrying the tap.
- Orphan tag or incomplete release: stop for maintainer recovery; do not force-retag or clobber an asset.
- Newer version already published: the old run stops rather than moving Latest or the tap backwards.

This automation does not update the maintainer's installed app, activate system filtering, modify Surge, or claim untested runtime scenarios passed. The separate release skill remains a deferred todo; this pipeline does not install it.

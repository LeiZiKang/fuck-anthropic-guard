# Branch and release workflow

- `main` is the reviewed integration branch. New work starts from current `origin/main` and reaches it through a PR.
- Use a focused `codex/feature-<topic>` branch for publication. Do not push directly to main or force-update a branch used by another worktree.
- `archive/*` names preserve local historical work; they are not release branches and should not be pushed as current products.
- Preserve unique commits and uncommitted changes before cleaning up a linked worktree. A missing temporary directory is not permission to delete its branch history.

## Development

Xcode navigator: App / Core / Network Filter / Preview / Tests / Resources / Documentation / Build & Release / Products. Physical source locations and target membership remain explicit.

Use **01 Preview (Safe)** and Xcode MCP BuildProject/GetBuildLog for incremental builds. Four menu `#Preview` definitions in App/main.swift use `CCW_CANVAS`, set only for the Xcode Preview target. The standalone `scripts/test.sh` build excludes Canvas macros. Production schemes build without activating filtering.

## Release

1. Update version/build metadata, README, guides, validation status and release notes. A replacement filter needs a compatible new host/provider build identifier.
2. Commit and freeze source on a `codex/feature-` branch.
3. Use `scripts/publish-release.sh --prepare --tag v<version>-beta.<n>` with signing profiles supplied externally. It builds Universal 2, runs host checks and writes a versioned candidate manifest. It does not publish.
4. Use `--notarize` for the approved Apple upload. The submission ID is saved for resumption; the stapled ZIP receives a new digest.
5. A separate reviewer must inspect frozen source, reachable history, exact ZIP and release text. Produce matching source-only and binary-prerelease audit reports.
6. The publication gate checks exact commit/tree, branch, origin, archive digest, release tag and release-text digest. Push the reviewed feature, create a PR, verify CI, merge without bypassing protection, then publish the reviewed prerelease.
7. Verify remote main, tag and downloadable asset. Delete only merged remote task branches; retain unrelated/local historical work. A Homebrew tap update is a separate change.

The gate is a workflow check, not an exhaustive security proof. Never publish private profiles, keys, logs, tokens, personal paths or backups.

## Promote an existing notarized build to stable

An explicit maintainer decision can defer known validation items without marking them passed. Preserve those limits in stable notes. Freeze publication-only changes on a feature branch, then use `scripts/publish-release.sh --prepare --stable --tag v<version> --reuse-from v<version>-beta.<n>`. The gate rejects changed runtime/build inputs and copies the already notarized ZIP byte-for-byte. The manifest records the original artifact source commit separately from the current publication source.

Obtain new matching independent source-only and binary-stable reviews. Publish source with `--stable --source-only --audit-report`, complete PR/CI/main, then publish with `--stable --audit-report`. The stable tag targets the original artifact source commit; the reviewed publication docs/scripts live on main. Retain the historical beta tag/release. Verify the new public URL/hash, update the tap and check current installed binaries before considering any reinstall.

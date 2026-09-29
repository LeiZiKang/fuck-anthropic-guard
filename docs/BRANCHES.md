# Branch workflow

Current development branch: `codex/guard-0.4.2-polish`.
Base: `origin/main` (the merged 0.4.0 beta baseline). This branch has no upstream
until it is deliberately published. It must not push directly to main.

## Roles

- `origin/main`: published integration history; use this as the base for new work.
- `codex/guard-0.4.2-polish`: local 0.4.1 UI/journal implementation plus 0.4.2 UX fixes and project organization.
- `archive/merged-homebrew-beta-20260929`: preserved former `codex/feature-homebrew-beta`; already in origin/main.
- `archive/merged-public-guard-20260929`: preserved former `codex/feature-surge-guard-public`; already in origin/main.
- Older `codex/*` validation branches and local `main`: historical work. Several
  are checked out in other worktrees; do not reset, delete, or reuse them blindly.

Local `main` belongs to an older checkout and has diverged from `origin/main`.
It is NOT the current integration baseline. Preserve its unique commits until
that checkout has been reviewed with its owner. Temporary validation worktree
registrations may reference missing directories; this does not authorize deleting
branches or their commits.

## Routine development

1. Fetch origin using the existing working network setup.
2. Start a focused `codex/<topic>` branch from `origin/main`.
3. Keep local changes in coherent commits; separate behavior changes from Xcode
   navigator/build metadata changes.
4. Prefer Xcode MCP `BuildProject` on `01 Preview (Safe)` for incremental builds.
   Use `GetBuildLog` with errors/warnings rather than dumping full logs.
5. Build `02 Watcher - Build Only` only to validate production compilation. Never
   run a production filter as a development test. The shell build remains a
   reproducible packaging/CI fallback.
6. Before any public push/release, follow AGENTS.md's independent review gate.
   Local signing/notarization/installation is separate from public publication.
7. After merge, archive or remove only reviewed, unused branches. Never force
   update a branch used by another worktree, and never confuse archived code with
   the running app.

## Xcode navigator

App / Core / Network Filter / Preview / Tests / Resources / Documentation /
Build & Release / Products. Groups organize existing file references without
moving physical source files or changing target membership. Existing bundle and
Mach-service identifiers remain stable.

Remote freshness: GitHub fetch failed during this maintenance (direct timeout, proxy HTTP/2 error and HTTP/1.1 empty reply). The base is the last known origin/main at da9287b; do not claim the remote was refreshed. No remote refs were modified.

## Xcode Canvas
On01 Preview (Safe), open App/main.swift and Canvas. Four named#Preview entries render the actual GuardMenuPanel used by the live NSPopover. Use Xcode MCP RenderPreview and locale overrides for English/Chinese. This is Xcode Canvas, distinct from running the standalone Preview app. Never switch to the production scheme to simulate menu states.

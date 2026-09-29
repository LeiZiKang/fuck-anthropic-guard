#!/usr/bin/env python3
"""Prepare, notarize and publish an exact independently reviewed release."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import shutil

R = Path(__file__).resolve().parents[1]
ORIGIN = 'https://github.com/LeiZiKang/fuck-anthropic-guard.git'
REPO = 'LeiZiKang/fuck-anthropic-guard'
MATCH_KEYS = ('source_commit', 'source_tree', 'zip_sha256', 'branch', 'origin',
              'tag', 'release_notes_sha256', 'app_version', 'build_version')

def run(*args, **kwargs):
    return subprocess.run(args, cwd=R, check=True, **kwargs)

def git(*args):
    return subprocess.check_output(['git', *args], cwd=R, text=True).strip()

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def stop(message):
    raise SystemExit(message)

def publication_target():
    branch = git('branch', '--show-current')
    if not branch.startswith('codex/feature-'):
        stop('Publish only from a reviewed codex/feature- branch, never directly to main.')
    if any(git('remote', 'get-url', *args, 'origin') != ORIGIN for args in [(), ('--push',)]):
        stop('Unexpected publication remote.')
    if git('status', '--porcelain'):
        stop('Commit source before preparing or publishing frozen inputs.')
    return branch

def release_tag(version, requested):
    tag = requested or f'v{version}-beta.1'
    if not re.fullmatch(r'v' + re.escape(version) + r'(?:-[A-Za-z0-9.-]+)?', tag):
        stop('Release tag must match the app version.')
    return tag

def artifact_path(manifest, directory):
    name = manifest.get('zip', '')
    if not name or Path(name).name != name or not name.endswith('.zip'):
        stop('Invalid artifact filename.')
    path = directory / name
    if path.is_symlink() or not path.is_file():
        stop('Artifact is missing or is a symlink.')
    return path

def validate_frozen(manifest, directory, notes, head, tree, branch, tag):
    for key, value in [('source_commit', head), ('source_tree', tree), ('branch', branch),
                       ('origin', ORIGIN), ('tag', tag)]:
        if manifest.get(key) != value:
            stop('Frozen inputs changed: ' + key)
    archive = artifact_path(manifest, directory)
    if sha(archive) != manifest.get('zip_sha256'):
        stop('Frozen archive changed.')
    if sha(notes) != manifest.get('release_notes_sha256'):
        stop('Release text changed; independent review must be repeated.')
    return archive

def validate_review(review, manifest, source_only):
    for key in MATCH_KEYS:
        if review.get(key) != manifest.get(key):
            stop('Independent audit does not match ' + key)
    expected = 'source-only' if source_only else ('binary-stable' if manifest.get('stable') else 'binary-prerelease')
    for key in ('stable', 'reused_from_tag', 'artifact_source_commit'):
        if review.get(key) != manifest.get(key):
            stop('Independent audit does not match ' + key)
    if (review.get('publication_kind') != expected or review.get('decision') != 'pass'
        or not review.get('independent_reviewer') or review.get('tap_changed') is not False):
        stop('A passing independent review for this exact publication scope is required.')
    if not source_only and not manifest.get('notarized'):
        stop('Binary publication requires notarization.')

def reuse_candidate(previous, previous_dir, tag, version, build, head):
    if previous.get('origin') != ORIGIN or previous.get('tag') != tag:
        stop('Unexpected source release manifest.')
    if not previous.get('notarized') or previous.get('app_version') != version or previous.get('build_version') != build:
        stop('Promotion requires the same notarized app version and build.')
    archive = artifact_path(previous, previous_dir)
    if sha(archive) != previous.get('zip_sha256'):
        stop('Source release archive changed.')
    source = previous.get('artifact_source_commit') or previous['source_commit']
    if git('rev-parse', tag + '^{commit}') != source:
        stop('Source tag does not match artifact source.')
    # Only publication metadata/docs may differ. Never reuse a binary after runtime edits.
    changed = git('diff', '--name-only', source, head).splitlines()
    allowed = {'README.md', 'README.zh-CN.md', 'todo.md',
               'scripts/publish_release.py', 'scripts/test_publish_release.py'}
    if any(path not in allowed and not path.startswith('docs/') for path in changed):
        stop('Runtime/build inputs changed; cannot promote the existing binary.')
    return archive, source


def pack(app, archive):
    if archive.exists():
        archive.unlink()
    run('/usr/bin/ditto', '-c', '-k', '--keepParent', '--sequesterRsrc', str(app), str(archive))

def save(path, data):
    path.write_text(json.dumps(data, indent=2) + '\n')

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    action = parser.add_mutually_exclusive_group(required=True)
    action.add_argument('--prepare', action='store_true')
    action.add_argument('--notarize', action='store_true')
    action.add_argument('--audit-report')
    parser.add_argument('--source-only', action='store_true')
    parser.add_argument('--tag')
    parser.add_argument('--stable', action='store_true', help='Explicitly publish a stable version, not a beta')
    parser.add_argument('--reuse-from', help='During stable preparation, reuse an existing notarized prerelease ZIP')
    args = parser.parse_args()
    branch = publication_target()
    info = plistlib.loads((R / 'Info.plist').read_bytes())
    version, build = info['CFBundleShortVersionString'], info['CFBundleVersion']
    tag = release_tag(version, args.tag or (f'v{version}' if args.stable else None))
    if args.stable and tag != f'v{version}':
        stop('Stable publication requires the plain version tag.')
    if args.reuse_from and (not args.prepare or not args.stable):
        stop('--reuse-from is only valid with --prepare --stable.')
    directory = R / 'release' / tag
    manifest_path = directory / 'candidate.json'
    notes = R / 'docs/RELEASE-NOTES.md'
    app = R / 'dist' / tag / 'fuck-anthropic guard.app'
    if args.prepare:
        if manifest_path.exists():
            stop('Candidate already exists; preserve it and use a new tag/output directory.')
        previous = None
        if args.reuse_from:
            previous_tag = release_tag(version, args.reuse_from)
            if previous_tag == tag:
                stop('Source and destination tags must differ.')
            previous_dir = R / 'release' / previous_tag
            previous = json.loads((previous_dir / 'candidate.json').read_text())
            old_archive, artifact_source = reuse_candidate(previous, previous_dir, previous_tag, version, build, git('rev-parse', 'HEAD'))
        directory.mkdir(parents=True, exist_ok=True)
        archive = directory / f'fuck-anthropic-guard-{tag[1:]}.zip'
        if previous:
            shutil.copyfile(old_archive, archive)
        else:
            env = {**os.environ, 'CCW_BUILD_MODE': 'host', 'CCW_ARCHITECTURES': 'arm64 x86_64',
                   'CCW_OUTPUT_ROOT': str(app.parent)}
            run('bash', 'scripts/build.sh', env=env)
            run(str(app / 'Contents/MacOS/ClaudeConnectionWatcher'), '--self-test')
            pack(app, archive)
        manifest = dict(source_commit=git('rev-parse', 'HEAD'), source_tree=git('rev-parse', 'HEAD^{tree}'),
                        branch=branch, origin=ORIGIN, tag=tag, app_version=version, build_version=build,
                        zip=archive.name, zip_sha256=sha(archive), notarized=False, tap_changed=False,
                        release_notes_sha256=sha(notes), architectures=['arm64', 'x86_64'])
        manifest['stable'] = args.stable
        if previous:
            manifest.update(notarized=True, reused_from_tag=previous_tag, artifact_source_commit=artifact_source,
                            notary_submission_id=previous.get('notary_submission_id'))
        save(manifest_path, manifest)
        print(json.dumps(manifest))
        return
    manifest = json.loads(manifest_path.read_text())
    if bool(manifest.get('stable')) != args.stable:
        stop('Release channel differs from frozen manifest.')
    archive = validate_frozen(manifest, directory, notes, git('rev-parse', 'HEAD'),
                              git('rev-parse', 'HEAD^{tree}'), branch, tag)
    if args.notarize:
        profile = os.environ.get('CCW_NOTARY_PROFILE')
        if not profile:
            stop('Set an existing CCW_NOTARY_PROFILE; do not put credentials in this script.')
        if manifest.get('notarized'):
            print('This exact archive is already notarized.'); return
        # Ensure the signed app still corresponds to the submitted archive.
        run('/usr/bin/codesign', '--verify', '--all-architectures', '--deep', '--strict', str(app))
        # File digests from the ZIP are compared without changing the candidate.
        import tempfile
        with tempfile.TemporaryDirectory(prefix='guard-notary-check-') as temp:
            run('/usr/bin/ditto', '-x', '-k', str(archive), temp)
            extracted = Path(temp) / app.name
            def files(root):
                return {str(p.relative_to(root)): ('link:' + str(p.readlink()) if p.is_symlink() else sha(p))
                        for p in root.rglob('*') if p.is_file() or p.is_symlink()}
            if files(extracted) != files(app):
                stop('Prepared app changed since archive creation.')
        submission = manifest.get('notary_submission_id')
        if not submission:
            result = run('xcrun', 'notarytool', 'submit', str(archive), '--keychain-profile', profile,
                         '--output-format', 'json', capture_output=True, text=True)
            submission = json.loads(result.stdout)['id']
            manifest['notary_submission_id'] = submission
            manifest['notary_input_sha256'] = sha(archive)
            save(manifest_path, manifest)
        result = run('xcrun', 'notarytool', 'wait', submission, '--keychain-profile', profile,
                     '--timeout', '10m', '--output-format', 'json', capture_output=True, text=True)
        response = json.loads(result.stdout); save(directory / 'notary-result.json', response)
        if response.get('status') != 'Accepted':
            stop('Notarization not accepted; nothing published. Inspect the submission log.')
        run('xcrun', 'stapler', 'staple', str(app))
        run('xcrun', 'stapler', 'validate', str(app))
        run('/usr/sbin/spctl', '--assess', '--type', 'execute', str(app))
        pack(app, archive)
        manifest.update(notarized=True, zip_sha256=sha(archive))
        save(manifest_path, manifest)
        print(json.dumps(manifest))
        return
    review = json.loads(Path(args.audit_report).read_text())
    validate_review(review, manifest, args.source_only)
    run('git', 'push', '--set-upstream', 'origin', 'HEAD:refs/heads/' + branch)
    if not args.source_only:
        run('gh', 'release', 'create', tag, str(archive), '--repo', REPO,
            '--target', manifest.get('artifact_source_commit', manifest['source_commit']),
            *(['--latest=true'] if args.stable else ['--prerelease', '--latest=false']),
            '--title', f'fuck-anthropic guard {version}' + ('' if args.stable else ' beta'), '--notes-file', str(notes))
    print('Published independently reviewed inputs; main merge and tap are separate actions.')

if __name__ == '__main__':
    main()

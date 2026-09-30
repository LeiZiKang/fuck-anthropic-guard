#!/usr/bin/env python3
"""Trusted-main release orchestration. No credential values are logged."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request
import zipfile
import stat
import shlex

REPO = 'LeiZiKang/fuck-anthropic-guard'
TAP = 'LeiZiKang/homebrew-tap'
APP = 'fuck-anthropic guard.app'
HOST = 'com.leizikang.claude-connection-watcher'
FILTER = HOST + '.filter'
TEAM = 'Y355LMZA6C'
ROOT = Path(__file__).resolve().parents[2]

def run(args, **kw):
    return subprocess.run(args, check=True, **kw)

def gh(*args):
    result = subprocess.run(['gh', *args], capture_output=True, text=True)
    if result.returncode:
        raise RuntimeError('GitHub command failed: ' + ' '.join(args[:2]))
    return result.stdout.strip()

def api(path, method='GET', data=None, missing=False):
    token = os.environ.get('GH_TOKEN', '')
    headers = {'Content-Type':'application/json', 'Accept':'application/vnd.github+json', 'X-GitHub-Api-Version':'2022-11-28'}
    if token: headers['Authorization'] = 'Bearer ' + token
    request = urllib.request.Request('https://api.github.com/' + path, headers=headers,
        method=method, data=json.dumps(data).encode() if data is not None else None)
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            body = response.read()
            return json.loads(body) if body else None
    except urllib.error.HTTPError as error:
        if missing and error.code == 404: return None
        raise RuntimeError('GitHub API failed with HTTP ' + str(error.code)) from None

def version_tuple(value):
    if not re.fullmatch(r'(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)', value): raise ValueError('Version must be stable X.Y.Z')
    return tuple(map(int, value.split('.')))

def build_tuple(value):
    if not re.fullmatch(r'\d+(?:\.\d+){0,2}',value): raise ValueError('Invalid build number')
    parts=tuple(map(int,value.split('.')))
    return parts+(0,)*(3-len(parts))

def metadata():
    data = plistlib.loads((ROOT/'Info.plist').read_bytes())
    version, build = data['CFBundleShortVersionString'], data['CFBundleVersion']
    version_tuple(version)
    if not re.fullmatch(r'\d+(?:\.\d+){0,2}', build): raise ValueError('Invalid build number')
    return version, build

def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()

def trusted_main():
    if os.environ.get('GITHUB_REPOSITORY') != REPO or os.environ.get('GITHUB_REF') != 'refs/heads/main':
        raise ValueError('Only the canonical repository main branch may release')
    if os.environ.get('GITHUB_EVENT_NAME') not in ('push', 'workflow_dispatch'):
        raise ValueError('Unsupported release event')
    commit = os.environ.get('GITHUB_SHA', '')
    if not re.fullmatch(r'[0-9a-f]{40}', commit): raise ValueError('Invalid frozen source SHA')
    if subprocess.check_output(['git','rev-parse','HEAD'], cwd=ROOT, text=True).strip() != commit:
        raise ValueError('Checkout does not match frozen workflow SHA')
    return commit

def release_info(tag): return api(f'repos/{REPO}/releases/tags/{tag}', missing=True)

def ensure_not_older(version):
    latest = api(f'repos/{REPO}/releases/latest', missing=True)
    if latest and latest['tag_name'].startswith('v'):
        if version_tuple(version) < version_tuple(latest['tag_name'][1:]):
            raise ValueError('A newer stable release already exists; refuse downgrade')

def asset_for(release, version):
    matches = [a for a in release.get('assets',[]) if a['name'] == f'fuck-anthropic-guard-{version}.zip']
    if len(matches) != 1: raise ValueError('Expected exactly one versioned ZIP; never overwrite assets')
    asset = matches[0]
    if not re.fullmatch(r'sha256:[0-9a-f]{64}', asset.get('digest') or ''):
        raise ValueError('Published asset lacks a verifiable SHA-256')
    return asset

def plan(output):
    commit = trusted_main(); version, build = metadata(); tag = 'v' + version
    ensure_not_older(version)
    release = release_info(tag)
    tag_ref = api(f'repos/{REPO}/git/ref/tags/{tag}', missing=True)
    if release:
        if release['draft'] or release['prerelease']: raise ValueError('Release exists but is not a complete stable release')
        asset_for(release, version)
        if not tag_ref: raise ValueError('Published release tag is missing')
        mode = 'existing'
    else:
        if tag_ref: raise ValueError('Orphan/existing tag conflicts with new release; manual recovery required')
        latest = api(f'repos/{REPO}/releases/latest', missing=True)
        if latest:
            import base64
            tag_name = latest['tag_name']
            version_tuple(tag_name.removeprefix('v'))
            previous = api(f'repos/{REPO}/contents/Info.plist?ref={tag_name}')
            old_build = plistlib.loads(base64.b64decode(previous['content']))['CFBundleVersion']
            if build_tuple(build) <= build_tuple(old_build):
                raise ValueError('New releases must increase CFBundleVersion for the system extension')
        heading=(ROOT/'docs/RELEASE-NOTES.md').read_text().splitlines()[0]
        if not re.fullmatch(r'# '+re.escape(version)+r' / build '+re.escape(build),heading):
            raise ValueError('Release notes heading must match version and build')
        mode = 'new'
    values = dict(mode=mode, version=version, build=build, tag=tag, source_commit=commit)
    with open(output, 'a') as f:
        for key,value in values.items(): f.write(f'{key}={value}\n')
    print(json.dumps(values))

def make_manifest(app, output):
    commit = trusted_main(); version, build = metadata()
    paths = [app/'Contents/Info.plist', app/f'Contents/Library/SystemExtensions/{FILTER}.systemextension/Contents/Info.plist']
    for path in paths:
        info = plistlib.loads(path.read_bytes())
        if info['CFBundleShortVersionString'] != version or info['CFBundleVersion'] != build:
            raise ValueError('Host/provider metadata differs from release')
    data = dict(source_commit=commit, version=version, build=build, tag='v'+version,
                notes_sha256=sha(ROOT/'docs/RELEASE-NOTES.md'), automated=True)
    output.write_text(json.dumps(data, indent=2)+'\n')

def validate_archive(archive):
    from pathlib import PurePosixPath
    seen=set()
    with zipfile.ZipFile(archive) as z:
        if sum(i.file_size for i in z.infolist()) > 512*1024*1024:
            raise ValueError('Archive is unexpectedly large')
        for item in z.infolist():
            name=item.filename
            parts=PurePosixPath(name).parts
            if not parts or name.startswith('/') or '\\' in name or '..' in parts or any(ord(c)<32 for c in name):
                raise ValueError('Unsafe archive path')
            normalized=str(PurePosixPath(name))
            if normalized in seen: raise ValueError('Duplicate archive path')
            seen.add(normalized)
            if stat.S_ISLNK(item.external_attr >> 16): raise ValueError('Symlinks are not allowed in this app archive')
            if parts[0] == '__MACOSX':
                if len(parts)>1 and parts[1] not in (APP,'._'+APP): raise ValueError('Unexpected resource-fork path')
                if not item.is_dir() and not parts[-1].startswith('._'): raise ValueError('Unexpected metadata file')
            elif parts[0] != APP: raise ValueError('Unexpected archive top-level entry')
        if APP+'/Contents/Info.plist' not in seen: raise ValueError('Archive lacks the expected application')
        if z.testzip() is not None: raise ValueError('Archive CRC check failed')

def extract(archive, destination):
    validate_archive(archive)
    if (destination/APP).exists(): raise ValueError('Refuse to merge archive into an existing bundle')
    destination.mkdir(parents=True,exist_ok=True)
    run(['ditto','-x','-k',str(archive),str(destination)])

def restore_state(directory):
    trusted_main()
    run_id=os.environ.get('GITHUB_RUN_ID','')
    if not run_id.isdigit(): raise ValueError('Invalid workflow run ID')
    data=api(f'repos/{REPO}/actions/runs/{run_id}/artifacts?per_page=100')
    matches=[a for a in data['artifacts'] if a['name']=='notary-state-'+run_id]
    if not matches:
        # A rerun may follow missing credentials before any Apple request. Later
        # uncertainty must be resolved explicitly, not silently submitted again.
        raise ValueError('No saved notarization state on rerun; inspect previous attempt before a fresh dispatch')
    if len(matches)!=1 or matches[0]['expired']: raise ValueError('Saved notarization state is missing/expired')
    directory.mkdir(parents=True,exist_ok=True)
    gh('run','download',run_id,'--repo',REPO,'--name','notary-state-'+run_id,'--dir',str(directory))
    if not (directory/'notary-state.json').is_file():
        raise ValueError('Previous attempt has no submission receipt; inspect before a fresh dispatch')

def verify(app, manifest, signed=True):
    m = json.loads(manifest.read_text()); version_tuple(m['version'])
    archive=manifest.parent/(f"fuck-anthropic-guard-{m['version']}.zip" if signed else 'unsigned.zip')
    expected=m.get('zip_sha256') if signed else m.get('unsigned_zip_sha256')
    if not expected or sha(archive)!=expected: raise ValueError('Verification archive/manifest digest mismatch')
    validate_archive(archive)
    if not re.fullmatch(r'[0-9a-f]{40}', m['source_commit']): raise ValueError('Invalid artifact provenance')
    if m['tag'] != 'v'+m['version']: raise ValueError('Artifact tag/version mismatch')
    parts = [(app,HOST,'ClaudeConnectionWatcher'),(app/f'Contents/Library/SystemExtensions/{FILTER}.systemextension',FILTER,'ClaudeConnectionFilter')]
    for bundle,identifier,executable in parts:
        info=plistlib.loads((bundle/'Contents/Info.plist').read_bytes())
        if (info['CFBundleIdentifier'],info['CFBundleShortVersionString'],info['CFBundleVersion']) != (identifier,m['version'],m['build']):
            raise ValueError('Bundle identity/version mismatch')
        binary=bundle/'Contents/MacOS'/executable
        archs=subprocess.check_output(['xcrun','lipo','-archs',str(binary)],text=True).split()
        if set(archs)!={'arm64','x86_64'}:raise ValueError('Universal 2 required')
        if signed:
            requirement=f'anchor apple generic and certificate leaf[subject.OU] = "{TEAM}" and identifier "{identifier}"'
            run(['codesign','--verify','--all-architectures','--strict','-R='+requirement,str(bundle)])
        for path in bundle.rglob('*'):
            if path.is_symlink():
                try: path.resolve().relative_to(app.resolve())
                except ValueError: raise ValueError('Bundle symlink escapes app')
            elif path.is_file() and path.suffix in ('.p8','.p12','.pfx','.keychain-db','.key'):
                raise ValueError('Credential-like file must not ship')
    icon=plistlib.loads((app/'Contents/Info.plist').read_bytes()).get('CFBundleIconFile')
    if icon not in ('Watcher','Watcher.icns') or not (app/'Contents/Resources/Watcher.icns').is_file():
        raise ValueError('Packaged application icon missing')
    run(['python3',str(ROOT/'scripts/check_system_extension_metadata.py'),str(parts[1][0]/'Contents/Info.plist'),'--host',str(app/'Contents/Info.plist')])
    if signed:
        run(['xcrun','stapler','validate',str(app)])
        run(['spctl','--assess','--type','execute',str(app)])
    print('Artifact identity, architectures, icon and signature/notary checks passed' if signed else 'Unsigned artifact checks passed')

def download_existing(directory):
    trusted_main();version,build=metadata();release=release_info('v'+version)
    if not release or release['draft'] or release['prerelease']:raise ValueError('Stable release not found')
    asset=asset_for(release,version);directory.mkdir(parents=True,exist_ok=True)
    archive=directory/asset['name']
    gh('release','download','v'+version,'--repo',REPO,'--pattern',asset['name'],'--dir',str(directory))
    if sha(archive)!=asset['digest'].split(':')[1]:raise ValueError('Downloaded archive hash mismatch')
    extract(archive,directory)
    tag=gh('api',f'repos/{REPO}/commits/v{version}','--jq','.sha')
    m=dict(source_commit=tag,version=version,build=build,tag='v'+version,zip_sha256=sha(archive),automated=True,existing=True)
    (directory/'manifest.json').write_text(json.dumps(m,indent=2)+'\n')

def publish(directory):
    commit=trusted_main();version,build=metadata();m=json.loads((directory/'manifest.json').read_text())
    if (m['source_commit'],m['version'],m['build'],m['notes_sha256']) != (commit,version,build,sha(ROOT/'docs/RELEASE-NOTES.md')):
        raise ValueError('Verified artifact does not match frozen source/text')
    archive=directory/f'fuck-anthropic-guard-{version}.zip'
    if sha(archive)!=m['zip_sha256'] or m.get('notarization_status')!='Accepted':raise ValueError('Artifact not verified/notarized')
    ensure_not_older(version)
    if release_info('v'+version) or api(f'repos/{REPO}/git/ref/tags/v{version}',missing=True):
        raise ValueError('Release/tag appeared concurrently; no clobber')
    gh('release','create','v'+version,str(archive),str(directory/'manifest.json'),'--repo',REPO,
       '--target',commit,'--latest=true','--title','Guard '+version,'--notes-file',str(ROOT/'docs/RELEASE-NOTES.md'))
    actual=asset_for(release_info('v'+version),version)
    if actual['digest']!='sha256:'+m['zip_sha256']:raise ValueError('Published digest differs')

def update_cask(text, version, digest):
    version_tuple(version)
    if not re.fullmatch('[0-9a-f]{64}',digest):raise ValueError('Invalid hash')
    match=re.search(r'^  version "([^"]+)"$',text,re.M)
    if not match:raise ValueError('Cask version not found')
    old=match[1].split('-')[0]
    if version_tuple(old)>version_tuple(version):raise ValueError('Refuse tap downgrade')
    text,n=re.subn(r'^  version "[^"]+"$',f'  version "{version}"',text,count=1,flags=re.M)
    text,n=re.subn(r'^  sha256 "[a-f0-9]+"$',f'  sha256 "{digest}"',text,count=1,flags=re.M)
    if n!=1:raise ValueError('Cask SHA stanza not found')
    return text

def tap(manifest):
    trusted_main();version,build=metadata();ensure_not_older(version)
    verified=json.loads(manifest.read_text())
    if verified['version']!=version or verified['build']!=build: raise ValueError('Verified artifact version mismatch')
    release=release_info('v'+version)
    if not release or release['draft'] or release['prerelease']:raise ValueError('Tap requires a public stable release')
    asset=asset_for(release,version);digest=asset['digest'].split(':')[1]
    tag_commit=gh('api',f'repos/{REPO}/commits/v{version}','--jq','.sha')
    if digest!=verified['zip_sha256'] or tag_commit!=verified['source_commit']:
        raise ValueError('Public artifact/tag changed after verification')
    # Read public cask before requiring a write token; identical retries are no-ops.
    import base64
    path=f'repos/{TAP}/contents/Casks/fuck-anthropic-guard.rb'
    current=api(path);text=base64.b64decode(current['content']).decode();updated=update_cask(text,version,digest)
    if text==updated:print('Homebrew already matches; no mutation');return
    key=os.environ.get('HOMEBREW_TAP_SSH_KEY')
    if not key:raise ValueError('Missing HOMEBREW_TAP_SSH_KEY')
    # Verify the actual public bytes, not only API metadata.
    with tempfile.TemporaryDirectory() as tmp:
        gh('release','download','v'+version,'--repo',REPO,'--pattern',asset['name'],'--dir',tmp)
        if sha(Path(tmp)/asset['name'])!=digest:raise ValueError('Public download hash mismatch')
    ensure_not_older(version)
    with tempfile.TemporaryDirectory(prefix='guard-tap-') as tmp:
        work=Path(tmp);private=work/'key';private.write_text(key);private.chmod(0o600)
        hostkeys=api('meta')['ssh_keys']
        if not hostkeys:raise ValueError('GitHub SSH host keys unavailable')
        known=work/'known_hosts';known.write_text(''.join('github.com '+value+'\n' for value in hostkeys))
        env={**os.environ,'GIT_SSH_COMMAND':'ssh -i '+shlex.quote(str(private))+' -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile='+shlex.quote(str(known))}
        checkout=work/'tap'
        run(['git','clone','--depth','1','--branch','main',f'git@github.com:{TAP}.git',str(checkout)],env=env)
        cask=checkout/'Casks/fuck-anthropic-guard.rb'
        desired=update_cask(cask.read_text(),version,digest)
        if cask.read_text()!=desired:
            cask.write_text(desired)
            run(['git','config','user.name','Guard Release'],cwd=checkout)
            run(['git','config','user.email','guard-release@users.noreply.github.com'],cwd=checkout)
            run(['git','add','Casks/fuck-anthropic-guard.rb'],cwd=checkout)
            run(['git','commit','-m',f'Update Guard to {version}'],cwd=checkout)
            ensure_not_older(version)
            # A normal push rejects concurrent changes; never force-push.
            run(['git','push','origin','HEAD:main'],cwd=checkout,env=env)
    public=api(path)
    if base64.b64decode(public['content']).decode()!=desired:raise ValueError('Tap readback mismatch')
    print('Homebrew cask updated and verified')

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('command',choices=['plan','manifest','verify','download-existing','publish','tap','extract','restore-state','seal-unsigned']);p.add_argument('--output',type=Path);p.add_argument('--app',type=Path);p.add_argument('--manifest',type=Path);p.add_argument('--directory',type=Path,default=ROOT/'dist/ci-release');p.add_argument('--unsigned',action='store_true');p.add_argument('--archive',type=Path);a=p.parse_args()
    if a.command=='plan':plan(a.output)
    elif a.command=='manifest':make_manifest(a.app,a.output)
    elif a.command=='verify':verify(a.app,a.manifest,not a.unsigned)
    elif a.command=='download-existing':download_existing(a.directory)
    elif a.command=='publish':publish(a.directory)
    elif a.command=='extract':extract(a.archive,a.directory)
    elif a.command=='restore-state':restore_state(a.directory)
    elif a.command=='seal-unsigned':
        m=json.loads(a.manifest.read_text());m['unsigned_zip_sha256']=sha(a.archive);validate_archive(a.archive);a.manifest.write_text(json.dumps(m,indent=2)+'\n')
    else:tap(a.manifest)

if __name__=='__main__':
    try:main()
    except (ValueError,RuntimeError,subprocess.CalledProcessError) as e:
        print('Release stopped: '+(str(e) if not isinstance(e,subprocess.CalledProcessError) else 'required command failed'),file=sys.stderr)
        sys.exit(1)

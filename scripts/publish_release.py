#!/usr/bin/env python3
"""Explicit local release preparation and independent-review publication gate."""
import argparse, hashlib, json, os, pathlib, subprocess
R=pathlib.Path(__file__).resolve().parents[1]
def run(*args,**kw):return subprocess.run(args,cwd=R,check=True,**kw)
def git(*args):return subprocess.check_output(['git',*args],cwd=R,text=True).strip()
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
p=argparse.ArgumentParser();p.add_argument('--prepare',action='store_true');p.add_argument('--audit-report');p.add_argument('--source-only',action='store_true');p.add_argument('--tag',default='v0.4.0-beta.1');a=p.parse_args()
EXPECTED_ORIGIN='https://github.com/LeiZiKang/fuck-anthropic-guard.git'
def publication_target():
 branch=git('branch','--show-current')
 if not branch.startswith('codex/feature-') or branch in ['main','master']:raise SystemExit('Only a codex/feature- branch may be published.')
 if git('remote','get-url','origin')!=EXPECTED_ORIGIN or git('remote','get-url','--push','origin')!=EXPECTED_ORIGIN:raise SystemExit('Unexpected publication remote.')
 return branch
branch=publication_target()
release=R/'release';manifest=release/'candidate.json' 
if a.prepare:
 if git('status','--porcelain'):raise SystemExit('Commit source before preparing the exact candidate.')
 release.mkdir(exist_ok=True)
 env={**os.environ,'CCW_BUILD_MODE':'host','CCW_ARCHITECTURES':'arm64 x86_64','CCW_OUTPUT_ROOT':str(R/'dist/release')}
 run('bash','scripts/build.sh',env=env)
 app=R/'dist/release/fuck-anthropic guard.app'
 run(str(app/'Contents/MacOS/ClaudeConnectionWatcher'),'--self-test')
 archive=release/'fuck-anthropic-guard-0.4.0-beta.1.zip'
 def pack():
  if archive.exists():archive.unlink()
  run('/usr/bin/ditto','-c','-k','--keepParent','--sequesterRsrc',str(app),str(archive))
 pack();notarized=False
 if os.environ.get('CCW_NOTARY_PROFILE'):
  if not os.environ.get('CCW_SIGN_IDENTITY'):raise SystemExit('Notarization requires an explicit signing identity.')
  r=run('xcrun','notarytool','submit',str(archive),'--keychain-profile',os.environ['CCW_NOTARY_PROFILE'],'--wait','--output-format','json',capture_output=True,text=True)
  report=json.loads(r.stdout);(release/'notary-result.json').write_text(json.dumps(report,indent=2)+'\n')
  if report.get('status')!='Accepted':raise SystemExit('Notarization not accepted; nothing published.')
  run('xcrun','stapler','staple',str(app));run('xcrun','stapler','validate',str(app));run('/usr/sbin/spctl','-a','--type','execute',str(app));pack();notarized=True
 run('/usr/bin/codesign','--verify','--deep','--strict',str(app))
 m={'source_commit':git('rev-parse','HEAD'),'source_tree':git('rev-parse','HEAD^{tree}'),'branch':branch,'origin':EXPECTED_ORIGIN,'zip':archive.name,'zip_sha256':sha(archive),'notarized':notarized,'tap_changed':False}
 manifest.write_text(json.dumps(m,indent=2)+'\n');print(json.dumps(m));raise SystemExit(0)
if not a.audit_report:raise SystemExit('Use --prepare, then --audit-report from an independent reviewer.')
m=json.loads(manifest.read_text());review=json.loads(pathlib.Path(a.audit_report).read_text());archive=release/m['zip']
if git('status','--porcelain'):raise SystemExit('Worktree changed after preparation.')
for key in ['source_commit','source_tree','zip_sha256','branch','origin']:
 if review.get(key)!=m[key]:raise SystemExit('Audit does not match '+key)
if m['branch']!=branch:raise SystemExit('Publication branch changed.')
kind='source-only' if a.source_only else 'binary-prerelease'
if review.get('publication_kind')!=kind:raise SystemExit('Audit publication scope mismatch.')
if review.get('decision')!='pass' or not review.get('independent_reviewer') or review.get('tap_changed') is not False:raise SystemExit('Independent review and unchanged tap confirmation required.')
if git('rev-parse','HEAD')!=m['source_commit'] or sha(archive)!=m['zip_sha256']:raise SystemExit('Frozen inputs changed.')
if not a.source_only and not m['notarized']:raise SystemExit('Binary distribution requires notarization; use --source-only for reviewed source.')
run('git','push','origin','HEAD:refs/heads/'+m['branch'])
if not a.source_only:
 run('gh','release','create',a.tag,str(archive),'--target',m['source_commit'],'--prerelease','--latest=false','--title','fuck-anthropic guard 0.4.0 beta — Surge companion','--notes-file','docs/RELEASE-NOTES.md')
print('Published reviewed feature; no branch merge or tap update performed.')

#!/usr/bin/env python3
"""Offline CI release boundary tests; no secrets, network or publishing."""
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import zipfile
import stat
import plistlib
import base64
import unittest
from unittest.mock import patch
spec=importlib.util.spec_from_file_location('ci_release',Path(__file__).with_name('release.py'))
r=importlib.util.module_from_spec(spec);spec.loader.exec_module(r)
CASK='''cask "fuck-anthropic-guard" do
  version "0.4.4"
  sha256 "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
end
'''
class ReleaseTests(unittest.TestCase):
 def test_versions_are_semantic(self):
  self.assertGreater(r.version_tuple('0.10.0'),r.version_tuple('0.9.9'))
  for bad in ['v0.4.4','0.4.4-beta.1','../0.4.4','0.4.4; echo unsafe']:
   with self.assertRaises(ValueError):r.version_tuple(bad)
 def test_non_main_dispatch_is_rejected(self):
  for repo,ref,event in [(r.REPO,'refs/heads/test','workflow_dispatch'),('other/repo','refs/heads/main','push'),(r.REPO,'refs/heads/main','pull_request')]:
   with patch.dict(os.environ,dict(GITHUB_REPOSITORY=repo,GITHUB_REF=ref,GITHUB_EVENT_NAME=event),clear=True):
    with self.assertRaises(ValueError):r.trusted_main()
 def test_frozen_checkout_required(self):
  env=dict(GITHUB_REPOSITORY=r.REPO,GITHUB_REF='refs/heads/main',GITHUB_EVENT_NAME='push',GITHUB_SHA='a'*40)
  with patch.dict(os.environ,env,clear=True),patch.object(r.subprocess,'check_output',return_value='b'*40):
   with self.assertRaises(ValueError):r.trusted_main()
 def test_cask_update_preserves_other_text(self):
  changed=r.update_cask(CASK,'0.4.5','b'*64)
  self.assertIn('version "0.4.5"',changed);self.assertIn('b'*64,changed)
  self.assertEqual(r.update_cask(changed,'0.4.5','b'*64),changed)
 def test_cask_downgrade_rejected(self):
  with self.assertRaises(ValueError):r.update_cask(CASK,'0.4.3','b'*64)
 def test_invalid_hash_rejected(self):
  with self.assertRaises(ValueError):r.update_cask(CASK,'0.4.5','wrong')
 def test_duplicate_or_missing_assets_rejected(self):
  asset={'name':'fuck-anthropic-guard-0.4.4.zip','digest':'sha256:'+'a'*64}
  self.assertEqual(r.asset_for({'assets':[asset]},'0.4.4'),asset)
  for assets in [[],[asset,asset],[dict(asset,digest=None)]]:
   with self.assertRaises(ValueError):r.asset_for({'assets':assets},'0.4.4')
 def plan(self,release,ref,build='13.0',old_build=None,heading=None):
  with tempfile.TemporaryDirectory() as tmp:
   root=Path(tmp);(root/'docs').mkdir();(root/'docs/RELEASE-NOTES.md').write_text(heading or '# 0.4.4 / build '+build)
   def api(path,**kw):
    if '/git/ref/' in path:return ref
    if path.endswith('/releases/latest'):return {'tag_name':'v0.4.3'} if old_build else None
    return {'content':base64.b64encode(plistlib.dumps({'CFBundleVersion':old_build})).decode()}
   with patch.object(r,'trusted_main',return_value='a'*40),patch.object(r,'metadata',return_value=('0.4.4',build)),patch.object(r,'ensure_not_older'),patch.object(r,'release_info',return_value=release),patch.object(r,'api',side_effect=api),patch.object(r,'ROOT',root):
    p=root/'output';r.plan(p);return p.read_text()
 def test_new_version_builds(self):self.assertIn('mode=new',self.plan(None,None))
 def test_same_version_retries_existing_artifact(self):
  rel={'draft':False,'prerelease':False,'assets':[{'name':'fuck-anthropic-guard-0.4.4.zip','digest':'sha256:'+'a'*64}]}
  self.assertIn('mode=existing',self.plan(rel,{'object':{'sha':'b'*40}}))
 def test_orphan_tag_stops(self):
  with self.assertRaises(ValueError):self.plan(None,{'object':{'sha':'a'*40}})
 def test_incomplete_release_stops(self):
  for rel in [{'draft':True,'prerelease':False},{'draft':False,'prerelease':True}]:
   with self.assertRaises(ValueError):self.plan(rel,{})
 def test_latest_guard_rejects_old_run(self):
  with patch.object(r,'api',return_value={'tag_name':'v0.5.0'}):
   with self.assertRaises(ValueError):r.ensure_not_older('0.4.5')
 def run_tap(self,digest='a'*64):
  rel={'draft':False,'prerelease':False,'assets':[{'name':'fuck-anthropic-guard-0.4.4.zip','digest':'sha256:'+digest}]}
  with tempfile.TemporaryDirectory() as tmp:
   m=Path(tmp)/'manifest.json';m.write_text(json.dumps(dict(version='0.4.4',build='13.0',source_commit='c'*40,zip_sha256='a'*64)))
   with patch.dict(os.environ,{},clear=True),patch.object(r,'trusted_main'),patch.object(r,'metadata',return_value=('0.4.4','13.0')),patch.object(r,'ensure_not_older'),patch.object(r,'release_info',return_value=rel),patch.object(r,'gh',return_value='c'*40),patch.object(r,'api',return_value={'sha':'c'*40,'content':base64.b64encode(CASK.encode()).decode()}) as api:
    r.tap(m);return api.call_count
 def test_tap_noop_needs_no_write_token(self):self.assertEqual(self.run_tap(),1)
 def test_changed_public_asset_is_rejected_before_tap_write(self):
  with self.assertRaises(ValueError):self.run_tap('b'*64)
 def test_filter_build_must_increase(self):
  for old in ['13','13.0','14.0']:
   with self.assertRaises(ValueError):self.plan(None,None,old_build=old)
  self.assertIn('mode=new',self.plan(None,None,old_build='12.9'))
 def test_stale_release_notes_rejected(self):
  with self.assertRaises(ValueError):self.plan(None,None,heading='# Old notes')
 def archive(self,extra):
  with tempfile.TemporaryDirectory() as tmp:
   p=Path(tmp)/'app.zip'
   with zipfile.ZipFile(p,'w') as z:
    z.writestr(r.APP+'/Contents/Info.plist',b'plist')
    for name,symlink in extra:
     info=zipfile.ZipInfo(name)
     if symlink:info.external_attr=(stat.S_IFLNK|0o777)<<16
     z.writestr(info,b'test')
   r.validate_archive(p)
 def test_normal_archive_valid(self):self.archive([(r.APP+'/Contents/MacOS/App',False)])
 def test_archive_traversal_duplicate_and_link_rejected(self):
  for path,link in [('../secret',False),('/tmp/secret',False),('other.app/file',False),(r.APP+'/../escape',False),(r.APP+'/Contents/Info.plist',False),(r.APP+'/link',True),('__MACOSX/evil',False)]:
   with self.assertRaises(ValueError):self.archive([(path,link)])
 def test_restore_missing_expired_or_unreadable_state_stops(self):
  with patch.dict(os.environ,{'GITHUB_RUN_ID':'123'}),patch.object(r,'trusted_main'),patch.object(r,'gh') as gh:
   for data in [{'artifacts':[]},{'artifacts':[{'name':'notary-state-123','expired':True}]}]:
    with patch.object(r,'api',return_value=data):
     with self.assertRaises(ValueError):r.restore_state(Path('/not-used'))
   with patch.object(r,'api',side_effect=RuntimeError('API failed')):
    with self.assertRaises(RuntimeError):r.restore_state(Path('/not-used'))
   gh.assert_not_called()
if __name__=='__main__':unittest.main()

#!/usr/bin/env python3
"""Offline negative tests for the publication gate; no network or real publishing."""
import copy
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('publisher', Path(__file__).with_name('publish_release.py'))
publisher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(publisher)

class PublicationGateTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.notes = self.root / 'notes.md'; self.notes.write_text('Reviewed release text\n')
        self.zip = self.root / 'guard.zip'; self.zip.write_bytes(b'reviewed artifact')
        self.manifest = dict(source_commit='commit', source_tree='tree', branch='codex/feature-release',
            origin=publisher.ORIGIN, tag='v0.4.4-beta.1', app_version='0.4.4', build_version='13.0',
            zip='guard.zip', zip_sha256=publisher.sha(self.zip), release_notes_sha256=publisher.sha(self.notes),
            notarized=True, tap_changed=False)
        self.review = {k: self.manifest[k] for k in publisher.MATCH_KEYS}
        self.review.update(decision='pass', independent_reviewer='independent-test-fixture',
                           publication_kind='binary-prerelease', tap_changed=False)

    def frozen(self, manifest=None, **kwargs):
        return publisher.validate_frozen(manifest or self.manifest, self.root, self.notes,
            kwargs.get('head', 'commit'), 'tree', 'codex/feature-release', kwargs.get('tag', 'v0.4.4-beta.1'))

    def test_reviewed_inputs_pass(self):
        self.assertEqual(self.frozen(), self.zip)
        publisher.validate_review(self.review, self.manifest, False)

    def test_archive_tampering_blocks(self):
        self.zip.write_bytes(b'changed')
        with self.assertRaises(SystemExit): self.frozen()

    def test_release_text_tampering_blocks(self):
        self.notes.write_text('unreviewed words')
        with self.assertRaises(SystemExit): self.frozen()

    def test_source_moved_blocks(self):
        with self.assertRaises(SystemExit): self.frozen(head='new commit')

    def test_tag_moved_blocks(self):
        with self.assertRaises(SystemExit): self.frozen(tag='v0.4.4-beta.2')

    def test_archive_path_escape_blocks(self):
        m = dict(self.manifest, zip='../guard.zip')
        with self.assertRaises(SystemExit): self.frozen(m)

    def test_archive_symlink_blocks(self):
        self.zip.unlink(); self.zip.symlink_to(self.notes)
        with self.assertRaises(SystemExit): self.frozen()

    def test_wrong_review_digest_blocks(self):
        review = dict(self.review, zip_sha256='wrong')
        with self.assertRaises(SystemExit): publisher.validate_review(review, self.manifest, False)

    def test_missing_independent_reviewer_blocks(self):
        review = dict(self.review, independent_reviewer='')
        with self.assertRaises(SystemExit): publisher.validate_review(review, self.manifest, False)

    def test_unnotarized_binary_blocks_but_reviewed_source_can_pass(self):
        manifest = dict(self.manifest, notarized=False)
        with self.assertRaises(SystemExit): publisher.validate_review(self.review, manifest, False)
        review = dict(self.review, publication_kind='source-only')
        publisher.validate_review(review, manifest, True)

    def test_scope_and_tap_mismatch_block(self):
        for changes in [dict(publication_kind='source-only'), dict(tap_changed=True), dict(decision='fail')]:
            with self.assertRaises(SystemExit): publisher.validate_review(dict(self.review, **changes), self.manifest, False)

    def test_stable_requires_matching_channel_review(self):
        manifest = dict(self.manifest, stable=True)
        review = dict(self.review, stable=True, publication_kind='binary-stable')
        publisher.validate_review(review, manifest, False)
        with self.assertRaises(SystemExit): publisher.validate_review(self.review, manifest, False)
        with self.assertRaises(SystemExit): publisher.validate_review(dict(review, publication_kind='binary-prerelease'), manifest, False)

    def test_promotion_provenance_is_reviewed(self):
        manifest = dict(self.manifest, stable=True, reused_from_tag='v0.4.4-beta.1', artifact_source_commit='original')
        review = dict(self.review, stable=True, publication_kind='binary-stable', reused_from_tag='v0.4.4-beta.1', artifact_source_commit='original')
        publisher.validate_review(review, manifest, False)
        for key in ('reused_from_tag', 'artifact_source_commit'):
            with self.assertRaises(SystemExit): publisher.validate_review(dict(review, **{key:'changed'}), manifest, False)

    def reuse(self, manifest=None, changes='docs/RELEASE-NOTES.md', source='commit'):
        with patch.object(publisher, 'git', side_effect=[source, changes]):
            return publisher.reuse_candidate(manifest or self.manifest, self.root, 'v0.4.4-beta.1', '0.4.4', '13.0', 'head')

    def test_unchanged_notarized_binary_can_be_promoted(self):
        self.assertEqual(self.reuse(), (self.zip, 'commit'))

    def test_runtime_changes_block_reuse(self):
        for changes in ('Sources/FilterController.swift', 'Info.plist', 'scripts/build.sh', 'Guard/Shared/ProcessIdentity.swift'):
            with self.assertRaises(SystemExit): self.reuse(changes=changes)

    def test_original_tag_moved_blocks_reuse(self):
        with self.assertRaises(SystemExit): self.reuse(source='moved')

    def test_unnotarized_or_different_version_blocks_reuse(self):
        for delta in ({'notarized':False}, {'app_version':'0.4.5'}, {'build_version':'14.0'}, {'origin':'wrong'}):
            with self.assertRaises(SystemExit): self.reuse(dict(self.manifest, **delta))

    def test_source_zip_tampering_blocks_reuse(self):
        self.zip.write_bytes(b'tampered')
        with self.assertRaises(SystemExit): self.reuse()

    def test_tag_matches_app_version(self):
        self.assertEqual(publisher.release_tag('0.4.4', None), 'v0.4.4-beta.1')
        for bad in ['v0.4.0-beta.1', '../v0.4.4', 'v0.4.4; echo bad']:
            with self.assertRaises(SystemExit): publisher.release_tag('0.4.4', bad)

if __name__ == '__main__': unittest.main()

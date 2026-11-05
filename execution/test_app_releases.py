"""Release publication tests use temporary files only, never the app database."""
import io
import json
from pathlib import Path
import sys
import tarfile
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
from prepare_app_release import sha256, verify_web, ROOT
from publish_app_release import read_bundle, publish


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(dir=ROOT / '.tmp')
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.artifact = self.base / 'artifact'
        self.artifact.mkdir()
        self.root, self.web = self.base / 'releases', self.base / 'current'

    def web_record(self, build=2):
        release_id = f'web-1-0-1-{build}-test'
        for name in ['index.html', 'main.dart.js', 'assets/FontManifest.json', 'assets/AssetManifest.bin.json',
                     'manifest.json', 'icons/Icon-192.png']:
            path = self.artifact / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('{}')
        (self.artifact / 'flutter_service_worker.js').write_bytes((ROOT / 'deployment/web/retire_flutter_service_worker.js').read_bytes())
        (self.artifact / 'flutter_bootstrap.js').write_text(f'entrypointBaseUrl assetBase /releases/web/{release_id}/')
        (self.artifact / 'index.html').write_text("searchParams.set('startup', Date.now())")
        return {'schema_version': 1, 'platform': 'web', 'release': {
            'release_id': release_id, 'version': '1.0.1', 'build': build}}

    def test_preview_validates_without_creating_release_storage(self):
        report = publish(self.web_record(), self.artifact, self.root, self.web)
        self.assertFalse(report['apply'])
        self.assertFalse(self.root.exists())

    def test_worker_must_be_retired_in_release(self):
        self.web_record()
        (self.artifact / 'flutter_service_worker.js').write_text('old cache-first worker')
        with self.assertRaises(ValueError):
            verify_web(self.artifact)

    def test_release_rejects_startup_that_can_be_served_from_legacy_cache(self):
        self.web_record()
        (self.artifact / 'index.html').write_text('<script src="flutter_bootstrap.js"></script>')
        with self.assertRaisesRegex(ValueError, 'cached legacy bootstrap'):
            verify_web(self.artifact)

    def test_traversal_and_links_are_rejected_before_extraction(self):
        for name in ['../escape', '/escape']:
            archive = self.base / 'bad.tar.gz'
            with tarfile.open(archive, 'w:gz') as bundle:
                member = tarfile.TarInfo(name)
                member.size = 1
                bundle.addfile(member, io.BytesIO(b'x'))
            with self.assertRaises(ValueError):
                read_bundle(archive, self.base / 'unpack')
        self.assertFalse((self.base.parent / 'escape').exists())

    def test_android_publication_preserves_web_and_rejects_downgrades(self):
        (self.root / 'metadata').mkdir(parents=True)
        web = {'build': 5, 'release_id': 'web-5', 'version': '1.0.0'}
        (self.root / 'metadata/latest.json').write_text(json.dumps({'schema_version': 1, 'web': web}))
        apk = self.artifact / 'DefenSYS-1.0.1-2.apk'
        apk.write_bytes(b'APK fixture')
        record = {'schema_version': 1, 'platform': 'android', 'release': {
            'available': True, 'release_id': 'android-2', 'build': 2, 'version': '1.0.1',
            'application_id': 'com.example.user', 'signing_sha256': 'a' * 64,
            'download_url': 'https://defensys.site/releases/android/' + apk.name,
            'sha256': sha256(apk), 'size_bytes': apk.stat().st_size}}
        publish(record, self.artifact, self.root, self.web, True)
        latest = json.loads((self.root / 'metadata/latest.json').read_text())
        self.assertEqual(latest['web'], web)
        self.assertTrue((self.root / 'android' / apk.name).exists())
        with self.assertRaises(ValueError):
            publish(record, self.artifact, self.root, self.web, True)
        self.assertFalse(self.web.exists())

    def test_atomic_web_switch_preserves_previous_directory_and_metadata_on_failure(self):
        record = self.web_record()
        self.web.mkdir()
        (self.web / 'old.txt').write_text('keep old deployment')
        # Windows test hosts can lack symlink privileges; production is Ubuntu.
        probe = self.base / 'probe'
        try:
            probe.symlink_to(self.artifact, target_is_directory=True)
            probe.unlink()
        except OSError:
            self.skipTest('Host does not permit symbolic links.')
        with patch('publish_app_release.atomic_json', side_effect=OSError('disk full')):
            with self.assertRaises(OSError):
                publish(record, self.artifact, self.root, self.web, True)
        self.assertFalse(self.web.is_symlink())
        self.assertEqual((self.web / 'old.txt').read_text(), 'keep old deployment')
        self.assertFalse((self.root / 'metadata/latest.json').exists())
        # Retrying an interrupted publication reuses only byte-identical staged files.
        publish(record, self.artifact, self.root, self.web, True)
        self.assertTrue(self.web.is_symlink())
        self.assertEqual(json.loads((self.root / 'metadata/latest.json').read_text())['web']['build'], 2)


if __name__ == '__main__':
    unittest.main()

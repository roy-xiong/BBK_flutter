import hashlib
import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('publisher', Path(__file__).parents[1] / 'publish_release.py')
publisher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(publisher)


class ReleaseTests(unittest.TestCase):
    def test_notes_use_only_built_version_and_include_direct_download_links(self):
        history = '## 未发布\n\n- 未来修改\n\n## 1.0.7+8\n\n- 修复熄灯和倍速\n\n## 1.0.6+7\n\n- 旧版本\n'
        changes = publisher.version_changes(history, '1.0.7', '8')
        self.assertEqual(changes, '- 修复熄灯和倍速')
        with self.assertRaises(ValueError):
            publisher.version_changes(history, '1.0.8', '9')
        names = [Path('BBK-Flutter-macOS-1.0.7-build.8.dmg'), Path('BBK-Flutter-macOS-1.0.7-build.8.zip'), Path('SHA256SUMS.txt')]
        notes = publisher.release_notes('roy-xiong/BBK_flutter', 'v1.0.7-build.8', '1.0.7', '8', ['macos'], changes, names, 'https://example.invalid/run', 'a' * 40)
        self.assertIn('步步高经典游戏2', notes)
        self.assertIn('/releases/download/v1.0.7-build.8/BBK-Flutter-macOS-1.0.7-build.8.dmg', notes)
        self.assertNotIn('未来修改', notes)

    def test_uses_version_commit_instead_of_trigger_commit(self):
        commits = [{'sha':'b'*40,'parents':[{'sha':'a'*40}], 'commit':{'message':'chore: package 1.0.6+7 [skip ci]'}}]
        self.assertEqual(publisher.build_commit(commits,'a'*40,'1.0.6','7'),'b'*40)
        with self.assertRaises(ValueError):
            publisher.build_commit(commits,'c'*40,'1.0.6','7')

    def test_rejects_failure_and_foreign_repository(self):
        run = {'status':'completed','conclusion':'success','head_branch':'main','head_repository':{'full_name':'roy-xiong/BBK_flutter'},'path':'.github/workflows/packages.yml','event':'workflow_dispatch'}
        publisher.validate_run(run,'roy-xiong/BBK_flutter')
        with self.assertRaises(ValueError):
            publisher.validate_run(dict(run,conclusion='failure'),'roy-xiong/BBK_flutter')
        with self.assertRaises(ValueError):
            publisher.validate_run(run,'other/repository')

    def test_mac_packages_must_match_all_checksums(self):
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary)
            names=[f'BBK-Flutter-macOS-1.0.6+7.{suffix}' for suffix in ['dmg','zip']]
            for name in names:(root/name).write_bytes(name.encode())
            (root/'SHA256SUMS.txt').write_text(''.join(hashlib.sha256((root/name).read_bytes()).hexdigest()+'  '+name+'\n' for name in names))
            self.assertEqual(len(publisher.verify_artifact(root,'macos','1.0.6','7')),2)
            (root/names[0]).write_bytes(b'tampered')
            with self.assertRaises(ValueError):publisher.verify_artifact(root,'macos','1.0.6','7')


if __name__ == '__main__':
    unittest.main()

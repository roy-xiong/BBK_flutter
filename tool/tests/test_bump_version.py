"""在临时工程验证连续打包递增版本、归档变更，避免污染工作区。"""
from pathlib import Path
import subprocess
import tempfile
import unittest


class VersionTests(unittest.TestCase):
    def test_each_package_bumps_both_numbers_and_archives_only_pending_notes(self):
        script = Path(__file__).parents[1] / 'bump_version.py'
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / 'pubspec.yaml').write_text('name: test\nversion: 1.0.6+7\n')
            (root / 'CHANGELOG.md').write_text('# 更新\n\n## 未发布\n\n- 灯洞修复\n\n## 1.0.6+7\n\n- 旧版本\n')
            subprocess.run(['python3', str(script), '--test'], cwd=root, check=True, capture_output=True)
            self.assertIn('version: 1.0.7+8', (root / 'pubspec.yaml').read_text())
            self.assertIn('## 1.0.7+8\n\n- 灯洞修复', (root / 'CHANGELOG.md').read_text())
            subprocess.run(['python3', str(script), '--test'], cwd=root, check=True, capture_output=True)
            self.assertIn('version: 1.0.8+9', (root / 'pubspec.yaml').read_text())
            self.assertIn('## 1.0.8+9\n\n- 重新打包当前版本', (root / 'CHANGELOG.md').read_text())
            self.assertEqual((root / 'CHANGELOG.md').read_text().count('- 灯洞修复'), 1)


if __name__ == '__main__':
    unittest.main()

"""每次手动打包递增版本，确保所有平台引用同一提交和版本。"""
from pathlib import Path
import os
import re

path = Path('pubspec.yaml')
source = path.read_text(encoding='utf-8')
match = re.search(r'^version: (\d+)\.(\d+)\.(\d+)\+(\d+)$', source, re.M)
if match is None:
    raise SystemExit('pubspec.yaml 的版本格式无效')
major, minor, patch, build = map(int, match.groups())
version = f'{major}.{minor}.{patch + 1}'
build += 1
path.write_text(source[:match.start()] + f'version: {version}+{build}' + source[match.end():], encoding='utf-8')
output = os.environ.get('GITHUB_OUTPUT')
if output:
    with open(output, 'a', encoding='utf-8') as stream:
        stream.write(f'version={version}\nbuild={build}\n')
print(f'打包版本：{version}+{build}')

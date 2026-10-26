"""核对随合集导入的资源，以及未经语义改动的两个 Dart 游戏引擎。"""
from pathlib import Path
import hashlib
import json

snapshot = json.loads(Path('tool/source_snapshot.json').read_text())
count = 0
for item in snapshot['files']:
    path = Path(item['destination'])
    if not path.is_file():
        raise SystemExit(f'导入文件缺失：{path}')
    if str(path).startswith('assets/') or '/engine/' in str(path):
        if hashlib.sha256(path.read_bytes()).hexdigest() != item['importedSha256']:
            raise SystemExit(f'导入资源或引擎与整合快照不一致：{path}')
        count += 1
if any(Path('lib').rglob('*.js')) or any(Path('assets').rglob('*.wasm')):
    raise SystemExit('纯 Flutter 合集不能带入 WebView 游戏运行时')
print(f'源项目快照校验通过：{count} 个游戏资源及引擎文件')

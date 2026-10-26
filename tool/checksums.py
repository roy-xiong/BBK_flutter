"""为本次分发的所有产物生成 SHA-256 文件。"""
from pathlib import Path
import hashlib
import sys
directory = Path(sys.argv[1])
records = []
for path in sorted(directory.iterdir()):
    if path.is_file() and path.name != 'SHA256SUMS.txt':
        records.append(hashlib.sha256(path.read_bytes()).hexdigest() + '  ' + path.name)
(directory / 'SHA256SUMS.txt').write_text('\n'.join(records) + '\n', encoding='utf-8')

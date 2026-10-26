"""Release 必须使用仓库记录的固定证书，避免测试缓存丢失后签名变化。"""
from pathlib import Path
import os
import re
import subprocess
import sys

sdk = Path(os.environ['ANDROID_HOME'])
signer = sdk / 'build-tools/36.0.0/apksigner'
apk = Path(sys.argv[1])
result = subprocess.check_output([str(signer), 'verify', '--print-certs', str(apk)], text=True)
match = re.search(r'Signer #1 certificate SHA-256 digest: ([0-9a-fA-F]+)', result)
expected = Path('android/signing/certificate.sha256').read_text().strip().lower()
if match is None or match.group(1).lower() != expected:
    raise SystemExit('APK 证书与项目固定证书不一致')
print('APK 固定证书 SHA-256 校验通过')

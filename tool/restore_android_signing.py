"""从仓库专属 Actions Secret 恢复固定签名，不将私钥或口令写入日志。"""
from pathlib import Path
import base64
import json
import os

secret = os.environ.get('BBK_ANDROID_SIGNING')
if not secret:
    raise SystemExit('缺少 BBK_ANDROID_SIGNING，拒绝使用临时或随机签名')
data = json.loads(secret)
required = ('keystore', 'alias', 'storePassword', 'keyPassword')
if any(not isinstance(data.get(key), str) or not data[key] for key in required):
    raise SystemExit('固定签名配置不完整')
for key in required[1:]:
    if any(character in data[key] for character in '\r\n\\'):
        raise SystemExit('固定签名属性包含无效字符')
directory = Path('.signing')
directory.mkdir(mode=0o700, exist_ok=True)
store = directory / 'android-release.jks'
store.write_bytes(base64.b64decode(data['keystore'], validate=True))
store.chmod(0o600)
properties = Path('android/key.properties')
properties.write_text('storeFile=../.signing/android-release.jks\nkeyAlias=' + data['alias'] + '\nstorePassword=' + data['storePassword'] + '\nkeyPassword=' + data['keyPassword'] + '\n', encoding='utf-8')
properties.chmod(0o600)
print('已恢复项目专属固定 Android 签名')

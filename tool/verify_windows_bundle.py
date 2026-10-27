"""打包前验证真实PE、中文标题、运行库和两款游戏资源，错误产物不允许发布。"""
from pathlib import Path
import hashlib
import json
import struct
import sys


def verify_executable(data, version, build):
    """检查实际二进制，既核对RC中的产品名，也排除C++窗口标题的代码页乱码。"""
    if data[:2] != b'MZ':
        raise ValueError('Windows程序缺少MZ头')
    offset = struct.unpack_from('<I', data, 0x3c)[0]
    if data[offset:offset + 4] != b'PE\0\0' or struct.unpack_from('<H', data, offset + 4)[0] != 0x8664:
        raise ValueError('Windows程序不是有效x64 PE')
    name = '步步高经典游戏2'.encode('utf-16le') + b'\0\0'
    broken = 'æ\xad¥æ\xad¥'.encode('utf-16le')
    if data.count(name) < 3 or broken in data:
        raise ValueError('Windows原生窗口标题被错误代码页编译为乱码')
    at = data.find(b'\xbd\x04\xef\xfe')
    if at < 0:
        raise ValueError('Windows版本资源缺失')
    ms, ls = struct.unpack_from('<II', data, at + 8)
    actual = (ms >> 16, ms & 65535, ls >> 16, ls & 65535)
    expected = tuple(map(int, version.split('.'))) + (int(build),)
    if actual != expected:
        raise ValueError(f'Windows内部版本错误：{actual} != {expected}')
    return actual


def main():
    folder, version, build = Path(sys.argv[1]), sys.argv[2], sys.argv[3]
    actual = verify_executable((folder / '步步高经典游戏2.exe').read_bytes(), version, build)
    for name in ['flutter_windows.dll', 'vcruntime140.dll', 'vcruntime140_1.dll', 'msvcp140.dll', 'data/icudtl.dat', 'data/app.so', '开始游戏.txt']:
        if not (folder / name).is_file() or (folder / name).stat().st_size == 0:
            raise ValueError('缺少Windows运行文件：' + name)
    root = Path(__file__).resolve().parents[1]
    # 字体在 fonts 声明下，不会被 assets 目录扫描自动覆盖，单独核对真实包内容。
    font = Path('assets/fonts/NotoSansCJKsc-Regular.otf')
    if hashlib.sha256((folder / 'data/flutter_assets' / font).read_bytes()).digest() != hashlib.sha256((root / font).read_bytes()).digest():
        raise ValueError('Windows中文字体缺失或不一致')
    manifest = json.loads((folder / 'data/flutter_assets/FontManifest.json').read_text(encoding='utf-8'))
    if not any(row.get('family') == 'BBK CJK' and any(item.get('asset') == font.as_posix() for item in row['fonts']) for row in manifest):
        raise ValueError('Windows字体清单未绑定统一中文字体')
    directories = [line.strip()[2:] for line in (root / 'pubspec.yaml').read_text(encoding='utf-8').splitlines() if line.strip().startswith(('- assets/', '- licenses/'))]
    checked = 0
    for directory in directories:
        for original in (root / directory).iterdir():
            if not original.is_file() or original.name.startswith('.'):continue
            relative = original.relative_to(root)
            packaged = folder / 'data/flutter_assets' / relative
            if not packaged.is_file() or hashlib.sha256(packaged.read_bytes()).digest() != hashlib.sha256(original.read_bytes()).digest():
                raise ValueError('Windows包内资源不一致：' + str(relative))
            checked += 1
    print(json.dumps(dict(version='.'.join(map(str, actual)), architecture='x64', nativeChineseTitle='verified', resources=checked, runtimeFiles='complete'), ensure_ascii=False))


if __name__ == '__main__':main()

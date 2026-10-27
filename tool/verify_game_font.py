"""用原始 cmap 检查真实字体覆盖，不以主题里写了 fontFamily 代替字形验证。"""
from pathlib import Path
import hashlib
import json
import struct

FONT = Path('assets/fonts/NotoSansCJKsc-Regular.otf')
SHA256 = '2c76254f6fc379fddfce0a7e84fb5385bb135d3e399294f6eeb6680d0365b74b'


def unicode_points(data):
    tables = struct.unpack_from('>H', data, 4)[0]
    for index in range(tables):
        tag, _, offset, _ = struct.unpack_from('>4sIII', data, 12 + 16 * index)
        if tag == b'cmap':
            break
    else:
        raise ValueError('缺少 cmap')
    count = struct.unpack_from('>H', data, offset + 2)[0]
    result = set()
    for index in range(count):
        platform, encoding, relative = struct.unpack_from('>HHI', data, offset + 4 + 8 * index)
        if platform != 0 and not (platform == 3 and encoding in (1, 10)):
            continue
        at = offset + relative
        if struct.unpack_from('>H', data, at)[0] != 12:
            continue
        groups = struct.unpack_from('>I', data, at + 12)[0]
        for group in range(groups):
            first, last, glyph = struct.unpack_from('>III', data, at + 16 + 12 * group)
            result.update(range(first + (glyph == 0), last + 1))
    if not result:
        raise ValueError('字体 Unicode cmap 12 缺失')
    return result


def main():
    data = FONT.read_bytes()
    if hashlib.sha256(data).hexdigest() != SHA256:
        raise ValueError('字体不是已经审核的原始字体')
    points = unicode_points(data)
    corpus = ''.join(p.read_text(encoding='utf-8') for p in Path('lib').rglob('*.dart'))
    for name in ['FmjGuideData.json', 'FmjStageData.json', 'gbk.json']:
        corpus += json.dumps(json.loads(Path('assets/fmj/game', name).read_text()), ensure_ascii=False)
    # 所有界面、对白、物品、人物名与原 GBK 中文编码表均应由同一份字体覆盖。
    required = {ord(c) for c in corpus if 0x3400 <= ord(c) <= 0x9fff}
    required.update(range(0x20, 0x7f))
    required.update(map(ord, '，。！？：；“”‘’（）【】《》、·…—'))
    missing = sorted(required - points)
    if missing:
        raise ValueError('正文字符会发生字体回退：' + ''.join(map(chr, missing)))
    print(json.dumps({'font': FONT.name, 'unicodeGlyphs': len(points),
                      'requiredGlyphs': len(required), 'missing': 0,
                      'sha256': SHA256}, ensure_ascii=False))


if __name__ == '__main__':
    main()

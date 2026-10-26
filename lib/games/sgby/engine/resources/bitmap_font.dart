import 'dart:collection';
import 'dart:typed_data';

import 'baye_picture.dart';

/// 固定字模仓库。Android参考字模可选，缺少时使用原引擎12点阵字体。
///
/// 字体回退仅保障文本可读，不代表已通过Android像素对照。字模解码结果使用
/// 有界LRU缓存，避免长时间查询全部武将时无限增长。
final class BitmapFont {
  BitmapFont(Uint8List fallback, {Uint8List? androidAtlas})
    : _fallback = Uint8List.fromList(fallback).asUnmodifiableView() {
    if (_fallback.length < 94 * 94 * 18) {
      throw const FormatException('原版字库不完整');
    }
    if (androidAtlas != null) _readAtlas(androidAtlas);
  }

  final Uint8List _fallback;
  final Map<int, BayeBitmap> _android = <int, BayeBitmap>{};
  final LinkedHashMap<int, BayeBitmap> _cache =
      LinkedHashMap<int, BayeBitmap>();
  bool get usesAndroidReference => _android.isNotEmpty;

  /// SGFT字库由参考设备采集，逐字保存GBK内码、尺寸和1bpp平面。
  void _readAtlas(Uint8List bytes) {
    if (bytes.length < 8 || String.fromCharCodes(bytes.take(4)) != 'SGFT') {
      throw const FormatException('Android字模头部无效');
    }
    final data = ByteData.sublistView(bytes);
    if (data.getUint16(4, Endian.little) != 1) {
      throw const FormatException('Android字模版本不支持');
    }
    final count = data.getUint16(6, Endian.little);
    var offset = 8;
    for (var i = 0; i < count; i++) {
      if (offset > bytes.length - 6) {
        throw const FormatException('Android字模索引越界');
      }
      final code = data.getUint16(offset, Endian.little);
      final width = bytes[offset + 2];
      final height = bytes[offset + 3];
      final length = data.getUint16(offset + 4, Endian.little);
      offset += 6;
      if ((width != 24 && width != 48) ||
          height != 48 ||
          length != ((width + 7) ~/ 8) * height ||
          length > bytes.length - offset) {
        throw const FormatException('Android字模尺寸或长度无效');
      }
      _android[code] = _bitmap(
        width,
        height,
        bytes.sublist(offset, offset + length),
      );
      offset += length;
    }
    if (offset != bytes.length) throw const FormatException('Android字模含额外数据');
  }

  /// 返回4X字模；ASCII保留6逻辑点宽度，汉字保留12逻辑点宽度。
  BayeBitmap glyph(int code) {
    final reference = _android[code];
    if (reference != null) return reference;
    final cached = _cache.remove(code);
    if (cached != null) {
      _cache[code] = cached;
      return cached;
    }
    final ascii = code < 256;
    final width = ascii ? 24 : 48;
    final output = Uint8List(width ~/ 8 * 48);
    var encoded = code;
    if (ascii) encoded = (0xa4 << 8) | (code - 0x21 + 0xa1);
    final zone = (encoded >> 8) - 0xa1;
    final position = (encoded & 255) - 0xa1;
    final offset = (zone * 94 + position) * 18;
    if (code > 32 &&
        zone >= 0 &&
        position >= 0 &&
        position < 94 &&
        offset >= 0 &&
        offset + 18 <= _fallback.length) {
      for (var y = 0; y < 48; y++) {
        for (var x = 0; x < width; x++) {
          final bit = (y ~/ 4) * 12 + x ~/ 4;
          if ((_fallback[offset + bit ~/ 8] & (0x80 >> (bit & 7))) != 0) {
            output[y * (width ~/ 8) + x ~/ 8] |= 0x80 >> (x & 7);
          }
        }
      }
    }
    final result = _bitmap(width, 48, output);
    _cache[code] = result;
    if (_cache.length > 512) _cache.remove(_cache.keys.first);
    return result;
  }

  BayeBitmap _bitmap(int width, int height, List<int> pixels) {
    final bytes = Uint8List(7 + pixels.length);
    final header = ByteData.sublistView(bytes);
    header.setUint16(0, width, Endian.little);
    header.setUint16(2, height, Endian.little);
    header.setUint16(4, 1, Endian.little);
    bytes.setRange(7, bytes.length, pixels);
    final picture = BayePictureGroup.decode(bytes).picture(0);
    if (picture == null) throw const FormatException('字模图片缺失');
    return picture;
  }
}

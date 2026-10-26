import 'dart:typed_data';

/// 基于固定码表的GBK编解码器。码表随应用内置，不依赖平台默认字符集。
final class GbkCodec {
  GbkCodec(Uint8List table) {
    if (table.length != 65536 * 2) {
      throw const FormatException('GBK码表长度无效');
    }
    final view = ByteData.sublistView(table);
    _decode = Uint16List(65536);
    for (var i = 0; i < 65536; i++) {
      final value = view.getUint16(i * 2, Endian.little);
      _decode[i] = value;
      if (value != 0) _encode.putIfAbsent(value, () => i);
    }
  }

  late final Uint16List _decode;
  final Map<int, int> _encode = <int, int>{};

  /// 解码零结尾字符串；不完整双字节用替代字符显示，避免越界读取。
  ///
  /// 精修资源的A2FD/A2FE属于GBK扩展区，标准CP936码表没有对应Unicode。
  /// 将完整但未映射的内码暂存到平面15私用区，确保文字经过选择表、截取和
  /// 再编码后仍能取回手机采集的原始字模，不会退化成两个问号。
  String decode(List<int> bytes) {
    final output = StringBuffer();
    for (var i = 0; i < bytes.length; i++) {
      final first = bytes[i];
      if (first == 0) break;
      if (first < 128) {
        output.writeCharCode(first);
        continue;
      }
      if (i + 1 >= bytes.length) {
        output.writeCharCode(0xfffd);
        break;
      }
      final code = (first << 8) | bytes[++i];
      final unicode = _decode[code];
      output.writeCharCode(unicode == 0 ? 0xf0000 + code : unicode);
    }
    return output.toString();
  }

  /// 编码游戏文本；缺字回退为问号，不把UTF-16截断为错误的游戏内码。
  Uint8List encode(String text) {
    final output = BytesBuilder(copy: false);
    for (final rune in text.runes) {
      if (rune < 128) {
        output.addByte(rune);
      } else {
        final code = rune >= 0xf0000 && rune <= 0xfffff
            ? rune - 0xf0000
            : _encode[rune];
        if (code == null) {
          output.addByte(63);
        } else {
          output.add(<int>[code >> 8, code & 255]);
        }
      }
    }
    return output.takeBytes();
  }
}

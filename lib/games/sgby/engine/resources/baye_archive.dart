import 'dart:typed_data';

/// 原游戏 RCHEAD/RIDX 资源库。资源号及条目号均从 1 开始。
///
/// 构造时复制源数据并检查全部资源边界。倍率槽 17 保存数值而非文件偏移，
/// 必须独立识别；不能把任意越界偏移当作倍率，掩盖资源损坏。
final class BayeArchive {
  BayeArchive(Uint8List source)
    : _bytes = Uint8List.fromList(source).asUnmodifiableView() {
    if (_bytes.length < 4) throw const FormatException('资源索引不完整');
    final data = ByteData.sublistView(_bytes);
    final tableLength = data.getUint32(0, Endian.little);
    if (tableLength < 4 ||
        tableLength % 4 != 0 ||
        tableLength > _bytes.length) {
      throw const FormatException('资源索引长度无效');
    }
    slotCount = tableLength ~/ 4;
    for (var id = 1; id <= slotCount; id++) {
      final offset = data.getUint32((id - 1) * 4, Endian.little);
      if (offset == 0xffffffff) continue;
      if (id == 17 && offset >= 1 && offset <= 16) {
        scale = offset;
        continue;
      }
      if (offset < tableLength || offset > _bytes.length - 14) {
        throw FormatException('资源 $id 的头部越界');
      }
      final length = data.getUint32(offset, Endian.little);
      final storedId = data.getUint16(offset + 4, Endian.little);
      if (storedId != id || length < 14 || length > _bytes.length - offset) {
        throw FormatException('资源 $id 的标识或长度无效');
      }
      final resource = BayeResource._(
        id,
        Uint8List.sublistView(_bytes, offset, offset + length),
      );
      resource._validate();
      _resources[id] = resource;
    }
  }

  final Uint8List _bytes;
  final Map<int, BayeResource> _resources = <int, BayeResource>{};
  late final int slotCount;
  int scale = 1;

  /// 返回只读的资源号集合，倍率槽不属于可读取资源。
  Iterable<int> get resourceIds => _resources.keys;

  /// 资源缺失时返回空值；损坏资源在构造阶段报告明确错误。
  BayeResource? resource(int id) => _resources[id];

  /// 返回解密后的独立字节副本，调用方修改不会污染归档或其他会话。
  Uint8List? item(int id, [int index = 1]) => _resources[id]?.item(index);
}

/// 单个资源的只读头部与条目索引。
final class BayeResource {
  BayeResource._(this.id, this._raw);

  final int id;
  final Uint8List _raw;
  ByteData get _data => ByteData.sublistView(_raw);
  int get itemCount => _data.getUint16(6, Endian.little);
  int get itemLength => _data.getUint32(8, Endian.little);
  int get encryptionKey => _raw[12];
  int get byteLength => _raw.length;

  void _validate() {
    if (itemLength != 0) {
      if (itemLength * itemCount > _raw.length - 14) {
        throw FormatException('资源 $id 的定长条目越界');
      }
      return;
    }
    if (itemCount == 0) return;
    final indexEnd = 14 + itemCount * 8;
    if (indexEnd > _raw.length) {
      throw FormatException('资源 $id 的 RIDX 索引越界');
    }
    for (var index = 0; index < itemCount; index++) {
      final offset = _data.getUint32(14 + index * 8, Endian.little);
      final length = _data.getUint32(18 + index * 8, Endian.little);
      if (offset < indexEnd ||
          offset > _raw.length ||
          length > _raw.length - offset) {
        throw FormatException('资源 $id 的第 ${index + 1} 个条目越界');
      }
    }
  }

  /// 读取条目。零条目资源用于整段字符串或引擎脚本，仅允许读取编号 1。
  Uint8List? item(int index) {
    if (index < 1 || index > (itemCount == 0 ? 1 : itemCount)) return null;
    final int start;
    final int length;
    if (itemCount == 0) {
      start = 14;
      length = _raw.length - 14;
    } else if (itemLength != 0) {
      start = 14 + (index - 1) * itemLength;
      length = itemLength;
    } else {
      start = _data.getUint32(14 + (index - 1) * 8, Endian.little);
      length = _data.getUint32(18 + (index - 1) * 8, Endian.little);
    }
    return Uint8List.fromList(<int>[
      for (var i = start; i < start + length; i++)
        (_raw[i] - encryptionKey) & 0xff,
    ]);
  }
}

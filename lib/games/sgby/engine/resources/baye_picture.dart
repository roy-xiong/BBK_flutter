import 'dart:typed_data';

/// 原版 PictureHeadType 图片组。正文按行对齐，每个像素占 1 bit。
///
/// 有遮罩时每张图片依次保存 mask plane、data plane。mask 中的 1 保留
/// 背景，data 中的 1 写入前景，不能直接把 mask 当作 PNG 的 alpha。
final class BayePictureGroup {
  BayePictureGroup._(
    this._bytes, {
    required this.width,
    required this.height,
    required this.count,
    required this.flags,
    required this.byteLength,
  });

  factory BayePictureGroup.decode(Uint8List bytes, {int offset = 0}) {
    if (offset < 0 || offset > bytes.length - 7) {
      throw const FormatException('图片头部越界');
    }
    final data = ByteData.sublistView(bytes);
    final width = data.getUint16(offset, Endian.little);
    final height = data.getUint16(offset + 2, Endian.little);
    final count = data.getUint16(offset + 4, Endian.little);
    final flags = bytes[offset + 6];
    final mask = flags & 1;
    if (width == 0 ||
        height == 0 ||
        count == 0 ||
        width > 4096 ||
        height > 4096) {
      throw const FormatException('图片尺寸或数量无效');
    }
    final length = 7 + ((width + 7) ~/ 8) * height * count * (mask + 1);
    if (length > bytes.length - offset) {
      throw const FormatException('图片平面越界');
    }
    return BayePictureGroup._(
      Uint8List.fromList(
        bytes.sublist(offset, offset + length),
      ).asUnmodifiableView(),
      width: width,
      height: height,
      count: count,
      flags: flags,
      byteLength: length,
    );
  }

  final int width;
  final int height;
  final int count;

  /// 只用最低位判断遮罩，兵种资源的 0x11 等高位标志需要原样保留。
  final int flags;
  bool get masked => (flags & 1) != 0;
  final int byteLength;
  final Uint8List _bytes;
  int get stride => (width + 7) ~/ 8;

  /// 图片编号从 0 开始；资源条目编号由归档层负责，二者不能混用。
  BayeBitmap? picture(int index) {
    if (index < 0 || index >= count) return null;
    final planeLength = stride * height;
    final offset = 7 + index * planeLength * (masked ? 2 : 1);
    return BayeBitmap._(
      width,
      height,
      masked
          ? Uint8List.sublistView(_bytes, offset, offset + planeLength)
          : null,
      Uint8List.sublistView(
        _bytes,
        offset + (masked ? planeLength : 0),
        offset + (masked ? planeLength * 2 : planeLength),
      ),
    );
  }
}

/// 只读二值位图。将遮罩与像素分别保留，支持原版 AND/OR 合成。
final class BayeBitmap {
  BayeBitmap._(this.width, this.height, this.mask, this.data);

  final int width;
  final int height;
  final Uint8List? mask;
  final Uint8List data;

  int _bit(Uint8List plane, int x, int y) =>
      (plane[y * ((width + 7) ~/ 8) + x ~/ 8] >> (7 - (x & 7))) & 1;

  /// 坐标越界时视作背景，绘制调用仍应在目标画布内裁剪。
  bool inkAt(int x, int y) =>
      x >= 0 && y >= 0 && x < width && y < height && _bit(data, x, y) != 0;

  /// mask 为 1 时保留原背景；无 mask 的图片会覆盖整个矩形。
  bool preservesAt(int x, int y) {
    final plane = mask;
    return plane != null &&
        x >= 0 &&
        y >= 0 &&
        x < width &&
        y < height &&
        _bit(plane, x, y) != 0;
  }
}

/// 原版 SPERES 动画资源；保留每帧清除延时、推进延时和图片编号。
final class BayeAnimation {
  BayeAnimation._(this.startFrame, this.endFrame, this.frames, this.pictures);

  factory BayeAnimation.decode(Uint8List bytes) {
    if (bytes.length < 6) throw const FormatException('动画头部不完整');
    final frameCount = bytes[2];
    final pictureCount = bytes[3];
    var offset = 6 + frameCount * 5;
    if (frameCount == 0 ||
        pictureCount == 0 ||
        offset > bytes.length ||
        bytes[4] > bytes[5] ||
        bytes[5] >= frameCount) {
      throw const FormatException('动画索引无效');
    }
    final frames = <BayeAnimationFrame>[];
    for (var i = 0; i < frameCount; i++) {
      final p = 6 + i * 5;
      if (bytes[p + 4] >= pictureCount) {
        throw const FormatException('动画图片编号越界');
      }
      frames.add(
        BayeAnimationFrame(
          x: bytes[p],
          y: bytes[p + 1],
          clearDelay: bytes[p + 2],
          nextDelay: bytes[p + 3],
          pictureIndex: bytes[p + 4],
        ),
      );
    }
    final pictures = <BayeBitmap>[];
    for (var i = 0; i < pictureCount; i++) {
      final group = BayePictureGroup.decode(bytes, offset: offset);
      if (group.count != 1) {
        throw const FormatException('动画内图片组应仅含一张图片');
      }
      final picture = group.picture(0);
      if (picture == null) throw const FormatException('动画图片缺失');
      pictures.add(picture);
      offset += group.byteLength;
    }
    if (offset != bytes.length) throw const FormatException('动画存在未解析数据');
    return BayeAnimation._(
      bytes[4],
      bytes[5],
      List.unmodifiable(frames),
      List.unmodifiable(pictures),
    );
  }

  final int startFrame;
  final int endFrame;
  final List<BayeAnimationFrame> frames;
  final List<BayeBitmap> pictures;
}

/// 单帧元数据；延时单位与原版逻辑计时一致，由时钟层解释。
final class BayeAnimationFrame {
  const BayeAnimationFrame({
    required this.x,
    required this.y,
    required this.clearDelay,
    required this.nextDelay,
    required this.pictureIndex,
  });

  final int x;
  final int y;
  final int clearDelay;
  final int nextDelay;
  final int pictureIndex;
}

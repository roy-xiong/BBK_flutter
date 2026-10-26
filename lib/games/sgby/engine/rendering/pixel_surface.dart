import 'dart:math' as math;
import 'dart:typed_data';

import '../resources/baye_picture.dart';

/// 游戏的 8bpp 调色板画布，坐标均为实际资源像素。
///
/// 逻辑坐标在调用边界乘以资源倍率，合成期间不执行平滑插值。画布由游戏
/// 会话所在 isolate 独占；输出快照复制数据，后台处理不能并发修改当前帧。
final class PixelSurface {
  PixelSurface({required this.width, required this.height}) {
    if (width <= 0 || height <= 0 || width > 4096 || height > 4096) {
      throw ArgumentError('画布尺寸必须在 1 到 4096 之间');
    }
    _pixels = Uint8List(width * height);
  }

  final int width;
  final int height;
  late final Uint8List _pixels;

  /// 返回独立快照，后续绘制不会改变已交给渲染器或存档的帧。
  Uint8List snapshot() => Uint8List.fromList(_pixels);

  /// 显示增强仅读取局部像素，避免为几十个城市图标复制整个8bpp画布。
  int sample(int x, int y) =>
      x < 0 || y < 0 || x >= width || y >= height ? 0 : _pixels[y * width + x];

  /// 恢复完整帧缓冲；严格校验长度，避免旧分辨率快照污染新画布。
  void restore(Uint8List pixels) {
    if (pixels.length != _pixels.length) {
      throw const FormatException('帧缓冲尺寸不匹配');
    }
    _pixels.setAll(0, pixels);
  }

  /// 画整数像素线。线段先按画布范围逐点裁剪，不执行抗锯齿。
  void line(
    int x0,
    int y0,
    int x1,
    int y1, {
    int color = 255,
    int thickness = 1,
  }) {
    final dx = (x1 - x0).abs();
    final dy = -(y1 - y0).abs();
    final sx = x0 < x1 ? 1 : -1;
    final sy = y0 < y1 ? 1 : -1;
    var error = dx + dy;
    while (true) {
      fill(x0, y0, x0 + thickness - 1, y0 + thickness - 1, color);
      if (x0 == x1 && y0 == y1) break;
      final doubled = 2 * error;
      if (doubled >= dy) {
        error += dy;
        x0 += sx;
      }
      if (doubled <= dx) {
        error += dx;
        y0 += sy;
      }
    }
  }

  /// 清空为指定的调色板索引；0 对应原引擎背景色。
  void clear([int color = 0]) =>
      _pixels.fillRange(0, _pixels.length, color & 255);

  /// 边界外的像素不参与绘制，避免光标或动画越界导致数组访问崩溃。
  void pixel(int x, int y, int color) {
    if (x < 0 || y < 0 || x >= width || y >= height) return;
    _pixels[y * width + x] = color & 255;
  }

  /// 填充包含右下端点的矩形，与 SysLcdPartClear 的端点语义一致。
  void fill(int left, int top, int right, int bottom, [int color = 0]) {
    final x0 = math.max(0, left);
    final x1 = math.min(width - 1, right);
    final y0 = math.max(0, top);
    final y1 = math.min(height - 1, bottom);
    if (x1 < x0 || y1 < y0) return;
    for (var y = y0; y <= y1; y++) {
      _pixels.fillRange(y * width + x0, y * width + x1 + 1, color & 255);
    }
  }

  /// 逐像素反色；不通过透明图层模拟，保留连续两次反色恢复原图的性质。
  void reverse(int left, int top, int right, int bottom) {
    final x0 = math.max(0, left);
    final x1 = math.min(width - 1, right);
    final y0 = math.max(0, top);
    final y1 = math.min(height - 1, bottom);
    for (var y = y0; y <= y1; y++) {
      for (var x = x0; x <= x1; x++) {
        final index = y * width + x;
        _pixels[index] = 255 - _pixels[index];
      }
    }
  }

  /// 二值遮罩先保留/清除背景，数据位为1时以当前前景色覆盖。
  ///
  /// 原版OR操作针对二值数据位；不能按调色板索引做位或，否则128号红色标记
  /// 叠在200号地形上会错误地变成200号，造成兵种图标局部丢色。
  void blit(BayeBitmap bitmap, int left, int top, {int color = 255}) {
    final x0 = math.max(0, -left);
    final y0 = math.max(0, -top);
    final x1 = math.min(bitmap.width, width - left);
    final y1 = math.min(bitmap.height, height - top);
    final ink = color & 255;
    for (var y = y0; y < y1; y++) {
      for (var x = x0; x < x1; x++) {
        final index = (top + y) * width + left + x;
        final value = bitmap.inkAt(x, y) ? ink : 0;
        _pixels[index] = value != 0
            ? value
            : bitmap.preservesAt(x, y) && ink != 0
            ? _pixels[index]
            : 0;
      }
    }
  }

  /// 按调色板生成RGBA；没有指定调色板时使用不透明灰阶，供Flutter整帧提交。
  ///
  /// 彩色阵营覆盖将在显示增强层完成，不能修改规则层使用的二值资源。
  Uint8List rgbaSnapshot({List<int>? palette}) {
    if (palette != null && palette.length != 256) {
      throw const FormatException('显示调色板需要256个颜色');
    }
    final output = Uint8List(_pixels.length * 4);
    for (var i = 0; i < _pixels.length; i++) {
      final offset = i * 4;
      if (palette == null) {
        final shade = 255 - _pixels[i];
        output[offset] = shade;
        output[offset + 1] = shade;
        output[offset + 2] = shade;
        output[offset + 3] = 255;
      } else {
        final color = palette[_pixels[i]];
        output[offset] = color & 255;
        output[offset + 1] = (color >> 8) & 255;
        output[offset + 2] = (color >> 16) & 255;
        output[offset + 3] = (color >> 24) & 255;
      }
    }
    return output;
  }
}

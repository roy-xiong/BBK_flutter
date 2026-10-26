import 'dart:math' as math;
import 'dart:typed_data';
import '../data/game_data.dart';

/// 由 Flutter 系统字体排版器提供分页，不在游戏核心中实现字模或字体回退。
abstract interface class SystemTextLayout {
  TextPage fit(String text, int start, int width, int height);
}

final class TextPage {
  const TextPage(this.text, this.next);
  final String text;
  final int next;
}

/// 一条系统文字绘制命令，由 Flutter Canvas 与图片帧合成。
final class SystemTextRun {
  SystemTextRun(
    this.text,
    this.x,
    this.y,
    this.width,
    this.height,
    this.selected, [
    this.fontSize = 14,
  ]);
  final String text;
  final int x, y, width, height;
  final bool selected;
  final double fontSize;
  final Set<int> hiddenRows = {};
  SystemTextRun copy() =>
      SystemTextRun(text, x, y, width, height, selected, fontSize)
        ..hiddenRows.addAll(hiddenRows);
}

/// 整数坐标软件画布；统一裁剪负坐标，禁止精灵写入相邻行。
final class PixelSurface {
  PixelSurface(this.width, this.height, {this.textLayout})
    : pixels = Uint32List(width * height);
  final int width;
  final int height;
  final Uint32List pixels;
  final SystemTextLayout? textLayout;
  final List<SystemTextRun> textRuns = [];
  void clear([int color = 0xffb4b4b4]) {
    pixels.fillRange(0, pixels.length, color);
    textRuns.clear();
  }

  void dot(int x, int y, int color) {
    if (x >= 0 && y >= 0 && x < width && y < height) {
      pixels[y * width + x] = color;
    }
  }

  void fill(
    int left,
    int top,
    int right,
    int bottom, [
    int color = 0xffb4b4b4,
  ]) {
    textRuns.removeWhere(
      (run) =>
          run.x < right &&
          run.x + run.width > left &&
          run.y < bottom &&
          run.y + run.height > top,
    );
    final x0 = left.clamp(0, width), x1 = right.clamp(0, width);
    if (x1 <= x0) return;
    for (var y = top.clamp(0, height); y < bottom.clamp(0, height); y++) {
      pixels.fillRange(y * width + x0, y * width + x1, color);
    }
  }

  void line(int x, int y, int right, int bottom, [int color = 0xff000000]) {
    final dx = (right - x).abs(), dy = -(bottom - y).abs();
    final sx = x < right ? 1 : -1, sy = y < bottom ? 1 : -1;
    var error = dx + dy;
    for (var budget = 0; budget < 16384; budget++) {
      dot(x, y, color);
      if (x == right && y == bottom) return;
      final twice = error * 2;
      if (twice >= dy) {
        error += dy;
        x += sx;
      }
      if (twice <= dx) {
        error += dx;
        y += sy;
      }
    }
  }

  void rect(
    int left,
    int top,
    int right,
    int bottom, [
    int color = 0xff000000,
  ]) {
    line(left, top, right, top, color);
    line(right, top, right, bottom, color);
    line(right, bottom, left, bottom, color);
    line(left, bottom, left, top, color);
  }

  void frame(
    int left,
    int top,
    int right,
    int bottom, {
    bool selected = false,
  }) {
    fill(left, top, right, bottom, selected ? 0xff000000 : 0xffb4b4b4);
    rect(left, top, right, bottom);
  }

  void blit(
    GameBitmap? bitmap,
    int left,
    int top, {
    int scale = 1,
    bool extendCurtain = false,
  }) {
    if (bitmap == null || scale < 1) return;
    final w = extendCurtain ? width : bitmap.width * scale;
    // 系统文字保持独立图层，整行不透明特效覆盖后也必须遮住对应行。
    if (bitmap.isOpaque && textRuns.isNotEmpty) {
      for (final run in textRuns) {
        if (left <= run.x && left + w >= run.x + run.width) {
          for (
            var y = math.max(math.max(0, top), run.y);
            y <
                math.min(
                  math.min(height, top + bitmap.height * scale),
                  run.y + run.height,
                );
            y++
          ) {
            run.hiddenRows.add(y);
          }
        }
      }
    }
    for (
      var y = math.max(0, top);
      y < math.min(height, top + bitmap.height * scale);
      y++
    ) {
      final sourceRow = (y - top) ~/ scale * bitmap.width;
      for (var x = math.max(0, left); x < math.min(width, left + w); x++) {
        final color =
            bitmap.pixels[sourceRow +
                math.min(bitmap.width - 1, (x - left) ~/ scale)];
        if (color >> 24 != 0) pixels[y * width + x] = color;
      }
    }
  }

  /// 只记录系统文字与布局结果，不读取点阵字库，不向帧缓冲写入字符像素。
  int text(
    GameData data,
    String text,
    int x,
    int y, {
    bool selected = false,
    int? right,
    int? bottom,
    int start = 0,
    double fontSize = 14,
  }) {
    final layout = textLayout;
    if (layout == null) throw StateError('文字绘制需要系统字体排版器');
    final availableWidth = math.max(1, (right ?? width) - x),
        availableHeight = math.max(0, (bottom ?? y + 16) - y);
    final page = layout.fit(
      text,
      start,
      (availableWidth * 14 / fontSize).round(),
      (availableHeight * 14 / fontSize).round(),
    );
    if (page.text.isNotEmpty) {
      textRuns.add(
        SystemTextRun(
          page.text,
          x,
          y,
          availableWidth,
          availableHeight,
          selected,
          fontSize,
        ),
      );
    }
    return page.next;
  }

  /// 与 BBK 的 Scale3x、墨色调色与 82% 边缘混合逐式对应。
  Uint32List enhancedPixels() {
    final result = Uint32List(width * height * 9);
    final palette = <int, int>{};
    final blends = <(int, int), int>{};
    int color(int value) {
      // 绝大多数帧只有原黑色与 RGB180 纸色，直接返回可避免每帧创建大量闭包。
      if (value == 0xff000000) return 0xff1d1b18;
      if (value == 0xffb4b4b4) return 0xffcfd8d8;
      if (value == 0) return 0;
      final cached = palette[value];
      if (cached != null) return cached;
      final r = value & 255,
          g = (value >> 8) & 255,
          b = (value >> 16) & 255,
          a = value & 0xff000000;
      if (a == 0) return 0;
      final luma = (r * 299 + g * 587 + b * 114) / 1000;
      int result;
      if (math.max(r, math.max(g, b)) - math.min(r, math.min(g, b)) <= 18 &&
          luma < 80) {
        result = a | 24 | (27 << 8) | (29 << 16);
      } else if (math.max(r, math.max(g, b)) - math.min(r, math.min(g, b)) <=
              18 &&
          luma > 135) {
        result = a | 216 | (216 << 8) | (207 << 16);
      } else {
        int tint(int v) => ((v - 128) * 1.08 + 128).round().clamp(0, 255);
        result = a | tint(r) | (tint(g) << 8) | (tint(b) << 16);
      }
      palette[value] = result;
      return result;
    }

    int blend(int a, int b) {
      if (a == b) return color(a);
      if (a == 0xff000000 && b == 0xffb4b4b4) return 0xff3d3d3b;
      if (a == 0xffb4b4b4 && b == 0xff000000) return 0xffafb6b5;
      final key = (a, b), cached = blends[key];
      if (cached != null) return cached;
      final ca = color(a), cb = color(b);
      var value = 0;
      for (var shift = 0; shift < 32; shift += 8) {
        value |=
            ((((ca >> shift) & 255) * .82 + ((cb >> shift) & 255) * .18)
                    .round() &
                255) <<
            shift;
      }
      blends[key] = value;
      return value;
    }

    final ow = width * 3;
    for (var y = 0; y < height; y++) {
      final n = math.max(0, y - 1) * width,
          s = math.min(height - 1, y + 1) * width,
          row = y * width;
      for (var x = 0; x < width; x++) {
        final w = math.max(0, x - 1), east = math.min(width - 1, x + 1);
        final a = pixels[n + w],
            b = pixels[n + x],
            c = pixels[n + east],
            d = pixels[row + w],
            e = pixels[row + x],
            f = pixels[row + east],
            g = pixels[s + w],
            h = pixels[s + x],
            i = pixels[s + east];
        final e0 = d == b && d != h && b != f ? d : e;
        final e1 =
            (d == b && d != h && b != f && e != c) ||
                (b == f && b != d && f != h && e != a)
            ? b
            : e;
        final e2 = b == f && b != d && f != h ? f : e;
        final e3 =
            (d == b && d != h && b != f && e != g) ||
                (d == h && d != b && h != f && e != a)
            ? d
            : e;
        final e5 =
            (b == f && b != d && f != h && e != i) ||
                (h == f && d != h && b != f && e != c)
            ? f
            : e;
        final e6 = d == h && d != b && h != f ? d : e;
        final e7 =
            (d == h && d != b && h != f && e != i) ||
                (h == f && d != h && b != f && e != g)
            ? h
            : e;
        final e8 = h == f && d != h && b != f ? f : e;
        final o = y * 3 * ow + x * 3;
        result[o] = color(e0);
        result[o + 1] = blend(e1, e);
        result[o + 2] = color(e2);
        result[o + ow] = blend(e3, e);
        result[o + ow + 1] = color(e);
        result[o + ow + 2] = blend(e5, e);
        result[o + ow * 2] = color(e6);
        result[o + ow * 2 + 1] = blend(e7, e);
        result[o + ow * 2 + 2] = color(e8);
      }
    }
    return result;
  }
}

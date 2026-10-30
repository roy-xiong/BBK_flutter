import 'dart:math' as math;
import 'dart:ui';
import '../data/game_data.dart';

/// 原SRS只提供构图与出现位置；连续外轮廓经简化和三次曲线重建，消除逐像素方块。
/// 结果按位图弱键缓存，退出会话后可回收；轮廓复杂度与原周长相关，不创建GPU纹理。
final class ModernEffectShape {
  ModernEffectShape(this.path, this.bounds, this.centers);
  final Path path;
  final Rect bounds;
  final List<Offset> centers;
  static final _cache = Expando<ModernEffectShape>();
  static ModernEffectShape of(GameBitmap bitmap) =>
      _cache[bitmap] ??= _build(bitmap);

  static ModernEffectShape _build(GameBitmap bitmap) {
    final width = bitmap.width, height = bitmap.height, stride = width + 1;
    var mask = List<bool>.generate(width * height, (i) {
      final pixel = bitmap.pixels[i];
      return pixel >> 24 != 0 && pixel & 0xffffff == 0;
    });
    bool sample(List<bool> pixels, int x, int y) =>
        x >= 0 && y >= 0 && x < width && y < height && pixels[y * width + x];
    // 原点阵常用一像素间隙抖动。先接合内部断层，再拟合外形，不能把棋盘状
    // 黑点直接放大成一串圆点；原黑像素及整体构图仍保持。
    for (var pass = 0; pass < 2; pass++) {
      final before = mask;
      mask = List<bool>.generate(width * height, (i) {
        if (before[i]) return true;
        final x = i % width, y = i ~/ width;
        return sample(before, x - 1, y) && sample(before, x + 1, y) ||
            sample(before, x, y - 1) && sample(before, x, y + 1) ||
            sample(before, x - 1, y - 1) && sample(before, x + 1, y + 1) ||
            sample(before, x + 1, y - 1) && sample(before, x - 1, y + 1);
      });
    }
    bool ink(int x, int y) => sample(mask, x, y);
    final edges = <int, List<int>>{};
    void edge(int x, int y, int xx, int yy) =>
        edges.putIfAbsent(y * stride + x, () => []).add(yy * stride + xx);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        if (!ink(x, y)) continue;
        if (!ink(x, y - 1)) edge(x, y, x + 1, y);
        if (!ink(x + 1, y)) edge(x + 1, y, x + 1, y + 1);
        if (!ink(x, y + 1)) edge(x + 1, y + 1, x, y + 1);
        if (!ink(x - 1, y)) edge(x, y + 1, x, y);
      }
    }
    final path = Path()..fillType = PathFillType.evenOdd;
    final centers = <Offset>[];
    while (edges.isNotEmpty) {
      final start = edges.keys.first;
      var current = start;
      final points = <Offset>[];
      for (var guard = 0; guard < (width + 1) * (height + 1) * 4; guard++) {
        points.add(
          Offset((current % stride).toDouble(), (current ~/ stride).toDouble()),
        );
        final next = edges[current];
        if (next == null || next.isEmpty) break;
        final target = next.removeLast();
        if (next.isEmpty) edges.remove(current);
        current = target;
        if (current == start) break;
      }
      if (points.length < 3) continue;
      final box = points.fold<Rect>(
        Rect.fromPoints(points.first, points.first),
        (r, p) => r.expandToInclude(Rect.fromPoints(p, p)),
      );
      if (box.width <= 1.5 && box.height <= 1.5) {
        path.addOval(box.inflate(.1));
        continue;
      }
      final half = points.length ~/ 2;
      final reduced = [
        ..._simplify(points.sublist(0, half + 1)),
        ..._simplify([...points.sublist(half), points.first]).skip(1),
      ];
      if (reduced.length > 1 && reduced.last == reduced.first) {
        reduced.removeLast();
      }
      if (reduced.length < 3) continue;
      path.moveTo(reduced.first.dx, reduced.first.dy);
      for (var i = 0; i < reduced.length; i++) {
        final a = reduced[(i - 1) % reduced.length],
            b = reduced[i],
            c = reduced[(i + 1) % reduced.length],
            d = reduced[(i + 2) % reduced.length];
        // 限制切线长度，尖端保留收束，不把细剑尖平滑成膨大的圆团。
        final tangent1 = (c - a) * .145, tangent2 = (d - b) * .145;
        path.cubicTo(
          b.dx + tangent1.dx,
          b.dy + tangent1.dy,
          c.dx - tangent2.dx,
          c.dy - tangent2.dy,
          c.dx,
          c.dy,
        );
      }
      path.close();
      if (box.width * box.height > 12 && centers.length < 24) {
        centers.add(box.center);
      }
    }
    return ModernEffectShape(path, path.getBounds(), centers);
  }

  /// 迭代式RDP避免长轮廓递归溢出；0.85原像素容差仅简化锯齿，不抹掉招式构图。
  static List<Offset> _simplify(List<Offset> points) {
    if (points.length < 4) return points;
    final keep = <int>{0, points.length - 1},
        stack = <(int, int)>[(0, points.length - 1)];
    while (stack.isNotEmpty) {
      final (first, last) = stack.removeLast();
      final a = points[first], v = points[last] - a;
      var furthest = -1, distance = .85 * .85;
      for (var i = first + 1; i < last; i++) {
        final p = points[i] - a;
        final t = v.distanceSquared == 0
            ? 0.0
            : ((p.dx * v.dx + p.dy * v.dy) / v.distanceSquared).clamp(0.0, 1.0);
        final delta = p - v * t;
        if (delta.distanceSquared > distance) {
          distance = delta.distanceSquared;
          furthest = i;
        }
      }
      if (furthest >= 0) {
        keep.add(furthest);
        stack.add((first, furthest));
        stack.add((furthest, last));
      }
    }
    final indices = keep.toList()..sort();
    return indices.map((i) => points[math.min(i, points.length - 1)]).toList();
  }
}

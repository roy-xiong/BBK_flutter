import 'dart:ui';

/// 只圆滑可见地面边缘，真实地图、碰撞和出口仍按原整数格处理。
abstract final class ModernMazeFloor {
  static Path build({
    required int width,
    required int height,
    required bool Function(int, int) walkable,
  }) {
    bool floor(int x, int y) =>
        x >= 0 && y >= 0 && x < width && y < height && walkable(x, y);
    const r = .18, rounded = Radius.circular(r);
    final path = Path();
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        if (!floor(x, y)) continue;
        final up = floor(x, y - 1),
            down = floor(x, y + 1),
            left = floor(x - 1, y),
            right = floor(x + 1, y);
        path.addRRect(
          RRect.fromRectAndCorners(
            Rect.fromLTWH(x.toDouble(), y.toDouble(), 1, 1),
            topLeft: !up && !left ? rounded : Radius.zero,
            topRight: !up && !right ? rounded : Radius.zero,
            bottomLeft: !down && !left ? rounded : Radius.zero,
            bottomRight: !down && !right ? rounded : Radius.zero,
          ),
        );
        void concave(
          bool enabled,
          double vx,
          double vy,
          double ax,
          double ay,
          double bx,
          double by,
        ) {
          if (!enabled) return;
          path.moveTo(vx, vy);
          path.lineTo(vx + ax * r, vy + ay * r);
          path.quadraticBezierTo(vx, vy, vx + bx * r, vy + by * r);
          path.close();
        }

        concave(
          up && right && !floor(x + 1, y - 1),
          x + 1.0,
          y.toDouble(),
          0,
          -1,
          1,
          0,
        );
        concave(
          up && left && !floor(x - 1, y - 1),
          x.toDouble(),
          y.toDouble(),
          0,
          -1,
          -1,
          0,
        );
        concave(
          down && right && !floor(x + 1, y + 1),
          x + 1.0,
          y + 1.0,
          0,
          1,
          1,
          0,
        );
        concave(
          down && left && !floor(x - 1, y + 1),
          x.toDouble(),
          y + 1.0,
          0,
          1,
          -1,
          0,
        );
      }
    }
    return path;
  }
}

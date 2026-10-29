import 'dart:math' as math;
import 'dart:ui';

/// 与原版相同，在边缘约束镜头；小于视窗的地图以边缘图块延伸铺满。
///
/// 地图坐标不变。只有取样坐标进行裁剪，角色、事件和碰撞始终使用真实格子。
final class ModernMapCamera {
  ModernMapCamera({
    required this.mapWidth,
    required this.mapHeight,
    required num playerX,
    required num playerY,
    required bool wide,
  }) : tileSize = wide ? 32 : 64,
       columns = wide ? 20 : 10,
       rows = wide ? 12 : 6 {
    viewLeft = (playerX - columns ~/ 2)
        .clamp(0, math.max(0, mapWidth - columns))
        .toDouble();
    viewTop = (playerY - rows ~/ 2)
        .clamp(0, math.max(0, mapHeight - rows))
        .toDouble();
    left = viewLeft.floor();
    top = viewTop.floor();
  }
  final int mapWidth, mapHeight, columns, rows;
  final double tileSize;
  late final int left, top;
  late final double viewLeft, viewTop;
  int get paintColumns => columns + (viewLeft > left ? 1 : 0);
  int get paintRows => rows + (viewTop > top ? 1 : 0);
  Offset point(num x, num y) =>
      Offset((x - viewLeft) * tileSize, (y - viewTop) * tileSize);
  (int, int) sample(int column, int row) => (
    (left + column).clamp(0, mapWidth - 1),
    (top + row).clamp(0, mapHeight - 1),
  );
  Rect target(int column, int row) => Rect.fromLTWH(
    (left + column - viewLeft) * tileSize,
    (top + row - viewTop) * tileSize,
    tileSize,
    tileSize,
  );
}

import 'dart:math' as math;
import 'dart:ui';

/// 与原版相同，在边缘约束镜头；小于视窗的地图以边缘图块延伸铺满。
///
/// 地图坐标不变。只有取样坐标进行裁剪，角色、事件和碰撞始终使用真实格子。
final class ModernMapCamera {
  /// 仅用于连续场景内部绘制一张已经按真实区域裁剪的路段。
  /// 游戏普通镜头仍使用下方有边界约束的构造函数，不能借此强制人物居中。
  ModernMapCamera.window({
    required this.mapWidth,
    required this.mapHeight,
    required this.left,
    required this.top,
    required bool wide,
  }) : tileSize = wide ? 32 : 64,
       columns = wide ? 20 : 10,
       rows = wide ? 12 : 6;
  ModernMapCamera({
    required this.mapWidth,
    required this.mapHeight,
    required int playerX,
    required int playerY,
    required bool wide,
  }) : tileSize = wide ? 32 : 64,
       columns = wide ? 20 : 10,
       rows = wide ? 12 : 6 {
    left = (playerX - columns ~/ 2).clamp(0, math.max(0, mapWidth - columns));
    top = (playerY - rows ~/ 2).clamp(0, math.max(0, mapHeight - rows));
  }
  final int mapWidth, mapHeight, columns, rows;
  final double tileSize;
  late final int left, top;
  Offset point(int x, int y) =>
      Offset((x - left) * tileSize, (y - top) * tileSize);
  (int, int) sample(int column, int row) => (
    (left + column).clamp(0, mapWidth - 1),
    (top + row).clamp(0, mapHeight - 1),
  );
  Rect target(int column, int row) =>
      Rect.fromLTWH(column * tileSize, row * tileSize, tileSize, tileSize);
}

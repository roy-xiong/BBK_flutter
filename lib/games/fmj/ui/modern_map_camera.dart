import 'dart:math' as math;
import 'dart:ui';

/// 正常行走固定人物的屏幕锚点，横桥、竖桥及短道路切换时不因地图尺寸跳位。
///
/// 只有取样坐标裁剪到真实地图；镜头允许超出边缘，不能反向改写角色的世界位置。
/// 审核整图导出可显式使用clampToMap保留原拼图取景，鼠标反算与游戏共用默认镜头。
final class ModernMapCamera {
  ModernMapCamera({
    required this.mapWidth,
    required this.mapHeight,
    required int playerX,
    required int playerY,
    required bool wide,
    this.clampToMap = false,
  }) : tileSize = wide ? 32 : 64,
       columns = wide ? 20 : 10,
       rows = wide ? 12 : 6 {
    final x = playerX - columns ~/ 2, y = playerY - rows ~/ 2;
    left = clampToMap ? x.clamp(0, math.max(0, mapWidth - columns)) : x;
    top = clampToMap ? y.clamp(0, math.max(0, mapHeight - rows)) : y;
  }
  final int mapWidth, mapHeight, columns, rows;
  final double tileSize;
  final bool clampToMap;
  late final int left, top;
  Offset point(int x, int y) =>
      Offset((x - left) * tileSize, (y - top) * tileSize);
  (int, int) sample(int column, int row) => (
    (left + column).clamp(0, mapWidth - 1),
    (top + row).clamp(0, mapHeight - 1),
  );

  /// 地图外只延展底材；不能把边缘房屋、篱笆、树或门复制成多排假结构。
  bool containsSource(int column, int row) =>
      left + column >= 0 &&
      top + row >= 0 &&
      left + column < mapWidth &&
      top + row < mapHeight;
  Rect target(int column, int row) =>
      Rect.fromLTWH(column * tileSize, row * tileSize, tileSize, tileSize);
}

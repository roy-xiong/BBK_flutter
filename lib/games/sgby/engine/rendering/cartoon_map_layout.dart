import 'dart:ui';

import '../resources/baye_database.dart';

/// 彩色地图只换素材，布局读取与黑白引擎相同的 C_CITYPOS 和16×16逻辑格。
///
/// 不持有经纬度、独立相机或最近城池吸附；视口偏移与原版输入保持一致。
final class CartoonMapLayout {
  CartoonMapLayout(this.resources, {this.viewX = 0, this.viewY = 0});
  final BayeDatabase resources;
  final int viewX, viewY;

  Rect get bounds => Rect.fromLTWH(
    0,
    0,
    (((resources.logicalWidth + 1) ~/ 16) - 2) * 16.0,
    resources.logicalHeight.toDouble(),
  );

  /// 返回原版城池所在的整格，不因重要性、选中状态或名称避让而挪动。
  Rect? cell(int id) {
    final positions = resources.constant(6);
    if (id < 0 || id * 2 + 1 >= positions.length) return null;
    return Rect.fromLTWH(
      (positions[id * 2] - viewX) * 16.0,
      (positions[id * 2 + 1] - viewY) * 16.0,
      16,
      16,
    );
  }

  Offset? city(int id) => cell(id)?.center;

  /// 完整列出视口内城池；每个格子固定分配图标、城名、数量位置，不隐藏名称。
  Iterable<int> visibleCities(int count) sync* {
    for (var id = 0; id < count; id++) {
      final rect = cell(id);
      if (rect != null && bounds.overlaps(rect)) yield id;
    }
  }
}

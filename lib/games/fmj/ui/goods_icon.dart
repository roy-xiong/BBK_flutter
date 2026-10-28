import 'package:flutter/material.dart';
import 'modern_art.dart';

/// 菜单统一使用原物品ID查彩色图标；背包、商店、战斗和穿戴没有独立映射副本。
/// 图集由会话统一持有和释放，滚动列表不逐行解码、不缓存额外GPU图片。
final class GoodsIcon extends StatelessWidget {
  const GoodsIcon({
    super.key,
    required this.id,
    required this.art,
    this.size = 32,
  });
  final String id;
  final ModernArt? art;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(painter: GoodsIconPainter(id, art)),
  );
}

final class GoodsIconPainter extends CustomPainter {
  const GoodsIconPainter(this.id, this.art);
  final String id;
  final ModernArt? art;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    art?.drawSprite(
      canvas,
      'goods:$id/0',
      bounds,
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(GoodsIconPainter oldDelegate) =>
      id != oldDelegate.id || !identical(art, oldDelegate.art);
}

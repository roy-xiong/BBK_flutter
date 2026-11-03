part of 'modern_scene.dart';

extension _ConnectedRoadPainting on ModernScenePainter {
  static final _clips = Expando<Path>();

  /// 按原脚本解析的实例及接缝裁剪真实路段，绘制区域与逻辑出口分开。
  /// 每次绘制至多处理18个实例且剔除视窗外实例，不解码图片或建立无限缓存。
  void _connected(Canvas canvas, ModernArt art) {
    final world = game.connectedWorld,
        view = game.connectedWorld.view(game.wide);
    final current = world.current;
    if (view == null || current == null) return;
    final tile = view.tileSize;
    final map = current.map;
    final base = ModernTerrain.sceneMaterial(
      map.tiles,
      map.cell(0, 0) & 127,
      false,
    );
    // 路段之外的角落同样完整铺设自然底材，但绝不生成可行走的假道路。
    for (var y = 0; y < view.rows; y++) {
      for (var x = 0; x < view.columns; x++) {
        art.drawGround(
          canvas,
          base,
          Rect.fromLTWH(x * tile, y * tile, tile, tile),
          view.left + x,
          view.top + y,
          _paint..color = Colors.white,
        );
      }
    }
    for (final node in world.visiblePriority.reversed) {
      final region = node.region;
      final bounds = region.bounds;
      if (bounds.$3 <= bounds.$1 || bounds.$4 <= bounds.$2) continue;
      final rect = Rect.fromLTRB(
        (bounds.$1 - view.left) * tile,
        (bounds.$2 - view.top) * tile,
        (bounds.$3 - view.left) * tile,
        (bounds.$4 - view.top) * tile,
      );
      if (!rect.overlaps(const Rect.fromLTWH(0, 0, 640, 384))) {
        continue;
      }
      canvas.save();
      final clip = _clips[region] ??= (() {
        final path = Path();
        if (region.right > region.left && region.bottom > region.top) {
          path.addRect(
            Rect.fromLTRB(
              region.left.toDouble(),
              region.top.toDouble(),
              region.right.toDouble(),
              region.bottom.toDouble(),
            ),
          );
        }
        for (final cell in region.cells) {
          path.addRect(
            Rect.fromLTWH(cell.$1.toDouble(), cell.$2.toDouble(), 1, 1),
          );
        }
        return path;
      })();
      canvas.scale(tile);
      canvas.translate(-view.left.toDouble(), -view.top.toDouble());
      canvas.clipPath(clip, doAntiAlias: false);
      canvas.translate(view.left.toDouble(), view.top.toDouble());
      canvas.scale(1 / tile);
      ModernScenePainter(
        game,
        art,
        mapOverride: node.map,
        overview: true,
        cameraOverride: ModernMapCamera.window(
          mapWidth: node.map.width,
          mapHeight: node.map.height,
          left: view.left - node.x,
          top: view.top - node.y,
          wide: game.wide,
        ),
        textStyle: textStyle,
      ).paint(canvas, const Size(640, 384));
      canvas.restore();
    }
    for (final point in game.route.take(12)) {
      canvas.drawCircle(
        Offset(
          (current.x + point.$1 - view.left + .5) * tile,
          (current.y + point.$2 - view.top + .6) * tile,
        ),
        2,
        _paint..color = const Color(0x997dd9c3),
      );
    }
    // 世界足迹保留伙伴在上一段桥上的位置，换图不重新瞬移排队。
    for (final pose in world.actors) {
      final correction = world.actorOffset(pose.actor);
      final point = Offset(
        (pose.x + correction.$1 - view.left) * tile,
        (pose.y + correction.$2 - view.top) * tile,
      );
      if (point.dx < -160 ||
          point.dx > 800 ||
          point.dy < -192 ||
          point.dy > 512) {
        continue;
      }
      _drawActor(
        canvas,
        art,
        pose.actor,
        point,
        tile,
        direction: pose.direction,
        step: pose.step,
      );
    }
  }
}

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../engine/game_engine.dart';
import '../engine/game_actor.dart';
import 'modern_art.dart';
import 'modern_map_camera.dart';
import 'modern_battle_layout.dart';
import 'modern_terrain.dart';
import 'modern_world_objects.dart';

/// 四个方向严格对应屏幕水平、垂直轴，绘制坐标从不影响原地图碰撞和脚本。
final class ModernScenePainter extends CustomPainter {
  ModernScenePainter(
    this.game,
    this.art, {
    this.cameraOverride,
    this.overview = false,
    this.showActorsInOverview = false,
    this.textStyle,
  });
  final GameEngine game;
  final ModernArt? art;

  /// 审核文档复用同一生产渲染器导出完整地图；游戏默认路径不启用此模式。
  final ModernMapCamera? cameraOverride;
  final bool overview;
  final bool showActorsInOverview;

  /// 名牌与战斗数字沿用所在界面的系统字体及回退链；Painter 不另选字体。
  final TextStyle? textStyle;
  final Paint _paint = Paint()..filterQuality = FilterQuality.medium;

  /// 与方向键使用同一网格。保留为公开纯函数，供方向一致性回归验证。
  static Offset project(int x, int y, int cameraX, int cameraY) =>
      Offset(320 + (x - cameraX) * 32, 208 + (y - cameraY) * 32);

  @override
  void paint(Canvas canvas, Size size) {
    _paint.filterQuality = game.preferences['hd'] == true
        ? FilterQuality.medium
        : FilterQuality.none;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.scale(size.width / 640, size.height / 384);
    final art = this.art;
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 640, 384),
      _paint..color = const Color(0xff263d39),
    );
    if (art == null) {
      canvas.restore();
      return;
    }
    if (game.battle != null || game.map == null) {
      _landscape(canvas, art);
      if (game.battle != null) _battle(canvas, art);
      canvas.restore();
      return;
    }
    final map = game.map!, player = game.player;
    final camera =
        cameraOverride ??
        ModernMapCamera(
          mapWidth: map.width,
          mapHeight: map.height,
          playerX: player?.x ?? map.width ~/ 2,
          playerY: player?.y ?? map.height ~/ 2,
          wide: game.wide,
        );
    final tileSize = camera.tileSize, room = art.rooms[map.id];
    final buildings = (art.buildings[map.id] ?? const <SceneBuilding>[])
        .where((b) => art.sprites.containsKey('${b.key}/0'))
        .toList(growable: false);
    final decorations = (art.decorations[map.id] ?? const <SceneBuilding>[])
        .where((b) => art.sprites.containsKey('${b.key}/0'))
        .toList(growable: false);
    Iterable<int> coveredBy(SceneBuilding b) =>
        b.cells ??
        [
          for (var y = b.y; y < b.y + b.height; y++)
            for (var x = b.x; x < b.x + b.width; x++) y * map.width + x,
        ];
    final foregroundCovered = <int>{
      for (final b in [...buildings, ...decorations.where((b) => !b.floor)])
        ...coveredBy(b),
    };
    final floorCovered = <int>{
      for (final b in decorations.where((b) => b.floor)) ...coveredBy(b),
    };
    final buildingGround = <int>{for (final b in buildings) ...coveredBy(b)};
    bool inside(int x, int y) =>
        room == null || room.contains(Offset(x + .5, y + .5));
    // 第一层只铺地面，不能因为图块不认识就把原物件擦成同一片地板。
    for (var row = 0; row < camera.rows; row++) {
      for (var column = 0; column < camera.columns; column++) {
        final (x, y) = camera.sample(column, row);
        final target = camera.target(column, row);
        _paint.color = Colors.white;
        if (!inside(x, y)) {
          canvas.drawRect(target, _paint..color = const Color(0xff182725));
          continue;
        }
        final hallWall =
            map.tiles == 6 &&
            (y < 3 ||
                y >= map.height - 3 &&
                    const {20, 21, 24}.contains(map.cell(x, y) & 127));
        final material = map.tiles == 6
            ? (hallWall ? 'hall-wall' : 'hall-floor')
            : buildingGround.contains(y * map.width + x)
            ? ModernTerrain.base(map.tiles)
            : ModernTerrain.sceneMaterial(
                map.tiles,
                map.cell(x, y) & 127,
                map.canWalk(x, y),
              );
        if (!art.drawGround(
          canvas,
          material,
          target,
          camera.left + column,
          hallWall && y >= map.height - 3
              ? y - (map.height - 3)
              : camera.top + row,
          _paint,
        )) {
          art.draw(
            canvas,
            '7:1:${map.tiles}',
            map.cell(x, y) & 127,
            target,
            _paint,
          );
        }
      }
    }
    // 地毯先铺，再画它上面的桌椅；覆盖集合只包含原地毯片，不包含整块矩形。
    for (final b in decorations.where((b) => b.floor)) {
      final point = camera.point(b.x, b.y);
      art.drawSprite(
        canvas,
        '${b.key}/0',
        Rect.fromLTWH(
          point.dx,
          point.dy,
          b.width * tileSize,
          b.height * tileSize,
        ),
        _paint..color = Colors.white,
      );
    }
    // 第二层逐格保留原结构：围墙、砖道、池沿、云气、石栏、椅凳和未知陈设均有图。
    for (var row = 0; row < camera.rows; row++) {
      for (var column = 0; column < camera.columns; column++) {
        final (x, y) = camera.sample(column, row);
        final index = y * map.width + x;
        if (!inside(x, y) ||
            foregroundCovered.contains(index) ||
            floorCovered.contains(index)) {
          continue;
        }
        final tile = map.cell(x, y) & 127,
            key = ModernTerrain.structureKey(map.tiles, tile);
        if (map.tiles == 6 &&
            ({20, 21, 24}.contains(tile) ||
                ModernTerrain.role(map.tiles, tile) == 'altar-object')) {
          // 墙面已按世界坐标连续铺设，供台已由完整物件接管；不叠回旧褐色碎片。
          continue;
        }
        if (map.tiles == 8) {
          // 洞壁沿原不可行走格绘制统一岩层，边缘明暗只标出真实的洞壁轮廓。
          if (!map.canWalk(x, y)) {
            final target = camera.target(column, row);
            if (map.canWalk(x, y - 1)) {
              canvas.drawLine(
                target.topLeft,
                target.topRight,
                _paint
                  ..color = const Color(0xff819389)
                  ..strokeWidth = tileSize * .047,
              );
            }
            if (map.canWalk(x, y + 1)) {
              canvas.drawLine(
                target.bottomLeft,
                target.bottomRight,
                _paint
                  ..color = const Color(0xff1f3030)
                  ..strokeWidth = tileSize * .094,
              );
            }
          }
          continue;
        }
        if (key == null) continue;
        if (!art.drawSprite(
          canvas,
          key,
          camera.target(column, row),
          _paint..color = Colors.white,
        )) {
          // 非完整包或后续漏配时仍保留原物件轮廓，不能静默丢失宝箱旁的陈设。
          art.draw(
            canvas,
            '7:1:${map.tiles}',
            tile,
            camera.target(column, row),
            _paint,
          );
        }
      }
    }
    final objects = <(double, VoidCallback)>[];
    for (final b in [...buildings, ...decorations.where((b) => !b.floor)]) {
      final point = camera.point(b.x, b.y);
      final visualHeight = (b.visualHeight ?? b.height.toDouble())
          .clamp(0.0, b.y + b.height.toDouble())
          .toDouble();
      final footprint = Rect.fromLTWH(
        point.dx,
        point.dy + (b.height - visualHeight) * tileSize,
        b.width * tileSize,
        visualHeight * tileSize,
      );
      if (!footprint.overlaps(const Rect.fromLTWH(0, 0, 640, 384))) continue;
      final owned = coveredBy(b).toSet();
      final protected = Path();
      var hasProtected = false;
      for (
        var yy = math.max(0, (b.y + b.height - visualHeight).floor());
        yy < b.y + b.height;
        yy++
      ) {
        for (var xx = b.x; xx < b.x + b.width; xx++) {
          if (owned.contains(yy * map.width + xx)) continue;
          final source = map.cell(xx, yy) & 127;
          final material = ModernTerrain.sceneMaterial(
            map.tiles,
            source,
            map.canWalk(xx, yy),
          );
          if (ModernTerrain.role(map.tiles, source) != 'floor' ||
              material == 'water' ||
              material == 'brick-road') {
            protected.addRect(
              Rect.fromLTWH(
                (xx - camera.left) * tileSize,
                (yy - camera.top) * tileSize,
                tileSize,
                tileSize,
              ),
            );
            hasProtected = true;
          }
        }
      }
      objects.add((
        b.y + b.height.toDouble(),
        () {
          canvas.save();
          if (hasProtected && map.tiles != 6) {
            final bounds = Path()..addRect(footprint);
            canvas.clipPath(
              Path.combine(PathOperation.difference, bounds, protected),
            );
          }
          art.drawObject(
            canvas,
            '${b.key}/0',
            footprint,
            _paint..color = Colors.white,
          );
          canvas.restore();
        },
      ));
    }
    objects.sort((a, b) => a.$1.compareTo(b.$1));
    for (final object in objects) {
      object.$2();
    }
    for (final point in game.route.take(12)) {
      canvas.drawCircle(
        camera.point(point.$1, point.$2) + Offset(tileSize / 2, tileSize * .6),
        2,
        _paint..color = const Color(0x997dd9c3),
      );
    }
    // 原引擎在地图之后绘制全部 NPC。交互机关不能被静态家具或屋顶挡掉。
    if (!overview || showActorsInOverview) {
      final actors = [...game.npcs.values, ?player]
        ..sort((a, b) => a.y.compareTo(b.y));
      for (final actor in actors) {
        final point = camera.point(actor.x, actor.y);
        if (point.dx < -160 ||
            point.dx > 800 ||
            point.dy < -192 ||
            point.dy > 512) {
          continue;
        }
        _drawActor(canvas, art, actor, point, tileSize);
      }
    }
    if (!overview) {
      _landmarks(canvas, art, camera);
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, 640, 384),
        _paint
          ..color = Colors.white
          ..shader = const RadialGradient(
            radius: 1.05,
            colors: [Colors.transparent, Color(0x330d2424)],
            stops: [.55, 1],
          ).createShader(const Rect.fromLTWH(0, 0, 640, 384)),
      );
      _paint.shader = null;
    }
    canvas.restore();
  }

  void _drawActor(
    Canvas canvas,
    ModernArt art,
    GameActor actor,
    Offset point,
    double tileSize,
  ) {
    if (actor.type == 4 && actor.name.contains('透明')) return;
    if (ModernWorldObjects.draw(
      canvas,
      game,
      actor,
      art,
      point,
      tileSize,
      textStyle,
    )) {
      return;
    }
    if (actor.type == 4 && actor.sprite == 10) {
      // 原剧情用四个石头机关封堵洞口。只换其画面，不删除 NPC、不改变坍塌
      // 剧情、位置或碰撞；经典 UI 继续使用原机关帧。
      if (art.drawObject(
        canvas,
        'plant:rock/0',
        Rect.fromLTWH(
          point.dx - tileSize * .4,
          point.dy - tileSize * .2,
          tileSize * 1.8,
          tileSize * 1.2,
        ),
        _paint..color = Colors.white,
      )) {
        return;
      }
    }
    final resource = actor.type == 1
        ? 'hero:${actor.index}'
        : '8:${actor.type}:${actor.sprite}';
    final frame =
        [0, 3, 6, 9][actor.direction.clamp(1, 4) - 1] +
        [0, 1, 2, 1][actor.step % 4];
    // 宝箱和透明机关使用自己的资源，不能与同编号 NPC 的高清人物切片混用。
    final hdKey = actor.type == 1 || actor.type == 2
        ? 'world:${actor.type == 1 ? 'hero' : 'npc'}:${actor.index}:${actor.direction.clamp(1, 4)}/${[0, 1, 2, 1][actor.step % 4]}'
        : null;
    final hd = hdKey == null ? null : art.sprites[hdKey];
    final source = art.frames['$resource/$frame'] ?? art.frames['$resource/0'];
    if (source == null && hd == null) return;
    // 身份同时通过轮廓大小区分：师傅高冠宽袍，孩童与小师弟明显矮于成年剑客。
    final stature = actor.type != 2
        ? 1.0
        : switch (actor.index) {
            1 => 1.08,
            2 => .78,
            _ => 1.0,
          };
    final h = hd == null
        ? source!.height * tileSize / 48
        : tileSize * 1.6 * stature;
    final w = hd == null
        ? source!.width * tileSize / 48
        : h * hd.rect.width / hd.rect.height;
    if (actor.type != 4) {
      canvas.drawOval(
        Rect.fromCenter(
          center: point + Offset(tileSize / 2, tileSize * .96),
          width: tileSize * .64,
          height: tileSize * .16,
        ),
        _paint..color = const Color(0x50212c22),
      );
    }
    final target = Rect.fromLTWH(
      actor.type == 4 ? point.dx : point.dx + tileSize / 2 - w / 2,
      point.dy + tileSize - h,
      w,
      h,
    );
    _paint.color = Colors.white;
    if (hdKey == null || !art.drawSprite(canvas, hdKey, target, _paint)) {
      art.draw(canvas, resource, frame, target, _paint);
    }
  }

  void _landmarks(Canvas canvas, ModernArt art, ModernMapCamera camera) {
    if (game.map?.id.startsWith('3:') == true) return;
    for (final item in art.landmarks[game.map?.id] ?? const <SceneLandmark>[]) {
      final building = (art.buildings[game.map?.id] ?? const <SceneBuilding>[])
          .where((b) => b.contains(item.x, item.y))
          .firstOrNull;
      final point = building == null
          ? camera.point(item.x.floor(), item.y.floor()) +
                Offset(
                  (item.x - item.x.floor()) * camera.tileSize,
                  -camera.tileSize * .35,
                )
          : camera.point(building.x, building.y) +
                Offset(
                  building.width * camera.tileSize / 2,
                  building.height *
                      camera.tileSize *
                      (building.key == 'building:cave-mouth' ? .27 : .6),
                );
      if (point.dx < -80 ||
          point.dx > 720 ||
          point.dy < -20 ||
          point.dy > 410) {
        continue;
      }
      final label = item.label,
          width = (label.length * 10.0 + 16).clamp(48.0, 112.0);
      final board = RRect.fromRectAndRadius(
        Rect.fromCenter(center: point, width: width, height: 20),
        const Radius.circular(2),
      );
      canvas.drawRRect(
        board,
        _paint
          ..style = PaintingStyle.fill
          ..color = const Color(0xef263f3a),
      );
      canvas.drawRRect(
        board,
        _paint
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = const Color(0xffbb9b61),
      );
      _paint.style = PaintingStyle.fill;
      _label(
        canvas,
        label,
        point - Offset(label.length * 5.0, 6),
        10,
        const Color(0xfff2dfad),
      );
    }
  }

  void _landscape(Canvas canvas, ModernArt art) {
    final type = game.map?.tiles;
    final key = type == 8
        ? 'cave'
        : [3, 5, 6, 7].contains(type)
        ? 'courtyard'
        : type == 9
        ? 'village'
        : 'forest';
    final background = art.backgrounds[key] ?? art.landscape;
    final source = Rect.fromLTWH(
      0,
      0,
      background.width.toDouble(),
      background.height.toDouble(),
    );
    canvas.drawImageRect(
      background,
      source,
      const Rect.fromLTWH(0, 0, 640, 384),
      _paint..color = Colors.white,
    );
  }

  void _battle(Canvas canvas, ModernArt art) {
    final battle = game.battle;
    if (battle == null) return;
    final layout = ModernBattleLayout(battle);
    final actors =
        [...battle.monsters, ...game.players].where((p) => p.visible).toList()
          ..sort((a, b) => layout.point(a).dy.compareTo(layout.point(b).dy));
    for (final actor in actors) {
      final point = layout.point(actor);
      final phase = math.max(0, actor.combatFrame - 1);
      final requested = actor.type == 1
          ? 'battle:hero:${actor.index}/$phase'
          : 'battle:monster:${actor.sprite}/$phase';
      final resting = actor.type == 1
          ? 'battle:hero:${actor.index}/0'
          : 'battle:monster:${actor.sprite}/0';
      // 原怪物低血帧号可能超出自身图片帧数，原渲染会回退首帧；新版也使用高清首帧。
      final key = art.sprites.containsKey(requested) ? requested : resting;
      final sprite = art.sprites[key];
      final resource = actor.type == 1
          ? '11:3:${actor.index}'
          : '8:3:${actor.sprite}';
      final source =
          art.frames['$resource/$phase'] ?? art.frames['$resource/0'];
      if (sprite == null && source == null) continue;
      final original = actor.type == 3
          ? game.data.image(8, 3, actor.sprite)
          : null;
      var height = actor.type == 1
          ? (sprite == null ? 114.0 : 144.0)
          : actor.sprite >= 33 && actor.sprite <= 40
          ? 156.0
          : actor.sprite <= 4 ||
                [
                  12,
                  13,
                  14,
                  15,
                  16,
                  17,
                  24,
                  41,
                  42,
                  43,
                  44,
                  45,
                  46,
                  47,
                  48,
                ].contains(actor.sprite)
          ? ((original?.height ?? 28) * 2.2).clamp(50.0, 100.0)
          : ((original?.height ?? 48) * 2.3).clamp(96.0, 156.0);
      if (actor.type == 3 && actor.sprite == 11) height = 144;
      if (actor.type == 3 && battle.presentationEnemies.indexOf(actor) == 1) {
        height = math.min(height, 112.0);
      }
      var width = sprite == null
          ? source!.width * height / source.height
          : sprite.rect.width * height / sprite.rect.height;
      final limit = actor.type == 1 ? 190.0 : 214.0;
      if (width > limit) {
        height *= limit / width;
        width = limit;
      }
      final selected =
          battle.phase == 'select' &&
          (battle.targetKind.isNotEmpty
              ? identical(
                  battle.targets.elementAtOrNull(battle.targetIndex),
                  actor,
                )
              : identical(battle.selectedPlayer, actor));
      canvas.drawOval(
        Rect.fromCenter(
          center: point + const Offset(0, 3),
          width: width * .68,
          height: 12,
        ),
        _paint..color = const Color(0x66353127),
      );
      if (selected) {
        canvas.drawOval(
          Rect.fromCenter(
            center: point + const Offset(0, 3),
            width: width * .86,
            height: 17,
          ),
          _paint
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.8
            ..color = const Color(0xffe0c682),
        );
        _paint.style = PaintingStyle.fill;
      }
      final idle = battle.current == null && actor.alive
          ? math.sin(game.ticks * .13 + actor.index) * .65
          : 0.0;
      final target = Rect.fromLTWH(
        point.dx - width / 2,
        point.dy - height + idle,
        width,
        height,
      );
      _paint.color = Colors.white;
      if (!art.drawSprite(canvas, key, target, _paint)) {
        art.draw(canvas, resource, phase, target, _paint);
      }
      final statuses = [
        for (final bit in [(8, '毒'), (4, '乱'), (2, '封'), (1, '眠')])
          if (actor.status & bit.$1 != 0) bit.$2,
      ].join('');
      if (statuses.isNotEmpty) {
        _label(
          canvas,
          statuses,
          point + Offset(-statuses.length * 5.0, -height - 28),
          10,
          const Color(0xffe0db9d),
        );
      }
      if (selected) {
        _label(
          canvas,
          '◆',
          point + Offset(-5, -height - 16),
          12,
          const Color(0xfff0d89d),
        );
      }
    }
    final action = battle.current;
    if (action != null && action.stage == 1 && action.movie != null) {
      for (final target in action.targets.where((p) => p.visible)) {
        final center = layout.point(target) + const Offset(0, -48),
            phase = game.ticks % 16 / 16;
        final healing = (action.changes[target] ?? 0) > 0;
        final color = healing
            ? const Color(0xff93dbb1)
            : const Color(0xffebd7a2);
        for (var i = 0; i < 3; i++) {
          final radius = 18 + phase * 28 + i * 8;
          canvas.drawOval(
            Rect.fromCenter(
              center: center + Offset(0, i * 5.0),
              width: radius * 2,
              height: radius * .75,
            ),
            _paint
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.7
              ..color = color.withValues(alpha: (1 - phase) * .8),
          );
        }
        _paint.style = PaintingStyle.fill;
        for (var i = 0; i < 9; i++) {
          final angle = i * math.pi * 2 / 9 + phase * 2;
          canvas.drawCircle(
            center +
                Offset(
                  math.cos(angle) * (16 + phase * 24),
                  math.sin(angle) * (22 + phase * 30),
                ),
            1.5,
            _paint..color = color.withValues(alpha: 1 - phase),
          );
        }
      }
    }
    for (final raise in battle.visibleRaises.where(
      (r) =>
          r.showing &&
          (r.actor == null ||
              r.actor?.type == 1 ||
              battle.presentationEnemies.contains(r.actor)),
    )) {
      _label(
        canvas,
        '${raise.delta > 0 ? '+' : ''}${raise.delta}',
        layout.raisePoint(raise),
        22,
        raise.delta > 0 ? const Color(0xffb5ecc2) : const Color(0xffffdfb1),
      );
    }
  }

  void _label(
    Canvas canvas,
    String value,
    Offset offset,
    double fontSize,
    Color color,
  ) {
    final text = TextPainter(
      text: TextSpan(
        text: value,
        style: (textStyle ?? const TextStyle()).copyWith(
          color: color,
          fontSize: fontSize,
          shadows: const [
            Shadow(color: Colors.black, blurRadius: 3, offset: Offset(0, 1)),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    text.paint(canvas, offset);
    text.dispose();
  }

  @override
  bool shouldRepaint(covariant ModernScenePainter oldDelegate) => true;
}

/// 独立放大头像，使用有来源记录的角色轮廓和新版肤色、发色材质。
final class PortraitPainter extends CustomPainter {
  PortraitPainter(this.index, this.name, this.art);
  final int index;
  final String name;
  final ModernArt? art;
  @override
  void paint(Canvas canvas, Size size) {
    final art = this.art;
    if (art == null || index < 1 || index > 3) return;
    final paint = Paint()..filterQuality = FilterQuality.medium;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(4)),
      paint
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xff476b66), Color(0xff1c3434)],
        ).createShader(Offset.zero & size),
    );
    paint.shader = null;
    final target = Rect.fromLTWH(
      size.width * .03,
      size.height * .02,
      size.width * .94,
      size.height * .96,
    );
    if (!art.drawPortrait(
      canvas,
      'portrait:hero:$index/0',
      target,
      paint..color = Colors.white,
    )) {
      art.draw(canvas, '11:1:$index', 0, target, paint..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(covariant PortraitPainter oldDelegate) =>
      index != oldDelegate.index || art != oldDelegate.art;
}

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import '../../domain/use_cases/strategy_commands.dart';
import '../core/native_game_session.dart';
import 'baye_draw_command.dart';
import 'cartoon_assets.dart';
import 'cartoon_scene_art.dart';
import 'game_art.dart';
import 'modern_game_painter.dart';
import 'selection_art.dart';
import 'war_report_art.dart';

/// 已确认写实卡通设计的运行时绘制。地图和单位读取真实世界，不使用效果稿截图。
///
/// 完整底图后只重放原版弹层；黑白帧、输入回调、动画时钟与随机数均由原会话拥有。
/// 战略图复用原矩阵布局；菜单、城池与点击始终使用原240×144坐标。
final class RealisticGamePainter extends CustomPainter {
  RealisticGamePainter(this.session, this.assets, {required this.revision})
    : commands = session.canvas.commands;
  final NativeGameSession session;
  final CartoonAssets assets;
  final int revision;
  final List<BayeDrawCommand> commands;

  @override
  void paint(ui.Canvas canvas, ui.Size size) {
    final base = commands.lastIndexWhere((op) => op.kind == BayeDrawKind.base);
    final report = session.visualReport;
    if (base < 0 ||
        commands[base].text == 'strategy' ||
        report != null && WarReportArt.supports(report.kind)) {
      ModernGamePainter(session, assets: assets).paint(canvas, size);
      return;
    }
    final scale = math.min(size.width / 240, size.height / 144);
    canvas.drawColor(const ui.Color(0xff14292f), ui.BlendMode.src);
    canvas.save();
    canvas.translate(
      (size.width - 240 * scale) / 2,
      (size.height - 144 * scale) / 2,
    );
    canvas.scale(scale);
    canvas.clipRect(const ui.Rect.fromLTWH(0, 0, 240, 144));
    final art = GameArt(canvas, assets: assets);
    if (commands[base].text == 'battle') {
      _battle(art);
    }
    ModernGamePainter(
      session,
      assets: assets,
    ).paintUi(art, commands.skip(base + 1));
    canvas.restore();
  }

  /// 在真实地形格上拼出连续水岸，样式去格线，寻路与攻击范围仍使用原格坐标。
  ui.Path _mask(bool Function(int, int) value, int cols, int rows) {
    final edges = <(int, int), List<(int, int)>>{};
    bool yes(int x, int y) =>
        x >= 0 && y >= 0 && x < cols && y < rows && value(x, y);
    void add((int, int) a, (int, int) b) =>
        edges.putIfAbsent(a, () => []).add(b);
    for (var y = 0; y < rows; y++) {
      for (var x = 0; x < cols; x++) {
        if (!yes(x, y)) continue;
        if (!yes(x, y - 1)) add((x, y), (x + 1, y));
        if (!yes(x + 1, y)) add((x + 1, y), (x + 1, y + 1));
        if (!yes(x, y + 1)) add((x + 1, y + 1), (x, y + 1));
        if (!yes(x - 1, y)) add((x, y + 1), (x, y));
      }
    }
    final result = ui.Path()..fillType = ui.PathFillType.evenOdd;
    while (edges.isNotEmpty) {
      final first = edges.keys.first;
      var current = first;
      final points = <ui.Offset>[];
      for (var guard = 0; guard < 2000; guard++) {
        points.add(ui.Offset(current.$1 * 16.0, current.$2 * 16.0));
        final choices = edges[current];
        if (choices == null || choices.isEmpty) {
          edges.remove(current);
          break;
        }
        final next = choices.removeAt(0);
        if (choices.isEmpty) edges.remove(current);
        current = next;
        if (current == first) break;
      }
      if (points.length < 3) continue;
      for (var i = 0; i < points.length; i++) {
        final a = points[(i + points.length - 1) % points.length],
            b = points[i],
            c = points[(i + 1) % points.length];
        final before = (a - b).distance, after = (c - b).distance;
        if (before == 0 || after == 0) continue;
        final r = math.min(4.5, math.min(before, after) * .4);
        final start = b + (a - b) / before * r, end = b + (c - b) / after * r;
        if (i == 0) {
          result.moveTo(start.dx, start.dy);
        } else {
          result.lineTo(start.dx, start.dy);
        }
        result.quadraticBezierTo(b.dx, b.dy, end.dx, end.dy);
      }
      result.close();
    }
    return result;
  }

  /// 地表纹理锚定世界坐标，镜头移动时地面不会随屏幕漂移。无常驻格线。
  void _ground(
    GameArt art,
    int viewX,
    int viewY, {
    String? sprite,
    double opacity = 1,
  }) {
    const length = 128.0;
    final left = -(viewX * 16 % 128).toDouble(),
        top = -(viewY * 16 % 128).toDouble();
    final source = ui.Rect.fromLTWH(
      0,
      0,
      assets.texture.width.toDouble(),
      assets.texture.height.toDouble(),
    );
    for (var y = top; y < 128; y += length) {
      for (var x = left; x < 240; x += length) {
        final rect = ui.Rect.fromLTWH(x, y, length, length);
        if (sprite != null) {
          assets.sprite(art.canvas, sprite, rect, opacity: opacity);
        } else {
          art.canvas.drawImageRect(
            assets.texture,
            source,
            rect,
            ui.Paint()..filterQuality = ui.FilterQuality.medium,
          );
        }
      }
    }
  }

  static String _arms(int value) => value >= 100000000
      ? '${(value / 100000000).toStringAsFixed(1)}亿'
      : value >= 10000
      ? '${(value / 10000).toStringAsFixed(1)}万'
      : '$value';

  /// 地物共用原逻辑格的落地点，轻微改变外形大小，减弱重复切片的拼贴感。
  ///
  /// 参数完全由世界格坐标确定，镜头滚动不会使山树跳动，也不消费世界随机数。
  /// 阴影与图片都限制在原格附近；碰撞、可达范围和触摸位置继续由原引擎决定。
  void _terrainProp(
    GameArt art,
    ui.Rect cell,
    String key,
    int worldX,
    int worldY, {
    bool natural = false,
  }) {
    final hash = ((worldX * 73) ^ (worldY * 137)) & 0x7fffffff;
    final scale = natural ? .89 + (hash % 4) * .035 : 1.0;
    final width = (natural ? 18.0 : 16.0) * scale;
    final height = (natural ? 18.0 : 16.0) * scale;
    final center = ui.Offset(cell.center.dx, cell.bottom - 1.5);
    art.canvas.drawOval(
      ui.Rect.fromCenter(center: center, width: 12 * scale, height: 2.5),
      art.paint(const ui.Color(0x283d392c)),
    );
    final rect = ui.Rect.fromLTWH(
      cell.center.dx - width / 2,
      cell.bottom - height - (natural ? 1 : 0),
      width,
      height,
    );
    art.canvas.save();
    if (natural && hash.isOdd) {
      art.canvas.translate(cell.center.dx * 2, 0);
      art.canvas.scale(-1, 1);
    }
    assets.sprite(art.canvas, key, rect);
    art.canvas.restore();
  }

  void _battle(GameArt art) {
    final battle = session.activeBattle, world = session.world;
    if (battle == null || world == null) return;
    final canvas = art.canvas;
    canvas.save();
    canvas.clipRect(const ui.Rect.fromLTWH(0, 0, 240, 128));
    _ground(art, battle.viewX, battle.viewY);
    final paths = <int, ui.Path>{};
    for (final type in [1, 4, 5, 6, 7]) {
      paths[type] = _mask(
        (x, y) => battle.terrain(battle.viewX + x, battle.viewY + y) == type,
        15,
        8,
      );
    }
    final dirt = ui.Path();
    for (final type in [1, 4, 5, 6]) {
      dirt.addPath(paths[type]!, ui.Offset.zero);
    }
    canvas.save();
    canvas.clipPath(dirt);
    _ground(
      art,
      battle.viewX,
      battle.viewY,
      sprite: 'ground/dirt',
      opacity: .53,
    );
    canvas.restore();
    final water = paths[7]!;
    canvas.drawPath(water, art.paint(const ui.Color(0xff887f61), stroke: 2.6));
    canvas.drawPath(water, art.paint(const ui.Color(0xffc3b68c), stroke: 1.3));
    canvas.save();
    canvas.clipPath(water);
    _ground(art, battle.viewX, battle.viewY, sprite: 'ground/water');
    canvas.restore();
    canvas.drawPath(water, art.paint(const ui.Color(0xffb9d1ca), stroke: .45));
    final cityCells = <ui.Rect>[];
    for (var y = 0; y < 8; y++) {
      for (var x = 0; x < 15; x++) {
        final type = battle.terrain(battle.viewX + x, battle.viewY + y);
        final rect = ui.Rect.fromLTWH(x * 16.0, y * 16.0, 16, 16);
        if (type == 2 || type == 3 || type == 4 || type == 6) {
          _terrainProp(
            art,
            rect,
            type == 2
                ? 'terrain/mountain'
                : type == 3
                ? 'terrain/tree'
                : type == 4
                ? 'terrain/village'
                : 'terrain/camp',
            battle.viewX + x,
            battle.viewY + y,
            natural: type == 2 || type == 3,
          );
        }
        if (type == 5) {
          cityCells.add(rect);
          art.rounded(
            rect.deflate(.35),
            const ui.Color(0xffd5cfb8),
            radius: 1.5,
          );
          art.rounded(
            rect.deflate(.35),
            const ui.Color(0xff615f50),
            radius: 1.5,
            stroke: .65,
          );
          // 城门保持城格中心与地面锚点，高出的门楼可越过驻军头顶；
          // 只放大绘制范围，原16点逻辑格、攻城判定和点击坐标不变。
          final gate = ui.Rect.fromLTWH(rect.left - 5, rect.top - 12, 26, 28);
          if (!assets.sprite(canvas, 'city/battle', gate)) {
            art.fortress(rect, art.gold, capital: true);
          }
        }
      }
    }
    var moving = false, attacking = false;
    for (final index in [0, 1]) {
      // 直接消费原引擎产生的可达格、攻击格，不用美术估算重建战斗规则。
      final points = {
        for (final op in commands)
          if (op.kind == BayeDrawKind.picture &&
              op.resource == 7 &&
              op.index == index)
            (op.x ~/ 16, op.y ~/ 16),
      };
      if (points.isEmpty) continue;
      if (index == 0) {
        moving = true;
      } else {
        attacking = true;
      }
      final path = _mask((x, y) => points.contains((x, y)), 15, 8);
      final color = index == 0
          ? const ui.Color(0xffeed894)
          : const ui.Color(0xffc9763e);
      canvas.drawPath(path, art.paint(color.withValues(alpha: .32)));
      canvas.drawPath(path, art.paint(const ui.Color(0xfffff0bb), stroke: .65));
      for (final point in points) {
        canvas.drawCircle(
          ui.Offset(point.$1 * 16 + 8.0, point.$2 * 16 + 8.0),
          index == 0 ? .8 : 1.25,
          art.paint(color),
        );
      }
    }
    final types = StrategyCommands(session.resources);
    const badges = ['骑', '步', '弓', '水', '极', '玄'];
    final fx = (battle.focusX - battle.viewX) * 16.0,
        fy = (battle.focusY - battle.viewY) * 16.0;
    final movie = session.movieVisual;
    final focusedDeath =
        movie?.effect == 'defeat' && movie?.x == fx && movie?.y == fy;
    final focusCell =
        !focusedDeath && fx >= 0 && fy >= 0 && fx < 240 && fy < 128
        ? ui.Rect.fromLTWH(fx, fy, 16, 16)
        : null;
    final selection = commands
        .lastWhere((op) => op.kind == BayeDrawKind.base && op.text == 'battle')
        .index;
    ui.Rect? selectedCell;
    if (selection >= 0 &&
        selection < battle.units.length &&
        battle.people[selection] != null &&
        battle.units[selection].state != 8) {
      final unit = battle.units[selection],
          x = (unit.x - battle.viewX) * 16.0,
          y = (unit.y - battle.viewY) * 16.0;
      if (x >= 0 && y >= 0 && x < 240 && y < 128) {
        selectedCell = ui.Rect.fromLTWH(x, y, 16, 16);
      }
    }
    if (selectedCell != null) SelectionArt.backdrop(art, selectedCell);
    if (focusCell != null && selection < 0) {
      SelectionArt.backdrop(art, focusCell);
    }
    // 框位于实体和军牌下层，城名、兵种、兵力与生命条不会被描边覆盖。
    if (selectedCell != null) SelectionArt.outline(art, selectedCell);
    if (focusCell != null && focusCell != selectedCell) {
      if (selection >= 0) {
        SelectionArt.cursor(art, focusCell);
      } else {
        SelectionArt.outline(art, focusCell);
      }
    }
    for (final op in commands) {
      if (op.kind != BayeDrawKind.picture || op.resource != 5) continue;
      final x = op.x ~/ 16 + battle.viewX, y = op.y ~/ 16 + battle.viewY;
      final slot = battle.unitAt(x, y);
      if (slot == null) continue;
      final unit = battle.units[slot], id = battle.people[slot];
      if (id == null || unit.state == 8 || (slot >= 10 && unit.state == 7)) {
        continue;
      }
      final p = world.person(id);
      // 原版图块与在场状态拥有退场顺序。群攻会先扣完兵力，再逐人播死亡动画，
      // 因此不能用已归零的兵力提前隐藏后续目标。零兵入场仍由引擎初始化拦截。
      if (p == null) continue;
      final index = op.index % 16;
      final type = (index == 12 || index == 13 ? 3 : types.armType(world, p))
          .clamp(0, 5);
      final rect = ui.Rect.fromLTWH(op.x.toDouble(), op.y - 1.0, 16, 17);
      final color = slot < 10 ? CartoonSceneArt.red : CartoonSceneArt.blue;
      canvas.drawOval(
        ui.Rect.fromLTWH(rect.left + 2, rect.top + 12, 13, 4),
        art.paint(const ui.Color(0x49333129)),
      );
      art.soldier(
        rect,
        type,
        color,
        frame: op.index % 2,
        inactive: unit.active != 0,
        state: unit.state,
        facingLeft: slot >= 10,
        battlefield: true,
      );
      // 外形、整片阵营甲色和单字兵种标记同时提供辨识信息，色觉差异也能区分。
      art.rounded(
        ui.Rect.fromLTWH(rect.left, rect.bottom - 5, 5, 5),
        color,
        radius: .7,
      );
      art.text(
        badges[type],
        ui.Rect.fromLTWH(rect.left, rect.bottom - 5, 5, 5),
        size: 4.5,
        color: art.paper,
        bold: true,
        align: ui.TextAlign.center,
      );
      art.rounded(
        ui.Rect.fromLTWH(rect.left + 5.2, rect.bottom - 5, 10.8, 5),
        const ui.Color(0xe8223032),
        radius: .5,
      );
      art.text(
        _arms(p.arms),
        ui.Rect.fromLTWH(rect.left + 5.2, rect.bottom - 5, 10.8, 5),
        size: 4.1,
        color: const ui.Color(0xfffff8dc),
        align: ui.TextAlign.center,
      );
      final maxHp = math.max(
        1,
        (p.force * 80 ~/ 100 + p.iq * 30 ~/ 100 + p.level) * p.thew ~/ 100,
      );
      art.rounded(
        ui.Rect.fromLTWH(rect.left, rect.bottom - .25, 16, .8),
        const ui.Color(0xff28312b),
        radius: .3,
      );
      art.rounded(
        ui.Rect.fromLTWH(
          rect.left,
          rect.bottom - .25,
          16 * (unit.hp / maxHp).clamp(0, 1),
          .8,
        ),
        color,
        radius: .3,
      );
      if (unit.active != 0) {
        art.text(
          '✓',
          ui.Rect.fromLTWH(rect.right - 5, rect.top, 5, 5),
          size: 5,
          bold: true,
          color: const ui.Color(0xfff6edca),
        );
      }
      CartoonSceneArt(art).status(rect, unit.state);
    }
    // 城池标记在驻守部队之后绘制，守将站在城格上时仍能看出城池位置。
    for (final cell in cityCells) {
      final color = battle.mode == 1
          ? CartoonSceneArt.blue
          : CartoonSceneArt.red;
      art.rounded(
        ui.Rect.fromLTWH(cell.left + 2, cell.top + 2, 4.3, 4.5),
        const ui.Color(0xef293b42),
        radius: .6,
      );
      art.text(
        '城',
        ui.Rect.fromLTWH(cell.left + 2, cell.top + 2, 4.3, 4.5),
        size: 3.8,
        bold: true,
        color: art.paper,
        align: ui.TextAlign.center,
      );
      art.path([
        ui.Offset(cell.left + 10, cell.top + 2),
        ui.Offset(cell.left + 14.5, cell.top + 2.6),
        ui.Offset(cell.left + 13, cell.top + 4.5),
        ui.Offset(cell.left + 10, cell.top + 4),
      ], color);
      canvas.drawLine(
        ui.Offset(cell.left + 10, cell.top + 1.5),
        ui.Offset(cell.left + 10, cell.top + 6.8),
        art.paint(art.outline, stroke: .55),
      );
    }
    canvas.restore();
    art.panel(const ui.Rect.fromLTWH(0, 128, 240, 16));
    final scenes = CartoonSceneArt(
      art,
      terrain: battle.terrain(battle.focusX, battle.focusY),
    );
    scenes.supplies(const ui.Rect.fromLTWH(1, 130, 10, 11));
    art.text(
      '${battle.playerFood}',
      const ui.Rect.fromLTWH(12, 129, 33, 7),
      size: 6.5,
      bold: true,
      color: CartoonSceneArt.red,
    );
    art.text(
      '第${battle.day}日',
      const ui.Rect.fromLTWH(12, 136, 33, 7),
      size: 6,
      color: art.outline,
    );
    scenes.weather(const ui.Rect.fromLTWH(47, 130, 11, 11), battle.weather - 1);
    final candidate = battle.unitAt(battle.focusX, battle.focusY);
    final selected =
        candidate != null &&
            !(candidate >= 10 && battle.units[candidate].state == 7)
        ? candidate
        : null;
    if (selected == null) {
      const names = ['草地', '平原', '山地', '森林', '村庄', '城池', '营寨', '河流'];
      final terrain = battle.terrain(battle.focusX, battle.focusY);
      art.text(
        terrain < names.length ? names[terrain] : '战场',
        const ui.Rect.fromLTWH(63, 129, 57, 14),
        size: 9,
        bold: true,
      );
      art.text(
        attacking
            ? '橙色区域可攻击'
            : moving
            ? '金色区域可移动'
            : '选择部队查看军情',
        const ui.Rect.fromLTWH(120, 130, 116, 12),
        size: 7.5,
        align: ui.TextAlign.right,
      );
    } else {
      final id = battle.people[selected],
          p = id == null ? null : world.person(id),
          unit = battle.units[selected];
      final color = selected < 10 ? CartoonSceneArt.red : CartoonSceneArt.blue;
      final type = p == null ? 0 : types.armType(world, p).clamp(0, 5);
      art.text(
        '${selected < 10 ? '我' : '敌'} · ${session.resources.personName(world.period, id ?? -1)}  ${badges[type]}',
        const ui.Rect.fromLTWH(63, 128, 105, 8),
        size: 7,
        bold: true,
        color: color,
      );
      art.text(
        '生命${unit.hp}  技力${unit.mp}  ${unit.active == 0 ? '可行动' : '已行动'}',
        const ui.Rect.fromLTWH(63, 136, 123, 7),
        size: 6,
        color: art.outline,
      );
      art.text(
        '${p?.arms ?? 0}兵',
        const ui.Rect.fromLTWH(170, 129, 66, 8),
        size: 7,
        bold: true,
        color: color,
        align: ui.TextAlign.right,
      );
    }
  }

  @override
  bool shouldRepaint(RealisticGamePainter oldDelegate) =>
      oldDelegate.revision != revision ||
      !identical(oldDelegate.assets, assets) ||
      !identical(oldDelegate.session, session);
}

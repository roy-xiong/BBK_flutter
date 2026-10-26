import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import '../core/native_game_session.dart';
import '../../domain/use_cases/strategy_commands.dart';
import 'baye_draw_command.dart';
import 'cartoon_scene_art.dart';
import 'game_art.dart';
import 'cartoon_assets.dart';
import 'cartoon_map_layout.dart';
import 'selection_art.dart';
import 'war_report_art.dart';

/// 将原生表现指令重放为彩色手绘画面。输入、状态机、寻路及随机数仍由原会话唯一拥有。
///
/// 使用与黑白模式相同的 240×144 坐标，所有菜单、数字、触摸热区在切换后仍准确。
/// 不创建后台图片或定时器；绘制依赖 frameVersion，离开页面即可释放所有画面对象。
final class ModernGamePainter extends CustomPainter {
  ModernGamePainter(this.session, {this.ink = false, this.assets})
    : revision = session.frameVersion,
      commands = session.canvas.commands;
  final NativeGameSession session;
  final bool ink;
  final CartoonAssets? assets;
  final int revision;
  final List<BayeDrawCommand> commands;

  /// 布景只读取当前战场地形，不创建另一套坐标、状态机或动画时钟。
  CartoonSceneArt _sceneArt(GameArt art) {
    final battle = session.activeBattle;
    return CartoonSceneArt(
      art,
      terrain: battle?.terrain(battle.focusX, battle.focusY) ?? 0,
    );
  }

  @override
  void paint(ui.Canvas canvas, ui.Size size) {
    final w = session.canvas.width.toDouble(),
        h = session.canvas.height.toDouble();
    final scale = math.min(size.width / w, size.height / h);
    canvas.drawColor(ui.Color(ink ? 0xffd5d1c5 : 0xffe4eef1), ui.BlendMode.src);
    canvas.save();
    canvas.translate(
      (size.width - w * scale) / 2,
      (size.height - h * scale) / 2,
    );
    canvas.scale(scale);
    canvas.clipRect(ui.Rect.fromLTWH(0, 0, w, h));
    final art = GameArt(canvas, ink: ink, assets: assets);
    if (_paintWarReport(art)) {
      canvas.restore();
      return;
    }
    final scene = session.scene;
    if ([
      NativeScene.intro,
      NativeScene.credits,
      NativeScene.mainMenu,
      NativeScene.periodMenu,
    ].contains(scene)) {
      _opening(art, w, h);
      canvas.restore();
      return;
    }
    canvas.drawRect(ui.Rect.fromLTWH(0, 0, w, h), art.paint(art.paper));
    final strategy = commands.any(
      (op) => op.kind == BayeDrawKind.picture && op.resource == 54,
    );
    final battle = commands.any(
      (op) => op.kind == BayeDrawKind.picture && op.resource == 4,
    );
    if (strategy) _strategy(art, w, h);
    if (battle) _battle(art, w, h);
    if (scene == NativeScene.battleSituation) _situation(art, w, h);
    // 字符在原版 reverse 高亮后应保持可读；先绘制选中底色，再重放这一区域文字。
    final glyphs = <BayeDrawCommand>[];
    for (final op in commands) {
      final rect = ui.Rect.fromLTRB(
        op.x.toDouble(),
        op.y.toDouble(),
        op.right.toDouble() + 1,
        op.bottom.toDouble() + 1,
      );
      switch (op.kind) {
        case BayeDrawKind.fill:
          // 动画清除仍作用于黑白帧；卡通动画按语义绘制，不能清掉下层地图。
          if (op.resource != 0) continue;
          glyphs.removeWhere(
            (glyph) => rect.contains(
              ui.Offset(
                (glyph.x + glyph.right) / 2,
                (glyph.y + glyph.bottom) / 2,
              ),
            ),
          );
          if (rect.width > 2 && rect.height > 2) {
            art.panel(rect, color: op.color == 0 ? art.paper : art.land);
          } else if (op.color != 0 && scene != NativeScene.battleSituation) {
            canvas.drawCircle(rect.center, .65, art.paint(art.outline));
          }
        case BayeDrawKind.line:
          canvas.drawLine(
            rect.topLeft,
            ui.Offset(op.right.toDouble(), op.bottom.toDouble()),
            art.paint(art.outline.withValues(alpha: .3), stroke: .5),
          );
        case BayeDrawKind.reverse:
          if (rect.width > 3) {
            art.rounded(rect, art.gold.withValues(alpha: .7), radius: 2);
            for (final glyph in glyphs) {
              if (rect.overlaps(
                ui.Rect.fromLTRB(
                  glyph.x.toDouble(),
                  glyph.y.toDouble(),
                  glyph.right.toDouble(),
                  glyph.bottom.toDouble(),
                ),
              )) {
                _glyph(art, glyph);
              }
            }
          }
        case BayeDrawKind.glyph:
          _glyph(art, op);
          glyphs.add(op);
        case BayeDrawKind.picture:
          _picture(art, op, rect);
        case BayeDrawKind.bitmap:
          // 在原播放器当前帧上统一绘制，避免把清除过的历史位图再次叠到画面。
          break;
        case BayeDrawKind.base:
          break;
      }
    }
    final movie = session.movieVisual;
    if (movie != null && scene == NativeScene.processing && battle) {
      _sceneArt(art).movie(
        movie,
        ui.Rect.fromLTWH(
          ((w - 130) ~/ 2).toDouble(),
          ((h - 64) ~/ 2).toDouble(),
          130,
          64,
        ),
      );
    }
    if (strategy && scene == NativeScene.strategy) _strategyLegend(art, w);
    _ending(art, w, h);
    canvas.restore();
  }

  /// 写实底图之上的原版菜单、数字框和报告，继续使用原热区与换行规则。
  void paintUi(GameArt art, Iterable<BayeDrawCommand> operations) {
    if (_paintWarReport(art)) return;
    final glyphs = <BayeDrawCommand>[];
    for (final op in operations) {
      final rect = ui.Rect.fromLTRB(
        op.x.toDouble(),
        op.y.toDouble(),
        op.right + 1.0,
        op.bottom + 1.0,
      );
      switch (op.kind) {
        case BayeDrawKind.fill:
          if (op.resource != 0) continue;
          glyphs.removeWhere(
            (g) => rect.contains(
              ui.Offset((g.x + g.right) / 2, (g.y + g.bottom) / 2),
            ),
          );
          if (rect.width > 2 && rect.height > 2) {
            art.panel(rect, color: op.color == 0 ? art.paper : art.land);
          }
        case BayeDrawKind.line:
          art.canvas.drawLine(
            rect.topLeft,
            ui.Offset(op.right.toDouble(), op.bottom.toDouble()),
            art.paint(art.outline.withValues(alpha: .35), stroke: .5),
          );
        case BayeDrawKind.glyph:
          _glyph(art, op);
          glyphs.add(op);
        case BayeDrawKind.reverse:
          art.rounded(rect, art.gold.withValues(alpha: .55), radius: 1.5);
          for (final g in glyphs) {
            if (rect.overlaps(
              ui.Rect.fromLTRB(
                g.x.toDouble(),
                g.y.toDouble(),
                g.right.toDouble(),
                g.bottom.toDouble(),
              ),
            )) {
              _glyph(art, g);
            }
          }
        case BayeDrawKind.picture:
          _picture(art, op, rect);
        case BayeDrawKind.bitmap:
        case BayeDrawKind.base:
          break;
      }
    }
    final movie = session.movieVisual;
    if (movie != null &&
        session.scene == NativeScene.processing &&
        session.activeBattle != null) {
      _sceneArt(art).movie(
        movie,
        ui.Rect.fromLTWH(
          ((session.canvas.width - 130) ~/ 2).toDouble(),
          ((session.canvas.height - 64) ~/ 2).toDouble(),
          130,
          64,
        ),
      );
    }
    _ending(
      art,
      session.canvas.width.toDouble(),
      session.canvas.height.toDouble(),
    );
  }

  bool _paintWarReport(GameArt art) {
    final report = session.visualReport, world = session.world;
    if (assets == null ||
        report == null ||
        world == null ||
        !WarReportArt.supports(report.kind)) {
      return false;
    }
    WarReportArt(art, session.resources, world, report).paint();
    return true;
  }

  void _glyph(GameArt art, BayeDrawCommand op) {
    // 原版底栏只显示粮草末三位；卡通模式在同一宽度内显示完整数值，避免5000变000。
    if (session.activeBattle != null &&
        op.y == session.canvas.height - 13 &&
        op.x >= 14 &&
        op.x < 47) {
      return;
    }
    art.text(
      op.text,
      ui.Rect.fromLTRB(
        op.x.toDouble(),
        op.y.toDouble() + .4,
        op.right.toDouble() + .5,
        op.bottom.toDouble(),
      ),
      size: 10.7,
      color: art.outline,
      bold: op.color != 0,
    );
  }

  void _opening(GameArt art, double w, double h) {
    art.geography(ui.Rect.fromLTWH(0, 0, w, h));
    art.panel(
      ui.Rect.fromLTWH(6, 6, w - 12, h - 12),
      color: art.paper.withValues(alpha: .92),
    );
    art.portrait(ui.Rect.fromLTWH(164, 55, 62, 75), seed: 2);
    final periodMenu = session.scene == NativeScene.periodMenu;
    art.text(
      periodMenu ? '选择历史时期' : '三国霸业',
      ui.Rect.fromLTWH(12, periodMenu ? 2 : 10, 215, periodMenu ? 19 : 26),
      size: periodMenu ? 16 : 22,
      bold: true,
    );
    if (!periodMenu) {
      art.text(
        ink ? '水墨山河 · 群雄逐鹿' : '群雄逐鹿 · 一统山河',
        ui.Rect.fromLTWH(14, 35, 210, 14),
        size: 8,
        color: art.forest,
      );
    }
    if (session.scene == NativeScene.mainMenu ||
        session.scene == NativeScene.periodMenu) {
      final period = session.scene == NativeScene.periodMenu;
      final coords = session.resources.ruleArray(
        period ? 'periodMenuButtonRects' : 'mainMenuButtonRects',
      );
      final labels = period
          ? ['董卓弄权', '曹操崛起', '赤壁之战', '三国鼎立']
          : ['新游戏', '读取进度', '制作名单', '退出游戏'];
      for (var i = 0; i < 4; i++) {
        final offset = i * 4;
        final rect = coords.length >= offset + 4
            ? ui.Rect.fromLTRB(
                coords[offset].toDouble(),
                coords[offset + 1].toDouble(),
                coords[offset + 2].toDouble() + 1,
                coords[offset + 3].toDouble() + 1,
              )
            : ui.Rect.fromLTWH(102, 50 + i * 20, 106, 18);
        art.rounded(
          rect,
          session.selection == i ? art.gold : art.land,
          radius: 3,
        );
        art.text(
          labels[i],
          rect.deflate(1),
          size: math.min(11, rect.height - 2),
          bold: true,
          align: ui.TextAlign.center,
        );
      }
    } else {
      art.text(
        session.scene == NativeScene.credits ? '三国霸业 · 制作名单' : '点击画面或按确认键开始',
        ui.Rect.fromLTWH(87, 100, 143, 20),
        size: 9,
      );
    }
  }

  void _strategy(GameArt art, double w, double h) {
    final world = session.world;
    if (world == null) return;
    final columns = ((w + 1) ~/ 16) - 2;
    final area = ui.Rect.fromLTWH(0, 0, columns * 16, h);
    art.canvas.save();
    art.canvas.clipRect(area);
    final full = ui.Rect.fromLTWH(
      -world.viewX * 16,
      -world.viewY * 16,
      session.resources.mapWidth * 16.0,
      session.resources.mapHeight * 16.0,
    );
    art.geography(full);
    final layout = CartoonMapLayout(
      session.resources,
      viewX: world.viewX,
      viewY: world.viewY,
    );
    if (session.mapRoadsVisible) {
      final links = StrategyCommands(
        session.resources,
        options: session.options,
      );
      for (var city = 0; city < world.cities.length; city++) {
        for (final next in links.neighbours(city)) {
          if (next <= city || next >= world.cities.length) continue;
          final a = layout.city(city), b = layout.city(next);
          if (a == null || b == null) continue;
          art.canvas.drawLine(
            a,
            b,
            art.paint(art.paper.withValues(alpha: .65), stroke: 1.5),
          );
          art.canvas.drawLine(
            a,
            b,
            art.paint(const ui.Color(0xffa3a77c), stroke: .5),
          );
        }
      }
    }
    for (final i in layout.visibleCities(world.cities.length)) {
      final cell = layout.cell(i)!;
      final x = cell.left, y = cell.top;
      final city = world.city(i);
      if (city == null) continue;
      final faction = _faction(art, city.belong);
      final selected = i == session.renderer.selectedCity(world);
      if (selected) {
        SelectionArt.backdrop(art, cell);
        SelectionArt.outline(art, cell);
      }
      art.canvas.drawOval(
        ui.Rect.fromLTWH(x + 2, y + 7, 12, 3.5),
        art.paint(faction.withValues(alpha: city.belong == 0 ? .15 : .28)),
      );
      // 一座城池的图标与名称完整收进原版16×16逻辑格，邻城之间保留空隙。
      // 图标居中缩至10×9，名称底板缩至15点宽；原城池坐标与触摸热区不变。
      art.fortress(
        ui.Rect.fromLTWH(x + 3, y + 1, 10, 9),
        faction,
        capital: selected,
      );
      art.rounded(
        ui.Rect.fromLTWH(x + .5, y + 10.5, 15, 5),
        city.belong == 0 ? const ui.Color(0xffdddace) : faction,
        radius: 1.5,
      );
      art.text(
        session.resources.cityName(i),
        ui.Rect.fromLTWH(x + .5, y + 10.5, 15, 5.5),
        size: 4.5,
        align: ui.TextAlign.center,
        color: city.belong == 0 ? art.outline : const ui.Color(0xfffffaf0),
        bold: true,
      );
      if (session.mapRoadsVisible) {
        final count = city.belong == 0
            ? 0
            : world.personsInCity(i, belong: city.belong).length;
        final badge = ui.Rect.fromLTWH(x + 9.5, y + .2, 6, 4.5);
        art.rounded(
          badge,
          city.belong == 0 ? const ui.Color(0xffdddace) : faction,
          radius: 1.2,
        );
        art.text(
          city.belong == 0 ? '空' : '$count',
          badge,
          size: 3.8,
          bold: true,
          color: city.belong == 0 ? art.outline : const ui.Color(0xfffffaf0),
          align: ui.TextAlign.center,
        );
      }
    }
    art.canvas.restore();
  }

  /// 图例放在原右栏空白处，城池坐标、热区和宿主操作面板保持原版布局。
  void _strategyLegend(GameArt art, double width) {
    final left = ((((width + 1) ~/ 16) - 2) * 16 + 3).toDouble();
    const entries = [
      (CartoonSceneArt.red, '我方'),
      (CartoonSceneArt.blue, '敌方'),
      (ui.Color(0xff77817d), '空城'),
      (SelectionArt.gold, '选中'),
    ];
    for (var i = 0; i < entries.length; i++) {
      final y = 61 + i * 7.5;
      art.rounded(
        ui.Rect.fromLTWH(left, y + 1, 4.5, 4.5),
        entries[i].$1,
        radius: .6,
      );
      art.text(
        entries[i].$2,
        ui.Rect.fromLTWH(left + 6, y, 21, 7),
        size: 5.5,
        bold: true,
      );
    }
  }

  /// 根据真实势力编号着色；关闭增强着色时继续使用红、蓝、空城三类颜色。
  ui.Color _faction(GameArt art, int belong) {
    if (belong == 0) return art.outline;
    if (belong == (session.world?.playerRulerIndex ?? -1) + 1) {
      return CartoonSceneArt.red;
    }
    if (assets != null) return CartoonSceneArt.blue;
    if (!session.options.enabled('factionColors')) return CartoonSceneArt.blue;
    return HSLColor.fromAHSL(
      1,
      (belong * 137.508 + 90) % 360,
      .56,
      .43,
    ).toColor();
  }

  /// 选君主地图和战略缩略图使用实际城池坐标及归属，不只绘制一张空白地形图。
  void _miniMap(GameArt art, ui.Rect rect) {
    art.geography(rect);
    final world = session.world;
    if (world == null) return;
    final positions = session.resources.constant(6);
    final kings = session.rulers;
    final selected =
        session.scene == NativeScene.rulers &&
            session.selection >= 0 &&
            session.selection < kings.length
        ? kings[session.selection] + 1
        : null;
    for (var city = 0; city < world.cities.length; city++) {
      final belong = world.city(city)?.belong ?? 0;
      final at = ui.Offset(
        rect.left +
            (positions[city * 2] + .5) /
                session.resources.mapWidth *
                rect.width,
        rect.top +
            (positions[city * 2 + 1] + .5) /
                session.resources.mapHeight *
                rect.height,
      );
      art.canvas.drawCircle(
        at,
        belong == selected ? 1.8 : 1,
        art.paint(_faction(art, belong)),
      );
      if (belong == selected) {
        art.canvas.drawCircle(at, 2.5, art.paint(art.gold, stroke: .65));
      }
    }
  }

  /// 战场形势图按真实地形、阵营及存活状态显示；右半名单继续重放原版文字。
  void _situation(GameArt art, double w, double h) {
    final battle = session.activeBattle;
    if (battle == null || battle.width <= 0 || battle.height <= 0) return;
    final sx = (w ~/ 2 - battle.width) ~/ 2, sy = (h - battle.height) ~/ 2 + 20;
    for (var y = 0; y < battle.height; y++) {
      for (var x = 0; x < battle.width; x++) {
        final terrain = battle.terrain(x, y);
        art.canvas.drawRect(
          ui.Rect.fromLTWH(sx + x.toDouble(), sy + y.toDouble(), 1, 1),
          art.paint(
            terrain == 7
                ? art.water
                : terrain == 2
                ? art.forest
                : art.land,
          ),
        );
      }
    }
    for (var slot = 0; slot < battle.units.length; slot++) {
      final unit = battle.units[slot];
      if (unit.state == 8 || battle.people[slot] == null) continue;
      art.canvas.drawCircle(
        ui.Offset(sx + unit.x.toDouble() + .5, sy + unit.y.toDouble() + .5),
        1.1,
        art.paint(slot < 10 ? CartoonSceneArt.red : CartoonSceneArt.blue),
      );
    }
  }

  /// 游戏结局以当前实际报告为准，避免在占城过程中的普通通知提前显示胜利。
  void _ending(GameArt art, double w, double h) {
    if (session.scene != NativeScene.report) return;
    final text = commands
        .where((op) => op.kind == BayeDrawKind.glyph)
        .map((op) => op.text)
        .join();
    final wonText = session.resources.text(64, 90),
        lostText = session.resources.text(64, 89);
    final won = wonText.isNotEmpty && text.contains(wonText),
        lost = lostText.isNotEmpty && text.contains(lostText);
    if (!won && !lost) return;
    // 结局接管整张画布，覆盖原报告外露的文字，避免大面板两侧残留旧消息。
    art.geography(ui.Rect.fromLTWH(0, 0, w, h));
    final rect = ui.Rect.fromLTWH(16, 13, w - 32, h - 26);
    art.panel(rect);
    _sceneArt(art).battleNote(
      ui.Rect.fromLTWH(rect.center.dx - 38, 19, 76, 55),
      won ? 2 : 3,
    );
    art.text(
      won ? '天下一统' : '壮志未酬',
      ui.Rect.fromLTWH(22, 77, w - 44, 24),
      size: 20,
      bold: true,
      align: ui.TextAlign.center,
      color: won ? CartoonSceneArt.red : art.outline,
    );
    art.text(
      '确认后返回主菜单',
      ui.Rect.fromLTWH(22, 110, w - 44, 12),
      size: 9,
      align: ui.TextAlign.center,
    );
  }

  ui.Path _mask(bool Function(int, int) selected, int columns, int rows) {
    final edges = <(int, int), List<(int, int)>>{};
    bool value(int x, int y) =>
        x >= 0 && y >= 0 && x < columns && y < rows && selected(x, y);
    void add((int, int) a, (int, int) b) =>
        edges.putIfAbsent(a, () => []).add(b);
    for (var y = 0; y < rows; y++) {
      for (var x = 0; x < columns; x++) {
        if (!value(x, y)) continue;
        if (!value(x, y - 1)) add((x, y), (x + 1, y));
        if (!value(x + 1, y)) add((x + 1, y), (x + 1, y + 1));
        if (!value(x, y + 1)) add((x + 1, y + 1), (x, y + 1));
        if (!value(x - 1, y)) add((x, y + 1), (x, y));
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
        if (choices == null || choices.isEmpty) break;
        current = choices.removeAt(0);
        if (choices.isEmpty) {
          edges.remove(
            points.isEmpty
                ? first
                : (points.last.dx ~/ 16, points.last.dy ~/ 16),
          );
        }
        if (current == first) break;
      }
      if (points.length < 3) continue;
      for (var i = 0; i < points.length; i++) {
        final a = points[(i + points.length - 1) % points.length],
            b = points[i],
            d = points[(i + 1) % points.length];
        final radius = math.min(
          5.0,
          math.min((a - b).distance, (d - b).distance) * .45,
        );
        final start = b + (a - b) / (a - b).distance * radius,
            end = b + (d - b) / (d - b).distance * radius;
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

  void _battle(GameArt art, double w, double h) {
    final battle = session.activeBattle;
    if (battle == null) return;
    final columns = w ~/ 16, rows = h ~/ 16 - 1;
    art.canvas.drawRect(ui.Rect.fromLTWH(0, 0, w, h - 16), art.paint(art.land));
    final water = _mask(
      (x, y) => battle.terrain(battle.viewX + x, battle.viewY + y) == 7,
      columns,
      rows,
    );
    art.canvas.drawPath(
      water,
      art.paint(art.outline.withValues(alpha: .2), stroke: 1.6),
    );
    art.canvas.drawPath(water, art.paint(art.water));
    art.canvas.drawPath(
      water,
      art.paint(art.paper.withValues(alpha: .7), stroke: .35),
    );
    art.canvas.save();
    art.canvas.clipPath(water);
    for (var y = 5; y < h - 16; y += 10) {
      for (var x = 3; x < w; x += 19) {
        art.canvas.drawPath(
          ui.Path()
            ..moveTo(x.toDouble(), y.toDouble())
            ..quadraticBezierTo(x + 3, y - 1, x + 7, y.toDouble()),
          art.paint(art.paper.withValues(alpha: .4), stroke: .4),
        );
      }
    }
    art.canvas.restore();
    for (var y = 0; y < rows; y++) {
      for (var x = 0; x < columns; x++) {
        final terrain = battle.terrain(battle.viewX + x, battle.viewY + y);
        if (terrain == 2) art.mountain(x * 16 + 8, y * 16 + 10, .5, x + y);
        if (terrain == 3) {
          art.tree(x * 16 + 5, y * 16 + 7, .5);
          art.tree(x * 16 + 11, y * 16 + 10, .4);
        }
        if ([4, 5, 6].contains(terrain)) {
          art.fortress(
            ui.Rect.fromLTWH(x * 16 + 1, y * 16 + 1, 14, 13),
            art.gold,
            capital: terrain == 5,
          );
        }
      }
    }
    for (final index in [0, 1]) {
      final points = {
        for (final op in commands)
          if (op.kind == BayeDrawKind.picture &&
              op.resource == 7 &&
              op.index == index)
            (op.x ~/ 16, op.y ~/ 16),
      };
      if (points.isNotEmpty) {
        final mask = _mask((x, y) => points.contains((x, y)), columns, rows);
        art.canvas.drawPath(
          mask,
          art.paint(
            (index == 0
                    ? const ui.Color(0xff78bbd6)
                    : const ui.Color(0xffef9970))
                .withValues(alpha: .22),
          ),
        );
        art.canvas.drawPath(mask, art.paint(art.gold, stroke: .5));
      }
    }
  }

  void _picture(GameArt art, BayeDrawCommand op, ui.Rect rect) {
    final r = op.resource, index = op.index;
    if ([4, 54, 55].contains(r)) return;
    if (r == 5) {
      final normalized = index % 16;
      final type = normalized == 12 || normalized == 13
          ? 3
          : (normalized ~/ 2).clamp(0, 5);
      final battle = session.activeBattle;
      final slot = battle?.unitAt(
        op.x ~/ 16 + battle.viewX,
        op.y ~/ 16 + battle.viewY,
      );
      final inactive = slot == null ? false : battle!.units[slot].active != 0;
      final state = slot == null ? 0 : battle!.units[slot].state;
      art.soldier(
        rect.deflate(.3),
        type,
        index >= 16 ? CartoonSceneArt.blue : CartoonSceneArt.red,
        frame: index % 2,
        inactive: inactive,
        state: state,
        facingLeft: index >= 16,
        battlefield: true,
      );
      if (state != 2 && state != 3) _sceneArt(art).status(rect, state);
    } else if (r == 56) {
      if (assets != null) return;
      art.rounded(
        ui.Rect.fromLTWH(op.x - 3.2, op.y - 7.2, 14.4, 14.4),
        art.gold,
        radius: 2,
        stroke: .8,
      );
    } else if (r == 7) {
      if (r == 7 && index < 2) return;
      art.rounded(rect.deflate(.8), art.gold, radius: 2, stroke: 1);
    } else if (r >= 48 && r <= 53) {
      art.portrait(rect, seed: index, period: r - 47, person: index);
    } else if (r == 47 || r == 75) {
      _miniMap(art, rect);
    } else if (r == 46) {
      art.panel(rect);
      art.text(
        session.scene == NativeScene.saveSlots ? '保存进度' : '读取进度',
        ui.Rect.fromLTWH(72, 8, 120, 20),
        size: 15,
        bold: true,
      );
    } else if (r >= 28 && r <= 32 || r == 9) {
      _sceneArt(art).weather(rect, r == 9 ? index : r - 28, card: r != 9);
    } else if (r == 16) {
      final visual = session.backdropMovie;
      if (visual != null &&
          visual.sourceType != null &&
          visual.effect.isEmpty) {
        _sceneArt(art).arena(
          rect,
          source: visual.sourceType!,
          target: visual.targetType ?? 1,
          sourceFriendly: visual.sourceFriendly,
          targetFriendly: visual.targetFriendly,
        );
      } else if (visual != null &&
          visual.label.isNotEmpty &&
          visual.effect.isEmpty) {
        art.panel(rect);
        art.text(
          visual.label,
          rect.deflate(5),
          size: 11,
          bold: true,
          align: ui.TextAlign.center,
        );
      } else {
        _sceneArt(art).arena(rect);
      }
    } else if (r == 33) {
      art.rounded(rect, art.paper.withValues(alpha: .95));
      art.text('第        天', rect, size: 9, align: ui.TextAlign.center);
    } else if (r == 26) {
      art.panel(rect);
    } else if (r == 69) {
      if (index == 0) {
        final world = session.world, ruler = session.world?.playerRulerIndex;
        if (world != null && ruler != null) {
          art.portrait(rect, period: world.period, person: ruler);
        } else {
          art.text('将', rect, size: 7, bold: true, align: ui.TextAlign.center);
        }
      } else {
        art.fortress(rect, art.gold);
      }
    } else if (r == 8) {
      if (op.y >= session.canvas.height - 16) {
        _sceneArt(
          art,
        ).supplies(ui.Rect.fromLTWH(op.x.toDouble(), op.y + 2.0, 12, 12));
        art.text(
          '${session.activeBattle?.playerFood ?? 0}',
          ui.Rect.fromLTWH(op.x + 14.0, op.y + 3.0, 31, 12),
          size: 8.5,
          bold: true,
        );
      }
    } else if (r == 34) {
      _sceneArt(art).status(rect, index < 4 ? 2 : 3);
    } else if (r == 76) {
      final report = session.visualReport,
          ruler = session.world?.playerRulerIndex;
      _sceneArt(art).battleNote(
        rect,
        index,
        friendly: report?.actor == null || report?.actor == ruler,
        opponentFriendly: report?.kind.name == 'fight'
            ? report?.target == ruler
            : null,
      );
    } else if (r == 10 || r == 11 || r == 12 || r == 13 || r == 14 || r == 15) {
      art.text('$index', rect, size: 11, color: art.gold, bold: true);
    } else {
      art.panel(rect);
      art.canvas.drawCircle(
        rect.center,
        math.min(rect.width, rect.height) * .22,
        art.paint(art.gold.withValues(alpha: .4)),
      );
    }
  }

  @override
  bool shouldRepaint(ModernGamePainter oldDelegate) =>
      oldDelegate.revision != revision ||
      oldDelegate.ink != ink ||
      !identical(oldDelegate.session, session);
}

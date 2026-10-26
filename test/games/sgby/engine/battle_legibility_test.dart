import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:bbk_flutter/games/sgby/domain/models/game_battle.dart';
import 'package:bbk_flutter/games/sgby/domain/use_cases/battle_engine.dart';
import 'package:bbk_flutter/games/sgby/engine/core/native_game_session.dart';
import 'package:bbk_flutter/games/sgby/engine/rendering/battle_scene_renderer.dart';
import 'package:bbk_flutter/games/sgby/engine/rendering/baye_draw_command.dart';
import 'package:bbk_flutter/games/sgby/engine/rendering/cartoon_assets.dart';
import 'package:bbk_flutter/games/sgby/engine/rendering/cartoon_map_layout.dart';
import 'package:bbk_flutter/games/sgby/engine/rendering/realistic_game_painter.dart';
import 'package:bbk_flutter/games/sgby/engine/rendering/game_art.dart';

import '../support/game_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late CartoonAssets assets;
  setUpAll(() async {
    assets = await CartoonAssets.load();
    final font = File('/System/Library/Fonts/Hiragino Sans GB.ttc');
    if (font.existsSync()) {
      await (FontLoader('LegibilityReview')..addFont(
            Future.value(ByteData.sublistView(font.readAsBytesSync())),
          ))
          .load();
      GameArt.previewFontFamily = 'LegibilityReview';
    }
  });
  tearDownAll(() {
    assets.dispose();
    GameArt.previewFontFamily = null;
  });

  Future<ui.Image> render(NativeGameSession session, String name) async {
    final recorder = ui.PictureRecorder();
    RealisticGamePainter(
      session,
      assets,
      revision: session.frameVersion,
    ).paint(ui.Canvas(recorder), const ui.Size(960, 576));
    final picture = recorder.endRecording();
    final image = await picture.toImage(960, 576);
    picture.dispose();
    final output = Platform.environment['SGBY_ART_OUTPUT'];
    if (output != null) {
      final file = File('$output/$name.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(
        (await image.toByteData(
          format: ui.ImageByteFormat.png,
        ))!.buffer.asUint8List(),
      );
    }
    return image;
  }

  Future<Uint8List> crop(ui.Image image, ui.Rect rect) async {
    final bytes = (await image.toByteData())!.buffer.asUint8List();
    final result = BytesBuilder(copy: false);
    for (var y = (rect.top * 4).round(); y < (rect.bottom * 4).round(); y++) {
      result.add(
        bytes.sublist(
          (y * 960 + (rect.left * 4).round()) * 4,
          (y * 960 + (rect.right * 4).round()) * 4,
        ),
      );
    }
    return result.takeBytes();
  }

  int colored(Uint8List rgba, bool Function(int, int, int) matches) {
    var count = 0;
    for (var p = 0; p < rgba.length; p += 4) {
      if (matches(rgba[p], rgba[p + 1], rgba[p + 2])) count++;
    }
    return count;
  }

  test('战场敌军实体按原版敌我方向镜像，文字与兵力不参与镜像', () async {
    final db = loadGameDatabase(), world = db.loadPeriod(1, seed: 1);
    db.beginGame(world, 5);
    world.setPerson(
      0,
      world.person(0)!.copyWith(arms: 5000, armsType: 0, equip0: 0, equip1: 0),
    );
    final session = NativeGameSession(db)..replaceWorld(world);
    final battle =
        GameBattle(
            mode: 1,
            city: 8,
            sourceCity: 3,
            way: 0,
            mapId: 113,
            playerFood: 5000,
            enemyFood: 5000,
            people: [
              5,
              ...List<int?>.filled(9, null),
              0,
              ...List<int?>.filled(9, null),
            ],
          )
          ..width = 15
          ..height = 8
          ..map = Uint8List.fromList(List.filled(120, 1))
          ..focusX = 1
          ..focusY = 1;
    final renderer = BattleSceneRenderer(session.canvas, BattleEngine(db));
    battle.units[10]
      ..x = 6
      ..y = 2
      ..state = 8;
    session.activeBattle = battle;
    renderer.draw(world, battle);
    session.submitScene(NativeScene.battle);
    final ground = await render(session, 'facing_ground');
    battle.units[10].state = 0;
    renderer.draw(world, battle);
    final actual = await render(session, 'facing_enemy');
    final recorder = ui.PictureRecorder(), canvas = ui.Canvas(recorder);
    canvas.drawImage(ground, ui.Offset.zero, ui.Paint());
    canvas.scale(4);
    const rect = ui.Rect.fromLTWH(96, 31, 16, 17);
    canvas.translate(rect.center.dx * 2, 0);
    canvas.scale(-1, 1);
    assets.sprite(canvas, 'unit/enemy/0/idle', rect);
    final picture = recorder.endRecording(),
        expected = await picture.toImage(960, 576);
    try {
      expect(
        await crop(actual, const ui.Rect.fromLTWH(96, 31, 16, 11)),
        await crop(expected, const ui.Rect.fromLTWH(96, 31, 16, 11)),
        reason: '敌军应面向与我军相反的方向',
      );
    } finally {
      ground.dispose();
      actual.dispose();
      expected.dispose();
      picture.dispose();
      session.dispose();
    }
  });

  test('战略城名底板明确使用我红、敌青、空城中性色', () async {
    final db = loadGameDatabase(), world = db.loadPeriod(1, seed: 1);
    db.beginGame(world, 5);
    for (final entry in [(0, 6), (1, 1), (2, 0)]) {
      world.setCity(entry.$1, world.city(entry.$1)!.copyWith(belong: entry.$2));
    }
    final session = NativeGameSession(db)..replaceWorld(world);
    final image = await render(session, 'strategy_ownership');
    try {
      final layout = CartoonMapLayout(db);
      for (final entry in [(0, true), (1, false)]) {
        final cell = layout.cell(entry.$1)!;
        final pixels = await crop(
          image,
          ui.Rect.fromLTWH(cell.left + .5, cell.top + 10.5, 15, 5),
        );
        final count = colored(
          pixels,
          (r, g, b) => entry.$2
              ? r > g * 1.22 && r > b * 1.22
              : g > r * 1.17 && b > r * 1.17,
        );
        expect(
          count,
          greaterThan(200),
          reason: '${entry.$2 ? '我方' : '敌方'}不能仅靠小旗尖辨别',
        );
      }
    } finally {
      image.dispose();
      session.dispose();
    }
  });

  test('战略选中城池有高对比金色标记', () async {
    final db = loadGameDatabase(), world = db.loadPeriod(1, seed: 1);
    db.beginGame(world, 5);
    final cell = CartoonMapLayout(db).cell(0)!;
    world
      ..cursorX = cell.left ~/ 16
      ..cursorY = cell.top ~/ 16;
    final session = NativeGameSession(db)..replaceWorld(world);
    final image = await render(session, 'strategy_selected');
    try {
      final count = colored(
        await crop(image, cell),
        (r, g, b) => r > 225 && g > 165 && b < 140,
      );
      expect(count, greaterThan(250), reason: '选中城池需要稳定醒目的金色边框');
    } finally {
      image.dispose();
      session.dispose();
    }
  });

  test('选中城市的金框不覆盖城名文字', () async {
    final db = loadGameDatabase(), world = db.loadPeriod(1, seed: 1);
    db.beginGame(world, 5);
    final cell = CartoonMapLayout(db).cell(0)!;
    world
      ..cursorX = 0
      ..cursorY = 8;
    final session = NativeGameSession(db)..replaceWorld(world);
    final plain = await render(session, 'city_text_plain');
    world
      ..cursorX = cell.left ~/ 16
      ..cursorY = cell.top ~/ 16;
    session.showStrategy();
    final selected = await render(session, 'city_text_selected');
    try {
      final area = ui.Rect.fromLTWH(cell.left + 2, cell.top + 11, 12, 4.5);
      final a = await crop(plain, area), b = await crop(selected, area);
      var glyph = 0, covered = 0;
      for (var p = 0; p < a.length; p += 4) {
        if (a[p] > 225 && a[p + 1] > 220 && a[p + 2] > 190) {
          glyph++;
          if (!(b[p] > 225 && b[p + 1] > 220 && b[p + 2] > 190)) covered++;
        }
      }
      expect(glyph, greaterThan(20));
      expect(covered, 0, reason: '城名字形像素不能被金框覆盖');
    } finally {
      plain.dispose();
      selected.dispose();
      session.dispose();
    }
  });

  test('战场当前将领在移动范围中仍有醒目的选中标记', () async {
    final db = loadGameDatabase(), world = db.loadPeriod(1, seed: 1);
    db.beginGame(world, 5);
    final session = NativeGameSession(db)..replaceWorld(world);
    final battle =
        GameBattle(
            mode: 1,
            city: 8,
            sourceCity: 3,
            way: 0,
            mapId: 113,
            playerFood: 5000,
            enemyFood: 5000,
            people: [5, ...List<int?>.filled(19, null)],
          )
          ..width = 15
          ..height = 8
          ..map = Uint8List.fromList(List.filled(120, 1))
          ..focusX = 6
          ..focusY = 3;
    battle.units[0]
      ..x = 6
      ..y = 3
      ..state = 0
      ..move = 5;
    session.activeBattle = battle;
    final engine = BattleEngine(db);
    BattleSceneRenderer(
      session.canvas,
      engine,
    ).draw(world, battle, path: engine.path(world, battle, 0), selected: 0);
    session.submitScene(NativeScene.battle);
    final image = await render(session, 'battle_selected');
    try {
      final count = colored(
        await crop(image, const ui.Rect.fromLTWH(96, 48, 16, 16)),
        (r, g, b) => r > 225 && g > 165 && b < 140,
      );
      expect(count, greaterThan(250), reason: '选中将领不能被可移动范围的浅金底色淹没');
      BattleSceneRenderer(
        session.canvas,
        engine,
      ).draw(world, battle, path: engine.path(world, battle, 0));
      battle.focusX = 1;
      battle.focusY = 1;
      BattleSceneRenderer(
        session.canvas,
        engine,
      ).draw(world, battle, path: engine.path(world, battle, 0));
      final plain = await render(session, 'unit_text_plain');
      try {
        final a = await crop(plain, const ui.Rect.fromLTWH(96, 59, 16, 5));
        final b = await crop(image, const ui.Rect.fromLTWH(96, 59, 16, 5));
        var glyph = 0, covered = 0;
        for (var p = 0; p < a.length; p += 4) {
          if (a[p] > 225 && a[p + 1] > 220 && a[p + 2] > 190) {
            glyph++;
            if (!(b[p] > 225 && b[p + 1] > 220 && b[p + 2] > 190)) covered++;
          }
        }
        expect(glyph, greaterThan(20));
        expect(covered, 0, reason: '兵种与兵力字形像素不能被金框覆盖');
      } finally {
        plain.dispose();
      }
      battle.focusY = 3;
      battle.focusX = 9;
      BattleSceneRenderer(
        session.canvas,
        engine,
      ).draw(world, battle, path: engine.path(world, battle, 0), selected: 0);
      final moved = await render(session, 'battle_selected_cursor_moved');
      try {
        expect(
          colored(
            await crop(moved, const ui.Rect.fromLTWH(96, 48, 16, 16)),
            (r, g, b) => r > 225 && g > 165 && b < 140,
          ),
          greaterThan(250),
          reason: '目的地光标离开后操控部队仍保持金框',
        );
      } finally {
        moved.dispose();
      }
    } finally {
      image.dispose();
      session.dispose();
    }
  });

  test('城池在空置和驻军时都保留可辨认标记，绘制不改变守军状态', () async {
    final db = loadGameDatabase(), world = db.loadPeriod(1, seed: 1);
    db.beginGame(world, 5);
    final session = NativeGameSession(db)..replaceWorld(world);
    final map = Uint8List.fromList(List.filled(120, 1));
    map[3 * 15 + 8] = 3;
    final battle =
        GameBattle(
            mode: 1,
            city: 8,
            sourceCity: 3,
            way: 0,
            mapId: 113,
            playerFood: 5000,
            enemyFood: 5000,
            people: [
              5,
              ...List<int?>.filled(9, null),
              0,
              ...List<int?>.filled(9, null),
            ],
          )
          ..width = 15
          ..height = 8
          ..map = map
          ..cityX = 8
          ..cityY = 3
          ..focusX = 8
          ..focusY = 3;
    session.activeBattle = battle;
    battle.units[10]
      ..x = 8
      ..y = 3
      ..state = 8;
    final renderer = BattleSceneRenderer(session.canvas, BattleEngine(db));
    try {
      for (final state in [8, 0]) {
        battle.units[10].state = state;
        renderer.draw(world, battle);
        session.submitScene(NativeScene.battle);
        final image = await render(
          session,
          state == 8 ? 'battle_city_empty' : 'battle_city_guarded',
        );
        image.dispose();
        expect(battle.terrain(8, 3), 5);
        expect(battle.units[10].state, state);
      }
    } finally {
      session.dispose();
    }
  });

  test('右侧武将统计头像绑定当前主公，而非默认曹操', () async {
    final db = loadGameDatabase(), world = db.loadPeriod(1, seed: 1);
    db.beginGame(world, 5);
    final session = NativeGameSession(db)..replaceWorld(world);
    final op = session.canvas.commands.firstWhere(
      (op) =>
          op.kind == BayeDrawKind.picture && op.resource == 69 && op.index == 0,
    );
    final rect = ui.Rect.fromLTRB(
      op.x.toDouble(),
      op.y.toDouble(),
      op.right + 1.0,
      op.bottom + 1.0,
    );
    final actual = await render(session, 'strategy_lord_portrait');
    final recorder = ui.PictureRecorder(), canvas = ui.Canvas(recorder);
    canvas.drawColor(const ui.Color(0xffeee8d7), ui.BlendMode.src);
    canvas.scale(4);
    assets.portrait(
      canvas,
      rect,
      period: world.period,
      person: world.playerRulerIndex,
    );
    final picture = recorder.endRecording(),
        expected = await picture.toImage(960, 576);
    try {
      expect(
        await crop(actual, rect),
        await crop(expected, rect),
        reason: '主公马腾的统计图标不能显示曹操',
      );
    } finally {
      actual.dispose();
      expected.dispose();
      picture.dispose();
      session.dispose();
    }
  });
}

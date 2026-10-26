import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:bbk_flutter/games/sgby/domain/models/game_report.dart';
import 'package:bbk_flutter/games/sgby/engine/core/native_game_session.dart';
import 'package:bbk_flutter/games/sgby/engine/rendering/baye_draw_command.dart';
import 'package:bbk_flutter/games/sgby/engine/rendering/modern_game_painter.dart';

import '../support/game_database.dart';

/// 绘制阶段只读世界；原动画继续拥有时序及回调，不能因换肤多执行一次指令。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<List<int>> render(NativeGameSession session) async {
    final recorder = ui.PictureRecorder();
    ModernGamePainter(
      session,
    ).paint(ui.Canvas(recorder), const ui.Size(480, 288));
    final picture = recorder.endRecording();
    final image = await picture.toImage(480, 288);
    try {
      return (await image.toByteData())!.buffer.asUint8List().toList();
    } finally {
      image.dispose();
      picture.dispose();
    }
  }

  test('道路开关、四类战争通知和游戏结局有独立表现，绘制不改变世界', () async {
    final db = loadGameDatabase(),
        session = NativeGameSession(loadGameDatabase());
    try {
      final world = db.loadPeriod(1, seed: 1);
      db.beginGame(world, 5);
      session.replaceWorld(world);
      final before = jsonEncode(world.toJson()), random = world.random.state;
      final roads = await render(session);
      session.mapRoadsVisible = false;
      final noRoads = await render(session);
      expect(noRoads, isNot(roads));
      final notes = <List<int>>[];
      for (final kind in [
        GameReportKind.attack,
        GameReportKind.fight,
        GameReportKind.victory,
        GameReportKind.defeat,
      ]) {
        session.showStrategy();
        session.renderer.battleNote(world, kind, 5, 8);
        notes.add(await render(session));
      }
      for (var i = 0; i < notes.length; i++) {
        for (var j = i + 1; j < notes.length; j++) {
          expect(notes[i], isNot(notes[j]));
        }
      }
      session.showReport(db.text(64, 90));
      final won = await render(session);
      session.showStrategy();
      session.showReport(db.text(64, 89));
      expect(await render(session), isNot(won));
      expect(world.random.state, random);
      expect(jsonEncode(world.toJson()), before);
    } finally {
      session.dispose();
    }
  });

  test('动画表现快照沿用原帧，动画清除标记不改变像素与回调次数', () {
    final db = loadGameDatabase(),
        session = NativeGameSession(loadGameDatabase());
    try {
      final world = db.loadPeriod(1, seed: 1);
      db.beginGame(world, 5);
      session.replaceWorld(world);
      final before = jsonEncode(world.toJson());
      var completed = 0;
      session.playMovie(
        19,
        first: 0,
        last: 10,
        x: 54,
        y: 40,
        visualLabel: '骑兵攻击',
        sourceType: 0,
        targetType: 1,
        completed: () => completed++,
      );
      final first = session.movieVisual;
      expect(first?.resource, 19);
      expect(first?.sourceType, 0);
      expect(first?.targetType, 1);
      expect(first?.label, '骑兵攻击');
      expect(
        session.canvas.commands.any(
          (op) => op.kind == BayeDrawKind.bitmap && op.resource == 19,
        ),
        isTrue,
      );
      var advanced = false;
      for (var frame = 0; frame < 500 && completed == 0; frame++) {
        session.advance(const Duration(milliseconds: 20));
        final visual = session.movieVisual;
        if (visual != null && visual.frame > first!.frame) advanced = true;
      }
      expect(advanced, isTrue);
      expect(completed, 1);
      expect(session.movieVisual, isNull);
      session.advance(const Duration(milliseconds: 200));
      expect(completed, 1);
      expect(jsonEncode(world.toJson()), before);
    } finally {
      session.dispose();
    }
    expect(session.movieVisual, isNull);
  });
}

import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:bbk_flutter/games/sgby/domain/models/game_report.dart';
import 'package:bbk_flutter/games/sgby/engine/core/native_game_session.dart';
import 'package:bbk_flutter/games/sgby/engine/rendering/cartoon_assets.dart';
import 'package:bbk_flutter/games/sgby/engine/rendering/realistic_game_painter.dart';

import '../support/game_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late CartoonAssets assets;
  setUpAll(() async => assets = await CartoonAssets.load());
  tearDownAll(() => assets.dispose());
  for (final kind in [
    GameReportKind.attack,
    GameReportKind.fight,
    GameReportKind.victory,
    GameReportKind.defeat,
  ]) {
    for (final speed in [1, 8]) {
      test('新战报${kind.name} ${speed}x沿原时序自动关闭，不需要确认', () async {
        final db = loadGameDatabase(), world = db.loadPeriod(1, seed: 1);
        db.beginGame(world, 5);
        final session = NativeGameSession(db)..replaceWorld(world);
        var completed = 0;
        session.displayReports([
          GameReport(
            '',
            kind: kind,
            actor: 5,
            target: kind == GameReportKind.fight ? 0 : 8,
            city: 8,
          ),
        ], completed: () => completed++);
        try {
          final before = jsonEncode(world.toJson()),
              random = world.random.state;
          final recorder = ui.PictureRecorder();
          RealisticGamePainter(
            session,
            assets,
            revision: session.frameVersion,
          ).paint(ui.Canvas(recorder), const ui.Size(960, 576));
          final picture = recorder.endRecording(),
              image = await picture.toImage(960, 576);
          image.dispose();
          picture.dispose();
          expect(jsonEncode(world.toJson()), before);
          expect(world.random.state, random);
          expect(session.visualReport?.city, 8);
          final delay = kind == GameReportKind.attack ? 1000000 : 3000000;
          var remaining = delay ~/ speed;
          while (remaining > 1) {
            final step = math.min(200000, remaining - 1);
            session.advance(Duration(microseconds: step), speed: speed);
            remaining -= step;
          }
          expect(session.scene, NativeScene.report);
          expect(completed, 0);
          session.advance(const Duration(microseconds: 1), speed: speed);
          expect(session.scene, NativeScene.strategy);
          expect(completed, 1);
          session.advance(const Duration(milliseconds: 200), speed: speed);
          expect(completed, 1);
        } finally {
          session.dispose();
        }
      });
    }
  }
}

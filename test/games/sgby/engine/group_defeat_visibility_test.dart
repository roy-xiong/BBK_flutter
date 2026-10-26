import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:bbk_flutter/games/sgby/domain/models/game_battle.dart';
import 'package:bbk_flutter/games/sgby/domain/models/game_options.dart';
import 'package:bbk_flutter/games/sgby/engine/core/battle_flow.dart';
import 'package:bbk_flutter/games/sgby/engine/core/native_game_session.dart';
import 'package:bbk_flutter/games/sgby/engine/rendering/baye_draw_command.dart';
import 'package:bbk_flutter/games/sgby/engine/rendering/cartoon_assets.dart';
import 'package:bbk_flutter/games/sgby/engine/rendering/realistic_game_painter.dart';

import '../support/game_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late CartoonAssets assets;
  setUpAll(() async => assets = await CartoonAssets.load());
  tearDownAll(() => assets.dispose());

  for (final speed in [1, 8]) {
    test('真实群攻${speed}x：后续敌军在轮到死亡动画前一直可见', () async {
      final db = loadGameDatabase(), world = db.loadPeriod(1, seed: 1);
      db.beginGame(world, 5);
      for (final id in [5, 0, 1, 2]) {
        world.setPerson(id, world.person(id)!.copyWith(arms: 5000));
      }
      final battle = GameBattle(
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
          1,
          2,
          ...List<int?>.filled(7, null),
        ],
      );
      final session = NativeGameSession(
        db,
        options: GameOptions({
          'wideGroupAttack': true,
          'oneHitKill': true,
          'freeMovement': true,
        }),
      )..replaceWorld(world);
      final flow = BattleFlow(session, battle, completed: () {})..start();
      try {
        for (var i = 0; i < 40; i++) {
          if (session.scene == NativeScene.report) session.closeReport();
          session.advance(const Duration(milliseconds: 100));
        }
        world.lookBattleMovie = true;
        battle
          ..width = 15
          ..height = 8
          ..viewX = 0
          ..viewY = 0
          ..cityX = 13
          ..cityY = 6
          ..result = 0
          ..map = Uint8List.fromList(List.filled(120, 1));
        for (final entry in [(0, 6, 3), (10, 7, 3), (11, 4, 1), (12, 8, 6)]) {
          battle.units[entry.$1]
            ..x = entry.$2
            ..y = entry.$3
            ..state = 0
            ..hp = 90
            ..move = 1
            ..active = 0;
        }
        battle
          ..focusX = 6
          ..focusY = 3;
        flow.draw();
        flow.input(NativeInput.confirm);
        if (session.scene == NativeScene.battle) {
          flow.input(NativeInput.confirm);
        }
        expect(session.scene, NativeScene.menu);
        session.input(NativeInput.confirm);
        flow.tap(7 * 16 + 8, 3 * 16 + 8);
        expect(session.scene, NativeScene.processing, reason: '真实攻击必须已经提交');
        expect(
          world.person(battle.people[10]!)!.arms,
          0,
          reason: '群攻目标必须已扣至零兵力',
        );
        final seen = <int>{};
        for (var i = 0; i < 30000; i++) {
          if (session.scene == NativeScene.report) session.closeReport();
          final movie = session.movieVisual;
          if (movie?.effect == 'defeat') {
            final currentSlot = [10, 11, 12].firstWhere(
              (slot) =>
                  battle.units[slot].x * 16 == movie!.x &&
                  battle.units[slot].y * 16 == movie.y,
            );
            if (!seen.add(currentSlot)) {
              session.advance(const Duration(milliseconds: 1), speed: speed);
              continue;
            }
            expect(world.person(battle.people[11]!)!.arms, 0);
            expect(world.person(battle.people[12]!)!.arms, 0);
            final recorder = ui.PictureRecorder();
            RealisticGamePainter(
              session,
              assets,
              revision: session.frameVersion,
            ).paint(ui.Canvas(recorder), const ui.Size(960, 576));
            final picture = recorder.endRecording();
            final image = await picture.toImage(960, 576);
            try {
              final bytes = (await image.toByteData())!.buffer.asUint8List();
              final output = Platform.environment['SGBY_ART_OUTPUT'];
              if (output != null) {
                final file = File(
                  '$output/group_defeat_${speed}x_$currentSlot.png',
                );
                file.parent.createSync(recursive: true);
                file.writeAsBytesSync(
                  (await image.toByteData(
                    format: ui.ImageByteFormat.png,
                  ))!.buffer.asUint8List(),
                );
              }
              for (final slot in [
                10,
                11,
                12,
              ].where((slot) => !seen.contains(slot) || slot == currentSlot)) {
                final unit = battle.units[slot];
                expect(
                  session.canvas.commands.any(
                    (op) =>
                        op.kind == BayeDrawKind.picture &&
                        op.resource == 5 &&
                        op.x == unit.x * 16 &&
                        op.y == unit.y * 16,
                  ),
                  isTrue,
                  reason: '原版画布仍显示待退场敌军',
                );
                var cyan = 0;
                for (var y = unit.y * 64; y < unit.y * 64 + 40; y++) {
                  for (var x = unit.x * 64; x < unit.x * 64 + 64; x++) {
                    final p = (y * 960 + x) * 4;
                    if (bytes[p + 1] > bytes[p] * 1.17 &&
                        bytes[p + 2] > bytes[p] * 1.17) {
                      cyan++;
                    }
                  }
                }
                expect(cyan, greaterThan(40), reason: '槽位$slot在轮到死亡动画前不能先变成空地');
              }
            } finally {
              image.dispose();
              picture.dispose();
            }
            if (seen.length == 3) break;
          }
          session.advance(const Duration(milliseconds: 1), speed: speed);
        }
        expect(seen, {10, 11, 12}, reason: '必须通过真实输入完整检查三位目标的死亡阶段');
      } finally {
        session.dispose();
      }
    });
  }
}

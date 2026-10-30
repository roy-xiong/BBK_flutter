import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bbk_flutter/games/fmj/engine/game_actor.dart';
import 'package:bbk_flutter/games/fmj/engine/game_engine.dart';
import 'package:bbk_flutter/games/fmj/ui/modern_art.dart';
import 'package:bbk_flutter/games/fmj/ui/modern_battle_pose.dart';
import 'package:bbk_flutter/games/fmj/ui/modern_scene.dart';
import 'package:bbk_flutter/games/fmj/ui/system_font_layout.dart';
import 'game_engine_test.dart' show loadData;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('三主角虚弱真实低头屈膝、防御举剑；正式姿态入口只读', (tester) async {
    await tester.runAsync(() async {
      final data = await loadData(), art = await ModernArt.load();
      final random = _ObservedRandom();
      final game = GameEngine(
        data,
        textLayout: FlutterSystemFontLayout(),
        random: random,
      )..intro = null;
      final sheetRecorder = ui.PictureRecorder(), sheet = Canvas(sheetRecorder);
      sheet.drawColor(const Color(0xff203238), BlendMode.src);
      const target = Rect.fromLTWH(60, 18, 192, 192);
      Future<Uint8List> pixels(
        GameActor actor, {
        bool guard = false,
        bool addToSheet = true,
      }) async {
        final recorder = ui.PictureRecorder(), canvas = Canvas(recorder);
        if (!ModernBattlePose.draw(
          canvas,
          art,
          actor,
          target,
          defending: guard,
          ticks: game.ticks,
          filterQuality: FilterQuality.medium,
        )) {
          art.drawSprite(
            canvas,
            'battle:hero:${actor.index}/${actor.combatFrame - 1}',
            target,
            Paint()..filterQuality = FilterQuality.medium,
          );
        }
        final picture = recorder.endRecording();
        final image = await picture.toImage(320, 224);
        try {
          if (addToSheet) {
            sheet.save();
            sheet.translate(
              (guard
                      ? 2
                      : actor.hp == 1
                      ? 1
                      : 0) *
                  320.0,
              (actor.index - 1) * 224.0,
            );
            sheet.drawImage(image, Offset.zero, Paint());
            sheet.restore();
          }
          return (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!.buffer.asUint8List();
        } finally {
          image.dispose();
          picture.dispose();
        }
      }

      try {
        for (var id = 1; id <= 3; id++) {
          game.ticks = 0;
          final actor = GameActor.load(data, 1, id)!
            ..maxHp = 999
            ..hp = 800;
          game.players.add(actor);
          final idle = await pixels(actor);
          actor.hp = 1;
          actor.combatFrame = 11;
          final before = [
            actor.hp,
            actor.mp,
            actor.status,
            actor.combatX,
            actor.combatY,
            actor.combatFrame,
            game.ticks,
          ];
          final calls = random.calls;
          final weak = await pixels(actor);
          expect(
            _differentPixels(idle, weak),
            greaterThan(1800),
            reason: '$id 低血不能继续复用完整站立轮廓',
          );
          expect(
            _inkTop(weak),
            greaterThan(_inkTop(idle) + 8),
            reason: '$id 必须低头并降低身体重心',
          );
          expect([
            actor.hp,
            actor.mp,
            actor.status,
            actor.combatX,
            actor.combatY,
            actor.combatFrame,
            game.ticks,
          ], before);
          expect(random.calls, calls, reason: '绘图不能消耗战斗随机数');
          game.ticks = 12;
          final breathing = await pixels(actor, addToSheet: false);
          expect(
            _differentPixels(weak, breathing),
            greaterThan(80),
            reason: '$id 虚弱呼吸必须可见且只读取原时钟',
          );
          actor.hp = 800;
          actor.combatFrame = 1;
          final guard = await pixels(actor, guard: true);
          expect(
            _differentPixels(idle, guard),
            greaterThan(1800),
            reason: '$id 防御必须举臂持剑，不能只改变颜色',
          );
        }

        final battle = GameBattle(
          game,
          monsters: [44],
          background: [2, 2, 2],
          randomFight: true,
        );
        game.battle = battle;
        for (var column = 0; column < 3; column++) {
          for (final actor in game.players) {
            actor.hp = column == 1 ? 1 : 800;
            actor.combatFrame = column == 1 ? 11 : 1;
          }
          battle.defending.clear();
          if (column == 2) battle.defending.addAll(game.players);
          final before = game.players
              .map((a) => (a.hp, a.combatFrame, a.combatX, a.combatY))
              .toList();
          final calls = random.calls;
          sheet.save();
          sheet.translate(column * 320.0, 700);
          sheet.scale(.5);
          ModernScenePainter(game, art).paint(sheet, const Size(640, 384));
          sheet.restore();
          expect(
            game.players
                .map((a) => (a.hp, a.combatFrame, a.combatX, a.combatY))
                .toList(),
            before,
          );
          expect(random.calls, calls);
        }
        for (var column = 0; column < 3; column++) {
          final label = TextPainter(
            text: TextSpan(
              text: const [
                'Idle',
                'Weak: head / knees',
                'Defend: raised sword',
              ][column],
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          label.paint(sheet, Offset(column * 320.0 + 16, 675));
          label.dispose();
        }
        final picture = sheetRecorder.endRecording();
        try {
          if (Platform.environment['FMJ_EXPORT_APPROVED_ART'] == '1') {
            final image = await picture.toImage(960, 900);
            try {
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final folder = Directory('build/validation/current-feedback-v32')
                ..createSync(recursive: true);
              File(
                '${folder.path}/reviewed-poses.png',
              ).writeAsBytesSync(bytes!.buffer.asUint8List());
            } finally {
              image.dispose();
            }
          }
        } finally {
          picture.dispose();
        }
      } finally {
        if (sheetRecorder.isRecording) sheetRecorder.endRecording().dispose();
        art.dispose();
      }
    });
  });

  testWidgets('普通、出手、受击、死亡与原异常状态不被新姿态覆盖', (tester) async {
    await tester.runAsync(() async {
      final data = await loadData(), art = await ModernArt.load();
      try {
        for (var id = 1; id <= 3; id++) {
          final actor = GameActor.load(data, 1, id)!
            ..maxHp = 999
            ..hp = 1;
          for (var frame = 1; frame <= 12; frame++) {
            actor.combatFrame = frame;
            for (final guard in [false, true]) {
              if (frame == 11 || guard && frame == 1) continue;
              final recorder = ui.PictureRecorder();
              expect(
                ModernBattlePose.draw(
                  Canvas(recorder),
                  art,
                  actor,
                  const Rect.fromLTWH(0, 0, 144, 144),
                  defending: guard,
                  ticks: 0,
                  filterQuality: FilterQuality.medium,
                ),
                false,
                reason: '$id / $frame 必须保留原帧',
              );
              final picture = recorder.endRecording();
              final image = await picture.toImage(144, 144);
              final rgba = await image.toByteData(
                format: ui.ImageByteFormat.rawRgba,
              );
              expect(
                rgba!.buffer.asUint8List().every((v) => v == 0),
                true,
                reason: '回退原分支前不能向Canvas画入任何像素',
              );
              image.dispose();
              picture.dispose();
            }
          }
          for (final status in [1, 2, 4, 8]) {
            actor.status = status;
            actor.combatFrame = 11;
            final recorder = ui.PictureRecorder();
            expect(
              ModernBattlePose.draw(
                Canvas(recorder),
                art,
                actor,
                const Rect.fromLTWH(0, 0, 144, 144),
                defending: true,
                ticks: 0,
                filterQuality: FilterQuality.medium,
              ),
              false,
            );
            recorder.endRecording().dispose();
          }
        }
      } finally {
        art.dispose();
      }
    });
  });

  test('真实防御仍在原两次update结束，表现标记保留到既有回合清空点', () async {
    final data = await loadData();
    for (var id = 1; id <= 3; id++) {
      final game = GameEngine(data, textLayout: FlutterSystemFontLayout())
        ..intro = null;
      final actor = GameActor.load(data, 1, id)!;
      actor.equipment.fillRange(0, actor.equipment.length, null);
      game.players.add(actor);
      final battle = GameBattle(
        game,
        monsters: [44],
        background: [2, 2, 2],
        randomFight: true,
      );
      game.battle = battle;
      final hp = actor.hp;
      final action = BattleAction(actor, [actor], 'defend');
      battle.phase = 'perform';
      battle.queue.add(action);
      battle.update();
      expect(battle.current, same(action));
      expect(battle.defending, contains(actor));
      battle.update();
      expect(battle.current, isNull);
      expect(action.tick, 1);
      expect(action.frame, 0);
      expect(actor.hp, hp, reason: '防御标记不能修改伤害或生命值');
      expect(battle.defending, contains(actor), reason: '末帧600ms仍显示防御姿态');
      battle.update();
      expect(battle.phase, 'select');
      expect(battle.defending, isEmpty);
    }
  });
}

int _differentPixels(Uint8List a, Uint8List b) {
  var count = 0;
  for (var i = 0; i < a.length; i += 4) {
    if (a[i] != b[i] ||
        a[i + 1] != b[i + 1] ||
        a[i + 2] != b[i + 2] ||
        a[i + 3] != b[i + 3]) {
      count++;
    }
  }
  return count;
}

int _inkTop(Uint8List rgba) {
  for (var i = 3; i < rgba.length; i += 4) {
    if (rgba[i] > 128) return i ~/ 4 ~/ 320;
  }
  return 224;
}

/// 观察真正的Random调用，不能在姿态入口消耗随机数改变原战斗结果。
final class _ObservedRandom implements math.Random {
  final math.Random _delegate = math.Random(32);
  int calls = 0;
  @override
  bool nextBool() {
    calls++;
    return _delegate.nextBool();
  }

  @override
  double nextDouble() {
    calls++;
    return _delegate.nextDouble();
  }

  @override
  int nextInt(int max) {
    calls++;
    return _delegate.nextInt(max);
  }
}

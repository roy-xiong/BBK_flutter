import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bbk_flutter/games/fmj/data/game_data.dart';
import 'package:bbk_flutter/games/fmj/engine/game_actor.dart';
import 'package:bbk_flutter/games/fmj/engine/game_engine.dart';
import 'package:bbk_flutter/games/fmj/ui/modern_art.dart';
import 'package:bbk_flutter/games/fmj/ui/modern_world_objects.dart';
import 'package:bbk_flutter/games/fmj/ui/system_font_layout.dart';
import 'game_engine_test.dart' show loadData;

/// 从真实剧情指令、原始机关及生产 Painter 验证倍速和熄灯，避免仅测计时工具。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GameData data;
  setUpAll(() async => data = await loadData());

  GameEngine engine(int speed) =>
      GameEngine(
          data,
          textLayout: FlutterSystemFontLayout(),
          random: math.Random(24),
        )
        ..screen = 'play'
        ..intro = null
        ..setPreference('runSpeed', speed);

  test('四倍速下场景提示、获得物品提示和剧情等待均缩短为四分之一', () {
    for (final kind in ['timed', 'delay']) {
      final normal = engine(1)
        ..operation = GameOperation(kind, text: '百草园', args: [1000]);
      final fast = engine(4)
        ..operation = GameOperation(kind, text: '百草园', args: [1000]);
      for (var i = 0; i < 6; i++) {
        normal.update();
        fast.update();
      }
      expect(normal.operation?.elapsed, 240);
      expect(fast.operation?.elapsed, 960, reason: '$kind 未跟随倍速');
      fast.update();
      expect(fast.operation, isNull);
      expect(normal.operation, isNotNull);
    }
  });

  test('提示中切换倍速立即生效，已经消耗的时间不重置', () {
    final game = engine(1)..operation = GameOperation('timed', args: [1000]);
    for (var i = 0; i < 5; i++) {
      game.update();
    }
    game.setPreference('runSpeed', 4);
    for (var i = 0; i < 4; i++) {
      game.update();
    }
    expect(game.operation?.elapsed, 840);
    game.update();
    expect(game.operation, isNull);
  });

  test('场景名专用提示缩短至700毫秒，普通物品提示保持原时长', () {
    final game = engine(1)
      ..sceneName = '百草园'
      ..cursor = ScriptCursor(
        GameScript({
          'id': '99:1',
          'name': '场景名回归',
          'events': <int>[],
          'commands': [
            {'at': 0, 'op': 55, 'a': <int>[]},
            {'at': 1, 'op': 9, 'a': <int>[]},
          ],
        }),
      );
    game.update();
    expect(game.operation?.text, '百草园');
    expect(game.operation?.args, [700]);
  });

  test('经验、金钱、升级及学会法术卡片按倍速展示，奖励只结算一次', () {
    (int, List<String>, int, int) run(int speed) {
      final game = engine(speed);
      final hero = GameActor.load(data, 1, 1)!..exp = 999;
      game.players.add(hero);
      final battle = GameBattle(
        game,
        monsters: [1],
        background: [2, 2, 2],
        randomFight: true,
      );
      game.battle = battle;
      battle.forceWin();
      final money = game.money;
      final seen = <String>[];
      var count = 0;
      while (game.battle != null && count < 600) {
        for (final card in battle.victoryShown) {
          final value = '${card.kind}:${card.text}:${card.detail}';
          if (!seen.contains(value)) seen.add(value);
        }
        game.update();
        count++;
        expect(game.money, money, reason: '展示提示不应重复发奖');
      }
      expect(game.error, isEmpty);
      expect(game.battle, isNull);
      expect(seen.any((v) => v.startsWith('level:')), isTrue);
      return (count, seen, hero.level, hero.exp);
    }

    final normal = run(1);
    for (var speed = 2; speed <= 4; speed++) {
      final fast = run(speed);
      expect(fast.$1, lessThanOrEqualTo((normal.$1 / speed).ceil() + 1));
      expect(fast.$2, normal.$2, reason: '倍速不能跳过升级或学会法术提示');
      expect((fast.$3, fast.$4), (normal.$3, normal.$4));
    }
  });

  testWidgets('八个灯洞通关后及读档后灯火熄灭，灯座仍保留', (tester) async {
    await tester.runAsync(() async {
      final art = await ModernArt.load();
      try {
        Future<List<int>> pixels(GameEngine game) async {
          final actor = game.npcs.values.firstWhere(
            (a) => a.type == 4 && a.sprite == 7,
          );
          final recorder = ui.PictureRecorder();
          final canvas = Canvas(recorder);
          expect(
            ModernWorldObjects.draw(
              canvas,
              game,
              actor,
              art,
              const Offset(16, 16),
              96,
              null,
            ),
            isTrue,
          );
          final picture = recorder.endRecording();
          final image = await picture.toImage(128, 128);
          try {
            final bytes = await image.toByteData();
            return bytes!.buffer.asUint8List().toList();
          } finally {
            image.dispose();
            picture.dispose();
          }
        }

        GameEngine enter(int number, bool completed) {
          final game = engine(1)..players.add(GameActor.load(data, 1, 1)!);
          final script = data.scripts['2:${18 + number}']!;
          game.map =
              data.maps[script.commands
                  .where((c) => c.opcode == 1)
                  .firstOrNull
                  ?.args
                  .take(2)
                  .join(':')] ??
              data.maps['3:2'];
          if (completed) game.flags.add(10 + number);
          game.cursor = ScriptCursor(script);
          for (var i = 0; i < 150; i++) {
            game.update();
            if (game.cursor?.running == false && game.operation == null) break;
          }
          expect(game.error, isEmpty);
          return game;
        }

        for (var number = 1; number <= 8; number++) {
          final on = enter(number, false);
          final off = enter(number, true);
          expect(off.npcs.values.firstWhere((a) => a.sprite == 7).step, 0);
          final onPixels = await pixels(on);
          final offPixels = await pixels(off);
          expect(
            offPixels,
            isNot(onPixels),
            reason: '灯洞$number 原剧情已熄灯，彩色层仍在画火',
          );
          expect(offPixels.where((v) => v != 0).length, greaterThan(200));
          final restored = engine(1)
            ..restore(
              jsonDecode(jsonEncode(off.snapshot())) as Map<String, dynamic>,
            );
          expect(
            await pixels(restored),
            offPixels,
            reason: '读档后灯洞$number 不得重新亮灯',
          );
        }
      } finally {
        art.dispose();
      }
    });
  });
}

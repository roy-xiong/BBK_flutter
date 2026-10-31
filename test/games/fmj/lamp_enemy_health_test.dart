import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bbk_flutter/games/fmj/data/game_data.dart';
import 'package:bbk_flutter/games/fmj/engine/game_engine.dart';
import 'package:bbk_flutter/games/fmj/engine/game_actor.dart';
import 'package:bbk_flutter/games/fmj/ui/modern_art.dart';
import 'package:bbk_flutter/games/fmj/ui/modern_world_objects.dart';
import 'package:bbk_flutter/games/fmj/ui/modern_enemy_health.dart';
import 'package:bbk_flutter/games/fmj/ui/system_font_layout.dart';
import 'game_engine_test.dart' show loadData;

/// 按已认可的15项提案验证原事件格与真实战斗对象，不为测试伪造怪物身份。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GameData data;
  setUpAll(() async => data = await loadData());
  GameEngine game() =>
      GameEngine(
          data,
          textLayout: FlutterSystemFontLayout(),
          random: math.Random(24),
        )
        ..screen = 'play'
        ..intro = null
        ..players.add(GameActor.load(data, 1, 1)!);

  test('八个入口按原37号事件格恢复，同一套圆角道路继续保留', () {
    final map = data.maps['3:1']!;
    final markers = ModernWorldObjects.lampEntrances(map);
    expect(markers.map((m) => (m.x, m.y)).toSet(), {
      (11, 14),
      (22, 14),
      (23, 13),
      (23, 9),
      (22, 8),
      (11, 8),
      (10, 9),
      (10, 13),
    });
    for (final marker in markers) {
      expect(marker.key, 'review-v14:cave-stairs');
      expect(marker.visualWidth, 1.32);
      expect(map.cell(marker.x, marker.y) & 127, 37);
      expect(map.event(marker.x, marker.y), inInclusiveRange(2, 9));
    }
    for (final map in data.maps.values.where((m) => m.id != '3:1')) {
      expect(ModernWorldObjects.lampEntrances(map), isEmpty);
    }
  });

  test('灯洞返程后的左右八个洞口按原63号图块显示，与中央入口分开', () {
    final map = data.maps['3:1']!;
    final exits = ModernWorldObjects.lampReturnExits(map);
    expect(exits.map((e) => (e.x, e.y)).toSet(), {
      for (final x in [7, 26])
        for (var y = 21; y <= 24; y++) (x, y),
    });
    for (final marker in exits) {
      expect(marker.key, 'building:cave-mouth');
      expect(marker.width, 1);
      expect(marker.height, 1);
      expect(map.cell(marker.x, marker.y) & 127, 63);
    }
    for (final other in data.maps.values.where((m) => m.id != '3:1')) {
      expect(ModernWorldObjects.lampReturnExits(other), isEmpty);
    }
  });

  test('灯洞1击败护灯兽后走返回出口，原脚本落点就是伏魔洞63号洞口', () {
    final g = game()
      ..map = data.maps['3:2']
      ..cursor = ScriptCursor(data.scripts['2:19']!);
    g.flags.add(11);
    g.player!
      ..x = 5
      ..y = 3;
    for (var i = 0; i < 200; i++) {
      g.update();
      if (g.cursor?.running == false && g.operation == null) break;
    }
    g.move(4);
    for (var i = 0; i < 200; i++) {
      g.update();
      if (g.cursor?.script.id == '2:18' &&
          g.cursor?.running == false &&
          g.operation == null) {
        break;
      }
    }
    expect(g.error, isEmpty);
    expect(g.map?.id, '3:1');
    expect((g.player!.x, g.player!.y), (26, 21));
    expect(g.map!.cell(26, 21) & 127, 63);
    expect(
      ModernWorldObjects.lampReturnExits(
        g.map!,
      ).any((exit) => exit.x == g.player!.x && exit.y == g.player!.y),
      true,
    );
  });

  testWidgets('八段灯洞剧情的真实出口都用同一高清楼梯，挡路石不变成出口', (tester) async {
    await tester.runAsync(() async {
      final art = await ModernArt.load();
      try {
        for (var n = 1; n <= 8; n++) {
          final g = game()
            ..map = data.maps['3:${2 + (n - 1) % 4}']
            ..cursor = ScriptCursor(data.scripts['2:${18 + n}']!);
          for (var i = 0; i < 200; i++) {
            g.update();
            if (g.cursor?.running == false && g.operation == null) break;
          }
          expect(g.error, isEmpty);
          final exit = g.npcs[2]!;
          expect(exit.sprite, 11);
          final recorder = ui.PictureRecorder();
          final canvas = Canvas(recorder);
          final point = const Offset(48, 48), tile = 32.0;
          expect(
            ModernWorldObjects.draw(canvas, g, exit, art, point, tile, null),
            true,
          );
          final picture = recorder.endRecording();
          final actual = await picture.toImage(128, 128);
          final referenceRecorder = ui.PictureRecorder();
          art.drawObject(
            Canvas(referenceRecorder),
            'review-v14:cave-stairs/0',
            const Rect.fromLTWH(41.6, 35.2, 44.8, 44.8),
            Paint()..filterQuality = FilterQuality.medium,
          );
          final referencePicture = referenceRecorder.endRecording();
          final reference = await referencePicture.toImage(128, 128);
          try {
            final a = await actual.toByteData(),
                b = await reference.toByteData();
            expect(
              a!.buffer.asUint8List(),
              b!.buffer.asUint8List(),
              reason: '灯洞$n',
            );
          } finally {
            actual.dispose();
            reference.dispose();
            picture.dispose();
            referencePicture.dispose();
          }
        }
      } finally {
        art.dispose();
      }
    });
  });

  for (final count in [1, 2, 3]) {
    testWidgets('$count个敌人对应$count行，剧情占位不计入，击败归零后行位置固定', (tester) async {
      final g = game();
      final b = GameBattle(
        g,
        monsters: [10, 21, 17].take(count).toList(),
        background: [2, 2, 2],
        randomFight: count != 1,
      );
      g.battle = b;
      Future<void> show(double width) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Align(
              alignment: Alignment.topLeft,
              child: ModernEnemyHealth(battle: b, sceneWidth: width),
            ),
          ),
        );
      }

      for (final width in [390.0, 960.0]) {
        await show(width);
        for (var i = 0; i < count; i++) {
          final enemy = b.presentationEnemies[i];
          expect(find.text(enemy.name), findsOneWidget);
          expect(find.text('${enemy.hp}/${enemy.maxHp}'), findsOneWidget);
        }
        final rows = [
          for (var i = 0; i < count; i++)
            tester.getRect(find.byKey(ValueKey('enemy-health-row-$i'))),
        ];
        final first = b.presentationEnemies.first;
        first.hp = 0;
        first.visible = false;
        await show(width);
        expect(find.text('0/${first.maxHp}'), findsOneWidget);
        for (var i = 0; i < count; i++) {
          expect(
            tester.getRect(find.byKey(ValueKey('enemy-health-row-$i'))),
            rows[i],
          );
        }
        expect(tester.takeException(), isNull);
        first.hp = first.maxHp;
        first.visible = true;
      }
    });
  }
}

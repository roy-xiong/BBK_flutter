import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bbk_flutter/games/fmj/data/game_data.dart';
import 'package:bbk_flutter/games/fmj/engine/game_actor.dart';
import 'package:bbk_flutter/games/fmj/engine/game_engine.dart';
import 'package:bbk_flutter/games/fmj/ui/dialogue_presentation.dart';
import 'package:bbk_flutter/games/fmj/ui/modern_battle_layout.dart';
import 'package:bbk_flutter/games/fmj/ui/modern_map_camera.dart';
import 'package:bbk_flutter/games/fmj/ui/modern_battle_hud.dart';
import 'package:bbk_flutter/games/fmj/ui/game_view_model.dart';
import 'package:bbk_flutter/games/fmj/ui/game_keyboard_bindings.dart';
import 'package:bbk_flutter/games/fmj/ui/game_controls.dart';
import 'package:bbk_flutter/games/fmj/ui/system_font_layout.dart';
import 'game_engine_test.dart' show loadData;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GameData data;
  late Map<String, dynamic> initial;
  setUpAll(() async {
    data = await loadData();
    initial =
        jsonDecode(
              File(
                'test/games/fmj/fixtures/navigation_start.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
  });
  GameEngine engine() => GameEngine(
    data,
    textLayout: FlutterSystemFontLayout(),
    random: math.Random(24),
  );

  test('83 张地图两档视野的四角完整覆盖画面，取样始终位于地图内', () {
    for (final map in data.maps.values) {
      for (final wide in [true, false]) {
        for (final point in [
          (0, 0),
          (map.width - 1, 0),
          (0, map.height - 1),
          (map.width - 1, map.height - 1),
          (map.width ~/ 2, map.height ~/ 2),
        ]) {
          final camera = ModernMapCamera(
            mapWidth: map.width,
            mapHeight: map.height,
            playerX: point.$1,
            playerY: point.$2,
            wide: wide,
          );
          expect(camera.columns * camera.tileSize, 640, reason: map.id);
          expect(camera.rows * camera.tileSize, 384, reason: map.id);
          expect(
            camera.left,
            inInclusiveRange(0, math.max(0, map.width - camera.columns)),
          );
          expect(
            camera.top,
            inInclusiveRange(0, math.max(0, map.height - camera.rows)),
          );
          for (var y = 0; y < camera.rows; y++) {
            for (var x = 0; x < camera.columns; x++) {
              final sample = camera.sample(x, y), target = camera.target(x, y);
              expect(sample.$1, inInclusiveRange(0, map.width - 1));
              expect(sample.$2, inInclusiveRange(0, map.height - 1));
              expect(
                target,
                Rect.fromLTWH(
                  x * camera.tileSize,
                  y * camera.tileSize,
                  camera.tileSize,
                  camera.tileSize,
                ),
              );
            }
          }
        }
      }
    }
  });

  test('每个真实地图图块均有图集切片，包含室内 127 号空白边界', () {
    final frames =
        jsonDecode(
              File('assets/fmj/modern/world-atlas.json').readAsStringSync(),
            )
            as Map;
    for (final map in data.maps.values) {
      for (final tile in map.cells.map((c) => c & 127).toSet()) {
        expect(
          frames.containsKey('7:1:${map.tiles}/$tile'),
          isTrue,
          reason: '${map.id} ${map.name}: $tile',
        );
      }
    }
  });

  test('无机阁真实 NPC 事件的无头像对白署名为无机道人', () {
    final game = engine()..restore(initial);
    expect(game.triggerEvent(9), isTrue);
    final seen = <String>{};
    for (var i = 0; i < 300; i++) {
      game.update();
      final op = game.operation;
      if (op?.kind == 'dialogue') {
        final dialogue = DialoguePresentation.from(game, op!);
        if (dialogue.speaker != null) seen.add(dialogue.speaker!);
        if ((op.args.firstOrNull ?? 0) == 0) expect(dialogue.speaker, '无机道人');
        game.press(GameKey.confirm);
      }
      if (game.cursor?.running == false && game.operation == null) break;
    }
    expect(game.error, isEmpty);
    expect(seen, containsAll(['柳清风', '无机道人']));
  });

  test('对白使用完整角色名，识别全角冒号并保留无署名旁白', () {
    final game = engine();
    final maiden = GameOperation('dialogue', args: [2], text: '柳大哥，醒醒。')
      ..next = 8;
    expect(DialoguePresentation.from(game, maiden).speaker, '慕容小梅');
    final explicit = GameOperation(
      'dialogue',
      args: [0],
      text: '无机道人：听好，为师近观天象。',
    )..next = 99;
    final result = DialoguePresentation.from(game, explicit);
    expect(result.speaker, '无机道人');
    expect(result.text, '听好，为师近观天象。');
    final narrative = GameOperation('dialogue', args: [0], text: '远处传来钟声。')
      ..next = 99;
    expect(DialoguePresentation.from(game, narrative).speaker, isNull);
    final opening = GameOperation('dialogue', args: [0], text: '师兄，原来你在这啊。')
      ..scriptId = '1:1'
      ..address = 172
      ..next = 99;
    expect(DialoguePresentation.from(game, opening).speaker, '小师弟');
  });

  test('默认快捷键与原版相同，自定义冲突按键只属于一个动作', () {
    final defaults = GameKeyboardBindings.defaults;
    expect(defaults.actionFor('KeyQ'), GameControl.quickTravel);
    expect(defaults.actionFor('KeyT'), GameControl.cycleFmjRunSpeed);
    expect(defaults.actionFor('KeyF'), GameControl.search);
    expect(defaults.actionFor('KeyH'), GameControl.help);
    expect(defaults.actionFor('Space'), isNull);
    final edited = defaults.bind(GameControl.cancel, 'KeyQ');
    expect(edited.actionFor('KeyQ'), GameControl.cancel);
    expect(edited.bindings[GameControl.quickTravel], isNot(contains('KeyQ')));
    expect(
      GameKeyboardBindings.fromJson(edited.toJson()).toJson(),
      edited.toJson(),
    );
  });

  test('敌左我右的绘制投影不会修改原战斗坐标和伤害位置', () {
    final game = engine()..restore(initial);
    game.players.addAll(
      [
        GameActor.load(data, 1, 2),
        GameActor.load(data, 1, 3),
      ].whereType<GameActor>(),
    );
    final battle = GameBattle(
      game,
      monsters: [1, 2, 47],
      background: [2, 2, 2],
      randomFight: true,
    );
    final before = [
      for (final p in [...game.players, ...battle.monsters])
        (p.combatX, p.combatY, p.hp, p.mp),
    ];
    final layout = ModernBattleLayout(battle);
    for (final enemy in battle.monsters) {
      expect(layout.point(enemy).dx, lessThan(360));
    }
    for (final player in game.players) {
      expect(layout.point(player).dx, greaterThan(430));
    }
    expect([
      for (final p in [...game.players, ...battle.monsters])
        (p.combatX, p.combatY, p.hp, p.mp),
    ], before);
    final hit = BattleRaise(
      data,
      battle.monsters[1].combatX,
      battle.monsters[1].combatY,
      -10,
      0,
    );
    expect(layout.raisePoint(hit).dx, layout.resting(battle.monsters[1]).dx);
  });

  testWidgets('菱形指令使用原入口，并忽略已经结束的旧战斗按钮', (tester) async {
    final game = engine()..restore(initial);
    final model = GameViewModel()
      ..engine = game
      ..loading = false;
    final battle = GameBattle(
      game,
      monsters: [1],
      background: [2, 2, 2],
      randomFight: true,
    );
    game.battle = battle;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ModernBattleHud(model: model, battle: battle, art: null),
        ),
      ),
    );
    expect(find.text('攻击'), findsOneWidget);
    expect(find.text('法术'), findsOneWidget);
    expect(find.text('合击'), findsOneWidget);
    expect(find.text('策略'), findsOneWidget);
    expect(find.text('气血'), findsWidgets);
    expect(tester.takeException(), isNull);
    game.battle = null;
    final before = jsonEncode(game.snapshot());
    await tester.tap(find.text('攻击'));
    expect(jsonEncode(game.snapshot()), before);
    await tester.pumpWidget(const SizedBox.shrink());
    model.dispose();
  });
}

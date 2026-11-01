import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bbk_flutter/games/fmj/data/game_data.dart';
import 'package:bbk_flutter/games/fmj/engine/game_actor.dart';
import 'package:bbk_flutter/games/fmj/engine/game_engine.dart';
import 'package:bbk_flutter/games/fmj/ui/modern_enemy_health.dart';
import 'package:bbk_flutter/games/fmj/ui/system_font_layout.dart';
import 'game_engine_test.dart' show loadData;

/// 从真实剧情战斗指令进入，验证共享敌人资源不会串用另一段故事的人名。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GameData data;
  setUpAll(() async => data = await loadData());
  GameEngine game() => GameEngine(data, textLayout: FlutterSystemFontLayout())
    ..screen = 'play'
    ..intro = null
    ..players.add(GameActor.load(data, 1, 1)!);

  GameBattle enter(GameEngine game, String scriptId, int address) {
    final script = data.scripts[scriptId]!;
    game.battle = null;
    game.operation = null;
    game.menus.clear();
    game.cursor = ScriptCursor(script)..pointer = script.addresses[address]!;
    game.update();
    expect(game.error, isEmpty);
    expect(game.battle, isNotNull, reason: '$scriptId/$address');
    return game.battle!;
  }

  const expected = <(String, int), List<String>>{
    ('2:18', 953): ['护剑神'],
    ('3:12', 381): ['蛇妖'],
    ('4:8', 354): ['蛇妖'],
    ('5:1', 736): ['门卫一', '门卫二'],
    ('5:15', 157): ['打手', '李虎', '打手'],
    ('7:1', 739): ['游人', '游人', '游人'],
    ('7:2', 191): ['游人', '游人', '游人'],
    ('7:14', 108): ['小偷'],
    ('11:10', 745): ['鬼王'],
    ('13:2', 572): ['北海蛟', '北海龙'],
    ('13:2', 703): ['北海蛟'],
    ('13:2', 802): ['北海龙'],
  };

  for (final entry in expected.entries) {
    test('${entry.key}按当前剧情显示${entry.value.join('、')}', () {
      final battle = enter(game(), entry.key.$1, entry.key.$2);
      expect(battle.presentationEnemies.map((p) => p.name), entry.value);
      if (battle.presentationEnemies.length == 1) {
        expect(battle.monsters.first.visible, isFalse);
        expect(battle.monsters.first.name, entry.value.single);
      }
    });
  }

  test('全51处剧情战斗保持资源、数值、奖励与事件分支不变', () {
    var count = 0;
    for (final script in data.scripts.values) {
      for (final command in script.commands.where((c) => c.opcode == 39)) {
        final battle = enter(game(), script.id, command.address);
        final ids = command.args.skip(1).take(3).where((id) => id > 0).toList();
        final actors = battle.presentationEnemies;
        expect(actors.map((a) => a.index), ids);
        for (var i = 0; i < ids.length; i++) {
          final original = GameActor.load(data, 3, ids[i])!;
          expect(actors[i].sprite, original.sprite);
          expect(actors[i].maxHp, original.maxHp);
          expect(actors[i].maxMp, original.maxMp);
          expect(actors[i].attack, original.attack);
          expect(actors[i].defense, original.defense);
          expect(actors[i].magics(data), original.magics(data));
          if (!expected.containsKey((script.id, command.address))) {
            expect(actors[i].name, original.name);
          }
        }
        expect(battle.totalExp, actors.fold(0, (v, a) => v + a.rewardExp));
        expect(battle.totalMoney, actors.fold(0, (v, a) => v + a.money));
        expect(battle.loss, command.args[13]);
        expect(battle.win, command.args[14]);
        count++;
      }
    }
    expect(count, 51);
  });

  test('同一资源跨场景不串名，随机战斗仍使用资源原名', () {
    final g = game();
    expect(enter(g, '7:1', 739).presentationEnemies.first.name, '游人');
    expect(enter(g, '5:15', 157).presentationEnemies[1].name, '李虎');
    expect(enter(g, '7:14', 108).presentationEnemies.single.name, '小偷');
    expect(enter(g, '7:2', 191).presentationEnemies[1].name, '游人');
    final random = GameBattle(
      g,
      monsters: [9, 20, 26],
      background: [1, 1, 1],
      randomFight: true,
    );
    expect(random.presentationEnemies.map((p) => p.name), ['李虎', '小偷袁', '鲁大憨']);
    expect(GameActor.load(data, 3, 9)!.name, '李虎');
    expect(GameActor.load(data, 3, 20)!.name, '小偷袁');
  });

  testWidgets('手机和桌面的敌方气血栏实际显示剧情名称', (tester) async {
    final battle = enter(game(), '7:2', 191);
    for (final width in [390.0, 960.0]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Align(
            alignment: Alignment.topLeft,
            child: ModernEnemyHealth(battle: battle, sceneWidth: width),
          ),
        ),
      );
      expect(find.text('游人'), findsNWidgets(3));
      for (final name in ['李虎', '小偷袁', '鲁大憨']) {
        expect(find.text(name), findsNothing);
      }
      expect(tester.takeException(), isNull);
    }
  });
}

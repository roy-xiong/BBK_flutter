import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bbk_flutter/games/fmj/data/game_data.dart';
import 'package:bbk_flutter/games/fmj/engine/game_actor.dart';
import 'package:bbk_flutter/games/fmj/engine/game_engine.dart';
import 'package:bbk_flutter/games/fmj/ui/game_controls.dart';
import 'package:bbk_flutter/games/fmj/ui/system_font_layout.dart';
import 'game_engine_test.dart' show loadData;

/// 使用真实背包、菜单和回合队列，覆盖快捷入口的选择、取消及消耗边界。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GameData data;
  setUpAll(() async => data = await loadData());
  GameEngine game() => GameEngine(data, textLayout: FlutterSystemFontLayout())
    ..screen = 'play'
    ..intro = null
    ..players.addAll([
      GameActor.load(data, 1, 1)!,
      GameActor.load(data, 1, 2)!,
    ]);
  GameBattle battle(GameEngine g) {
    g.menus.clear();
    return g.battle = GameBattle(
      g,
      monsters: [1, 2, 3],
      background: [2, 2, 2],
      randomFight: true,
    );
  }

  test('短按优先弯月刀，耗尽后复用备用武器，再耗尽时重新选择', () {
    final g = game()
      ..addGoods('7:19')
      ..addGoods('7:9', 2);
    g.preferredThrowWeapon = '7:9';
    var b = battle(g)..quickThrow();
    expect(b.queue.single.resource, '7:19');
    expect(g.inventory['7:19'], 1, reason: '排队阶段不能提前消耗');
    expect(g.preferredThrowWeapon, '7:9', reason: '优先弯月刀不能覆盖备用选择');
    g.useGoods('7:19');
    b = battle(g)..quickThrow();
    expect(b.queue.single.resource, '7:9');
    expect(b.queue.single.targets, hasLength(3));
    g.useGoods('7:9', 2);
    g.addGoods('7:1');
    b = battle(g)..quickThrow();
    expect(g.menus.last.ids, ['7:1']);
    g.press(GameKey.confirm);
    expect(g.preferredThrowWeapon, '7:1');
    expect(b.queue.single.resource, '7:1');
    expect(b.queue.single.targets, hasLength(1));
  });

  test('长按强制选背包武器，取消不投掷，库存含药品暗器时仍只列武器', () {
    final g = game()
      ..addGoods('7:19')
      ..addGoods('7:9')
      ..addGoods('9:1')
      ..addGoods('8:1');
    final b = battle(g)..quickThrow(chooseWeapon: true);
    expect(g.menus.last.ids.toSet(), {'7:19', '7:9'});
    expect(b.queue, isEmpty);
    g.press(GameKey.cancel);
    expect(g.menus, isEmpty);
    expect(g.preferredThrowWeapon, isNull);
    expect(g.inventory['7:19'], 1);
    b.quickThrow(chooseWeapon: true);
    g.menus.last.selected = g.menus.last.ids.indexOf('7:9');
    g.press(GameKey.confirm);
    expect(g.preferredThrowWeapon, '7:9');
    expect(b.queue.single.resource, '7:9');
  });

  test('同回合预留最后一把武器，忙碌、剧情和禁投状态不重复投掷', () {
    final g = game()..addGoods('7:19');
    final b = battle(g)..quickThrow();
    b.quickThrow();
    expect(b.queue, hasLength(1));
    expect(g.notice, contains('武器'));
    b.phase = 'perform';
    b.quickThrow(chooseWeapon: true);
    expect(g.menus, isEmpty);
    b.phase = 'select';
    b.scriptPaused = true;
    b.quickThrow(chooseWeapon: true);
    expect(g.menus, isEmpty);
    b.scriptPaused = false;
    g.allowTossArm = false;
    b.quickThrow();
    expect(g.menus, isEmpty);
    expect(b.queue, hasLength(1));
  });

  test('技能和合击复用原选择流程，弹窗中不叠加操作', () {
    final g = game();
    g.players.first.learned = 10;
    final b = battle(g)..quickMagic();
    expect(g.menus.last.kind, 'magic');
    final depth = g.menus.length;
    b.quickMagic();
    b.quickCoop();
    expect(g.menus, hasLength(depth));
    g.press(GameKey.cancel);
    b.quickCoop();
    expect(b.targetKind, 'coop');
    g.press(GameKey.confirm);
    expect(b.current?.kind ?? b.queue.first.kind, 'coop');
  });

  for (final automatic in [false, true]) {
    test('钨龙剑${automatic ? '自动' : '手动'}普攻全体，普通木剑仍是单体', () {
      final g = game();
      g.players.first.equipment[4] = '7:9';
      g.players.first.attackStatus = 0;
      final b = battle(g);
      if (automatic) {
        g.preferences['autoBattle'] = true;
        b.update();
      } else {
        g.press(GameKey.confirm);
      }
      final action = [
        if (b.current != null) b.current!,
        ...b.queue,
      ].firstWhere((a) => identical(a.actor, g.players.first));
      expect(action.kind, 'attack');
      expect(action.targets, hasLength(3));
      g.preferences['autoBattle'] = false;
      g.players.first.equipment[4] = '7:1';
      final ordinary = battle(g);
      g.press(GameKey.confirm);
      expect(ordinary.targetKind, 'attack');
      g.press(GameKey.confirm);
      expect(ordinary.queue.single.targets, hasLength(1));
    });
  }

  test('传统投掷菜单也让钨龙剑群攻，实际命中三敌只消耗一把', () {
    final g = game()..addGoods('7:9', 2);
    g.players.removeLast();
    final b = battle(g)..icon = 3;
    g.press(GameKey.confirm);
    g.selectMenu(g.menus.last, 3);
    g.selectMenu(g.menus.last, 1);
    g.press(GameKey.confirm);
    final action = b.current ?? b.queue.first;
    expect(action.resource, '7:9');
    expect(action.targets, hasLength(3));
    final before = b.monsters.map((m) => m.hp).toList();
    for (var i = 0; i < 200 && !action.started; i++) {
      b.update();
    }
    expect(action.started, true);
    expect(g.inventory['7:9'], 1);
    for (var i = 0; i < before.length; i++) {
      expect(b.monsters[i].hp, lessThan(before[i]));
    }
  });

  test('自动战斗开启时快捷投掷不会在下一帧被普攻覆盖', () {
    final g = game()..addGoods('7:19');
    g.preferences['autoBattle'] = true;
    final b = battle(g)..quickThrow();
    for (var i = 0; i < 4; i++) {
      b.update();
    }
    expect(b.phase, 'select');
    expect(b.queue.single.kind, 'throw');
    expect(g.inventory['7:19'], 1);
    expect(g.preferences['autoBattle'], true);
    g.press(GameKey.confirm);
    g.press(GameKey.confirm);
    expect(b.phase, 'perform');
    expect(
      [
        if (b.current != null) b.current!,
        ...b.queue,
      ].where((a) => a.kind == 'throw'),
      hasLength(1),
    );
  });

  for (final portrait in [false, true]) {
    testWidgets('${portrait ? '竖屏' : '横屏'}投掷短按一次，长按仅打开选择且不先投掷', (tester) async {
      final inputs = <GameControl>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: portrait ? 360 : 720,
              height: portrait ? 460 : 360,
              child: portrait
                  ? PortraitGameControlsPanel(
                      hapticsEnabled: false,
                      onInput: inputs.add,
                      showBattleButtons: true,
                      battleButtonsEnabled: true,
                    )
                  : GameControlsOverlay(
                      hapticsEnabled: false,
                      onInput: inputs.add,
                      showBattleButtons: true,
                      battleButtonsEnabled: true,
                    ),
            ),
          ),
        ),
      );
      final toss = find.byKey(const ValueKey('fmj-battle-throw'));
      expect(toss, findsOneWidget);
      expect(tester.getSize(toss).shortestSide, greaterThanOrEqualTo(46));
      await tester.tap(toss);
      await tester.pump();
      expect(inputs, [GameControl.quickThrow]);
      inputs.clear();
      final gesture = await tester.startGesture(tester.getCenter(toss));
      await tester.pump(const Duration(milliseconds: 700));
      expect(inputs, [GameControl.chooseThrowWeapon]);
      await gesture.up();
      await tester.pump();
      expect(inputs, [GameControl.chooseThrowWeapon]);
      await tester.tap(find.byKey(const ValueKey('fmj-battle-magic')));
      await tester.tap(find.byKey(const ValueKey('fmj-battle-coop')));
      expect(inputs.skip(1), [GameControl.quickMagic, GameControl.quickCoop]);
      expect(tester.takeException(), isNull);
    });
  }
}

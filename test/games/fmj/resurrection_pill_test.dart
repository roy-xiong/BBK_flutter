import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:bbk_flutter/games/fmj/data/game_data.dart';
import 'package:bbk_flutter/games/fmj/engine/game_actor.dart';
import 'package:bbk_flutter/games/fmj/engine/game_engine.dart';
import 'package:bbk_flutter/games/fmj/ui/system_font_layout.dart';
import 'game_engine_test.dart' show loadData;

/// 通过真实菜单、剧情指令、存档和战斗结算验证新丹药，不能直接写复活结果旗标。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GameData data;
  setUpAll(() async => data = await loadData());
  GameEngine game() => GameEngine(data, textLayout: FlutterSystemFontLayout())
    ..screen = 'play'
    ..intro = null
    ..map = data.maps['1:46']
    ..cursor = (ScriptCursor(data.scripts['14:8']!)..running = false)
    ..players.addAll(
      [1, 2, 3].map(
        (i) => GameActor.load(data, 1, i)!
          ..x = 10
          ..y = 7,
      ),
    );
  void begin(GameEngine g, int address) {
    g.menus.clear();
    g.operation = null;
    g.battle = null;
    g.cursor = ScriptCursor(data.scripts['14:8']!)
      ..pointer = data.scripts['14:8']!.addresses[address]!;
  }

  void drain(GameEngine g, {int? choice}) {
    for (var i = 0; i < 1600; i++) {
      g.update();
      expect(g.error, isEmpty);
      final op = g.operation;
      if (op?.kind == 'choice') {
        if (choice == null) return;
        g.choose(choice, expected: op);
      } else if (op != null) {
        g.press(GameKey.confirm);
      }
      if (g.canSave) return;
    }
    fail('剧情未结束 ${g.cursor?.pointer} ${g.operation?.kind}');
  }

  void depart(GameEngine g) {
    begin(g, 1840);
    g.update();
    expect(g.players.any((p) => p.index == 3), false);
    g.battle = null;
    g.operation = null;
    g.cursor!.running = false;
  }

  test('新丹药可出售一百万，给选中人物服用后双上限+50且按新上限回满', () {
    final g = game(), p = g.players[1];
    g.addGoods('11:16');
    expect(g.goodsName('11:16'), '起死回生丹');
    expect(g.goods('11:16')?.word(20), 1000000);
    final hp = p.maxHp, mp = p.maxMp;
    p
      ..hp = 1
      ..mp = 0;
    expect(g.consumeMedicine(p, '11:16'), true);
    expect(
      [p.maxHp, p.hp, p.maxMp, p.mp],
      [hp + 50, hp + 50, mp + 50, mp + 50],
    );
    expect(g.inventory['11:16'] ?? 0, 0);
    expect(g.consumeMedicine(p, '11:16'), false);
    expect(p.maxHp, hp + 50);
  });
  test('出售数量确认真实成交且不能同时保留/服用已售丹药', () {
    final g = game()..addGoods('11:16');
    g.openInventory(mode: 'sell');
    g.press(GameKey.confirm);
    final menu = g.menus.last;
    expect(menu.purchase?.unitPrice, 1000000);
    g.changePurchaseQuantity(menu, 1);
    g.press(GameKey.confirm);
    expect(g.money, 1000000);
    expect(g.inventory['11:16'] ?? 0, 0);
    expect(g.consumeMedicine(g.player!, '11:16'), false);
  });
  test('战斗中服用同样只扣一颗，并保留永久成长到下一场', () {
    final g = game(), p = g.player!;
    g.addGoods('11:16');
    final hp = p.maxHp, mp = p.maxMp;
    final b = g.battle = GameBattle(
      g,
      monsters: [1],
      background: [2, 2, 2],
      randomFight: true,
    );
    p
      ..hp = 0
      ..mp = 0;
    b
      ..phase = 'perform'
      ..current = BattleAction(g.players[1], [p], 'item', resource: '11:16');
    b.update();
    expect(
      [p.maxHp, p.hp, p.maxMp, p.mp],
      [hp + 50, hp + 50, mp + 50, mp + 50],
    );
    expect(g.inventory['11:16'] ?? 0, 0);
  });
  test('隐藏点位于大环刀右一格，已领刀仍能领丹，见师父后不能领', () {
    final script = data.scripts['2:12']!;
    expect(
      script.commands.any(
        (c) => c.opcode == 32 && c.args.toString() == '[5, 18, 6, 2]',
      ),
      true,
    );
    for (final before in [true, false]) {
      final g = game()
        ..map = data.maps['1:2']
        ..cursor = ScriptCursor(script);
      g.flags.add(2390);
      if (before) g.flags.add(1);
      drain(g);
      expect(g.npcs.containsKey(4), false);
      expect(g.npcs.containsKey(5), before);
      g.triggerEvent(5);
      drain(g);
      expect(g.inventory['11:16'] ?? 0, before ? 1 : 0);
      g.triggerEvent(5);
      drain(g);
      expect(g.inventory['11:16'] ?? 0, before ? 1 : 0);
    }
  });
  test('有药才提示复活，默认使用，确认后原人物成长、装备和法术完整恢复', () {
    final g = game(), yuan = g.players.last;
    yuan.levelUp(data, 35);
    yuan.exp = 123;
    g.addGoods('7:33');
    g.equip(yuan, '7:33');
    yuan.extraMagic.add('1:11');
    final original = yuan.toJson();
    depart(g);
    g.addGoods('11:16');
    begin(g, 2451);
    drain(g);
    expect(g.operation?.kind, 'choice');
    expect(g.operation?.options, ['使用丹药', '不使用']);
    expect(g.operation?.selected, 0);
    expect(g.operation?.armed, true);
    expect(g.operation?.text, contains('复活袁萍芷'));
    g.press(GameKey.confirm);
    drain(g);
    final revived = g.players.singleWhere((p) => p.index == 3);
    expect(g.inventory['11:16'] ?? 0, 0);
    expect(g.inventory['14:10'], 1);
    expect(revived.level, original['level']);
    expect(revived.exp, 123);
    expect(revived.equipment, original['equipment']);
    expect(revived.extraMagic, contains('1:11'));
    expect(revived.maxHp, original['maxHp']);
    expect(revived.hp, revived.maxHp);
    expect(revived.mp, revived.maxMp);
    expect(g.flags, contains(2392));
    g.partyFollow.synchronize();
    expect(g.partyFollow.followers.map((p) => p.actor.index), contains(3));
    expect(g.npcs.containsKey(7), false);
    expect(g.players.where((p) => p.index == 3), hasLength(1));
  });
  test('没有丹药、已经吃掉或卖掉时保留原剧情，不弹复活框', () {
    for (final mode in ['none', 'ate', 'sold']) {
      final g = game();
      if (mode != 'none') g.addGoods('11:16');
      if (mode == 'ate') g.consumeMedicine(g.player!, '11:16');
      if (mode == 'sold') {
        g.openInventory(mode: 'sell');
        g.press(GameKey.confirm);
        g.changePurchaseQuantity(g.menus.last, 1);
        g.press(GameKey.confirm);
      }
      depart(g);
      begin(g, 2451);
      drain(g);
      expect(g.operation, isNull);
      expect(g.players.any((p) => p.index == 3), false);
      expect(g.inventory['14:10'], 1);
      expect(g.flags.contains(2392), false);
    }
  });
  test('拒绝复活不耗药，不添加人物；重复进入已复活分支不重复扣药或加人', () {
    final g = game();
    depart(g);
    g.addGoods('11:16', 2);
    begin(g, 2451);
    drain(g, choice: 1);
    expect(g.inventory['11:16'], 2);
    expect(g.players.any((p) => p.index == 3), false);
    begin(g, 9000);
    drain(g, choice: 0);
    expect(g.inventory['11:16'], 1);
    expect(g.players.where((p) => p.index == 3), hasLength(1));
    begin(g, 9000);
    drain(g, choice: 0);
    expect(g.inventory['11:16'], 1);
    expect(g.players.where((p) => p.index == 3), hasLength(1));
  });
  test('离队备份随快照读回，读档失败不污染当前游戏', () {
    final g = game(), yuan = g.players.last;
    yuan.levelUp(data, 40);
    yuan.attack += 77;
    final attack = yuan.attack;
    depart(g);
    final saved = GameData.decodeObject(jsonEncode(g.snapshot()));
    final next = game();
    next.restore(saved);
    next.addGoods('11:16');
    begin(next, 2451);
    drain(next, choice: 0);
    expect(next.players.singleWhere((p) => p.index == 3).attack, attack);
    final before = next.snapshot();
    final bad = GameData.decodeObject(jsonEncode(before))
      ..['departedYuan'] = {'type': 1, 'index': 1};
    expect(() => next.restore(bad), throwsFormatException);
    expect(next.snapshot(), before);
  });
}

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:bbk_flutter/games/fmj/data/game_data.dart';
import 'package:bbk_flutter/games/fmj/engine/game_actor.dart';
import 'package:bbk_flutter/games/fmj/engine/game_engine.dart';
import 'package:bbk_flutter/games/fmj/ui/system_font_layout.dart';
import 'game_engine_test.dart' show loadData;

/// 经真实选关入口检查背包、穿戴、成长及数量守恒，不通过恢复快照绕过选关。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GameData data;
  setUpAll(() async => data = await loadData());
  GameEngine game([List<int> ids = const [1]]) =>
      GameEngine(data, textLayout: FlutterSystemFontLayout())
        ..screen = 'play'
        ..intro = null
        ..map = data.maps['1:2']
        ..cursor = (ScriptCursor(data.scripts['2:12']!)..running = false)
        ..players.addAll(
          ids.map(
            (id) => GameActor.load(data, 1, id)!
              ..x = 11
              ..y = 8,
          ),
        );
  Map<String, dynamic> stage(String id) =>
      data.stages.singleWhere((s) => s['id'] == id);
  int owned(GameEngine g, String id) =>
      (g.inventory[id] ?? 0) +
      g.players.fold<int>(
        0,
        (n, p) => n + p.equipment.where((v) => v == id).length,
      );

  test('丹药常规说明只有价格和服用效果，不暴露隐藏人物剧情', () {
    final text = game().goods('11:16')!.text(30);
    for (final hint in ['袁', '朱雀', '救回', '背包', '彩蛋']) {
      expect(text, isNot(contains(hint)));
    }
    expect(text, contains('50'));
    expect(text, contains('一百万'));
  });
  test('跨关保留大环刀、全部库存、原穿戴、永久成长和高额金钱', () {
    final g = game(), p = g.player!;
    p.levelUp(data, 55);
    g.addGoods('7:33');
    g.equip(p, '7:33');
    g.addGoods('11:16', 3);
    g.addGoods('9:1', 17);
    g.addGoods('8:7', 4);
    g.consumeMedicine(p, '11:16');
    g.money = 1234567;
    final inventory = Map<String, int>.from(g.inventory),
        equipment = List<String?>.of(p.equipment);
    final stats = [
      p.level,
      p.maxHp,
      p.maxMp,
      p.attack,
      p.defense,
      p.speed,
      p.spirit,
      p.luck,
    ];
    g.selectStage(stage('stage-087'));
    for (final entry in inventory.entries) {
      expect(g.inventory[entry.key], entry.value, reason: entry.key);
    }
    final current = g.player!;
    expect(current.equipment, equipment);
    expect([
      current.level,
      current.maxHp,
      current.maxMp,
      current.attack,
      current.defense,
      current.speed,
      current.spirit,
      current.luck,
    ], stats);
    expect(g.money, 1234567);
    expect(current.immunity & 15, 15);
  });
  test('人数减少时其他队员的装备回到背包，重复选关不复制或丢大环刀', () {
    final g = game([1, 2, 3]);
    for (final p in g.players) {
      g.addGoods('7:33');
      g.equip(p, '7:33');
    }
    expect(owned(g, '7:33'), 3);
    for (var i = 0; i < 3; i++) {
      g.selectStage(stage('stage-001'));
      expect(g.players.map((p) => p.index), [1]);
      expect(g.player!.equipment[4], '7:33');
      expect(g.inventory['7:33'], 2);
      expect(owned(g, '7:33'), 3);
    }
    g.selectStage(stage('stage-060'));
    expect(owned(g, '7:33'), 3);
  });
  test('模板护甲不覆盖已有肩披，必需品可用且穿戴旗标反映真实装备', () {
    final g = game([1, 2]);
    g.addGoods('4:1');
    g.equip(g.player!, '4:1');
    g.selectStage(stage('stage-033'));
    expect(g.player!.equipment[6], '4:1');
    expect(owned(g, '4:14'), greaterThanOrEqualTo(1));
    final r = g.goods('4:14')!;
    expect(r.word(132), greaterThan(0));
    expect(g.flags.contains(r.word(132)), false, reason: '未穿模板甲不伪造已穿标记');
    g.equip(g.player!, '4:14');
    expect(g.flags, contains(r.word(132)));
  });
  test('已拥有的模板装备不因反复选关增加；空场直接选关仍提供原始开局配置', () {
    final g = game([1, 2]);
    g.addGoods('4:14');
    g.equip(g.player!, '4:14');
    for (var i = 0; i < 3; i++) {
      g.selectStage(stage('stage-033'));
      expect(owned(g, '4:14'), 1);
    }
    final fresh = GameEngine(data, textLayout: FlutterSystemFontLayout());
    fresh.selectStage(stage('stage-033'));
    expect(fresh.player!.equipment[6], '4:14');
    expect(fresh.players[1].equipment[6], '4:13');
    expect(fresh.money, 5000);
  });
  test('稀有隐藏点的领取记录与投掷偏好跨关保留，回开局不能重复领取', () {
    final g = game()
      ..flags.addAll([2390, 2391])
      ..preferredThrowWeapon = '7:33';
    g.addGoods('7:33');
    g.addGoods('11:16');
    g.selectStage(stage('stage-001'));
    expect(g.flags, containsAll([2390, 2391]));
    expect(g.preferredThrowWeapon, '7:33');
    g.map = data.maps['1:2'];
    g.cursor = ScriptCursor(data.scripts['2:12']!)..running = false;
    for (final event in [4, 5]) {
      g.triggerEvent(event);
      for (var i = 0; i < 40; i++) {
        g.update();
        if (g.operation != null) g.press(GameKey.confirm);
      }
    }
    expect(g.inventory['11:16'], 1);
    expect(owned(g, '7:33'), 1);
  });
  test('跨关后读档和恢复选关前进度都不丢物品或重复叠加装备数值', () {
    final g = game([1, 2]);
    g.addGoods('7:33');
    g.equip(g.player!, '7:33');
    g.addGoods('11:16', 2);
    g.addGoods('9:1', 7);
    final original = GameData.decodeObject(jsonEncode(g.snapshot()));
    g.selectStage(stage('stage-001'));
    final before = g.player!.attack,
        saved = GameData.decodeObject(jsonEncode(g.snapshot()));
    g.restore(saved);
    expect(g.player!.attack, before);
    expect(g.player!.equipment[4], '7:33');
    expect(g.inventory['11:16'], 2);
    expect(g.restoreBeforeStage(), true);
    expect(g.snapshot(), original);
  });
  test('连续切换全部96个节点，稀有物品和原武器数量保持，属性不重复叠加', () {
    final g = game([1, 2, 3]);
    for (final p in g.players) {
      p.levelUp(data, 60);
      g.addGoods('7:33');
      g.equip(p, '7:33');
    }
    g.addGoods('11:16', 2);
    g.addGoods('9:1', 17);
    final attack = g.player!.attack;
    for (final target in data.stages) {
      g.selectStage(target);
      expect(owned(g, '7:33'), 3, reason: '${target['id']}');
      expect(g.inventory['11:16'], 2, reason: '${target['id']}');
      expect(g.inventory['9:1'], 17, reason: '${target['id']}');
      expect(g.player!.equipment[4], '7:33', reason: '${target['id']}');
      expect(g.player!.attack, attack, reason: '${target['id']}');
      expect(g.error, isEmpty);
    }
  });
  test('全部218件物品连续选关后实际拥有量不减少', () {
    final g = game();
    final ids = [
      ...data.offsets.keys
          .where((key) => key.startsWith('6:'))
          .map((key) => key.substring(2)),
      '7:33',
      '11:16',
    ];
    for (final id in ids) {
      g.addGoods(id, 2);
    }
    final before = {for (final id in ids) id: owned(g, id)};
    for (final target in data.stages) {
      g.selectStage(target);
      for (final id in ids) {
        expect(
          owned(g, id),
          greaterThanOrEqualTo(before[id]!),
          reason: '${target['id']} $id',
        );
      }
    }
  });
}

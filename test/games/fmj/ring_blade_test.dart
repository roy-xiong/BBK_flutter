import 'package:flutter_test/flutter_test.dart';
import 'package:bbk_flutter/games/fmj/data/game_data.dart';
import 'package:bbk_flutter/games/fmj/engine/game_actor.dart';
import 'package:bbk_flutter/games/fmj/engine/game_engine.dart';
import 'package:bbk_flutter/games/fmj/ui/system_font_layout.dart';
import 'game_engine_test.dart' show loadData;

/// 真实装备、伤害、胜利、存档与剧情入口回归，避免仅验证配置常量。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GameData data;
  setUpAll(() async => data = await loadData());
  GameEngine game() => GameEngine(data, textLayout: FlutterSystemFontLayout())
    ..screen = 'play'
    ..intro = null
    ..map = data.maps['1:2']
    ..cursor = (ScriptCursor(data.scripts['2:12']!)..running = false)
    ..players.addAll([1, 2, 3].map((id) => GameActor.load(data, 1, id)!));

  test('大环刀是全员可装备的真实菜单物品，默认关闭敌人四种异常', () {
    final g = game();
    expect(g.goodsName('7:33'), '大环刀');
    expect(g.goods('7:33')?.byte(25), 500);
    expect(g.goods('7:33')?.byte(28), 16);
    for (final p in g.players) {
      expect(g.canEquip(p, '7:33'), isTrue);
    }
    expect(g.cheatWeaponIds.first, '7:33');
  });

  test('七项加500，可改值/禁用，不累加；卸下精确撤回，读档不重复加', () {
    final g = game(), p = g.players.first;
    g.unequip(p, 4);
    p
      ..x = 11
      ..y = 8;
    final before = [
      p.maxHp,
      p.maxMp,
      p.attack,
      p.defense,
      p.speed,
      p.spirit,
      p.luck,
    ];
    g.addGoods('7:33');
    expect(g.equip(p, '7:33'), isTrue);
    expect([
      p.maxHp,
      p.maxMp,
      p.attack,
      p.defense,
      p.speed,
      p.spirit,
      p.luck,
    ], before.map((v) => v + 500));
    g.setPreference('ringBlade', {
      'attack': 700,
      'attackOn': true,
      'defenseOn': false,
    });
    expect(p.attack, before[2] + 700);
    expect(p.defense, before[3]);
    final save = g.snapshot();
    g.restore(save);
    final restored = g.players.first;
    expect(restored.attack, before[2] + 700);
    g.setPreference('ringBlade', {'attack': 900});
    expect(restored.attack, before[2] + 900);
    g.restore(save);
    expect(g.players.first.attack, before[2] + 900, reason: '旧档按当前设置重新对齐');
    g.unequip(g.players.first, 4);
    expect([
      g.players.first.maxHp,
      g.players.first.maxMp,
      g.players.first.attack,
      g.players.first.defense,
      g.players.first.speed,
      g.players.first.spirit,
      g.players.first.luck,
    ], before);
  });

  test('普通攻击命中谁吸谁，实际不足只回实际值，防御不触发吸取', () {
    final g = game(), p = g.players.first;
    g.addGoods('7:33');
    g.equip(p, '7:33');
    g.setPreference('ringBlade', {'attackOn': false, 'groupAttack': false});
    p
      ..attack = 1
      ..hp = 100
      ..mp = 0;
    final b = g.battle = GameBattle(
      g,
      monsters: [1, 2, 3],
      background: [2, 2, 2],
      randomFight: true,
    );
    for (final enemy in b.monsters) {
      enemy
        ..maxHp = 1000
        ..hp = 1000
        ..maxMp = 500
        ..mp = 500
        ..defense = 999;
    }
    final target = b.monsters[1];
    b
      ..phase = 'perform'
      ..current = BattleAction(p, [target], 'attack');
    b.update();
    expect(p.hp, 300);
    expect(p.mp, 200);
    expect(target.hp, lessThanOrEqualTo(799));
    expect(target.mp, 300);
    expect(b.monsters.first.hp, 1000);
    expect(b.monsters.first.mp, 500);
    expect(target.status, 0, reason: '默认四种异常关闭');
    p
      ..hp = 100
      ..mp = 0;
    target
      ..hp = 1000
      ..mp = 35;
    b
      ..phase = 'perform'
      ..current = BattleAction(p, [target], 'attack');
    b.update();
    expect(p.mp, 35);
    expect(target.mp, 0);
    p
      ..hp = 100
      ..mp = 0;
    b
      ..phase = 'perform'
      ..current = BattleAction(p, [p], 'defend');
    b.update();
    expect(p.hp, 100);
    expect(p.mp, 0);
    target
      ..hp = 1000
      ..mp = 500;
    b
      ..phase = 'perform'
      ..current = BattleAction(p, [target], 'coop');
    b.update();
    expect(p.hp, 100, reason: '默认物理合击不重复触发普通攻击吸取');
    expect(p.mp, 0);
  });

  test('装备后免疫四种异常，开启敌方异常后按目标施加；关闭后恢复', () {
    final g = game(), p = g.players.first;
    g.addGoods('7:33');
    g.equip(p, '7:33');
    expect(p.immunity & 15, 15);
    g.setPreference('ringBlade', {
      'enemyPoison': true,
      'enemyConfuse': true,
      'enemySeal': true,
      'enemySleep': true,
      'statusRounds': 5,
      'attackOn': false,
      'hpDrainOn': false,
      'mpDrainOn': false,
    });
    final b = g.battle = GameBattle(
      g,
      monsters: [1, 2],
      background: [2, 2, 2],
      randomFight: true,
    );
    final target = b.monsters.first
      ..hp = 9999
      ..maxHp = 9999
      ..immunity = 0
      ..luck = 0;
    b
      ..phase = 'perform'
      ..current = BattleAction(p, [target], 'attack');
    b.update();
    expect(target.status & 15, 15);
    expect(target.statusRounds.values, everyElement(5));
    expect(b.monsters.last.status, 0);
    g.unequip(p, 4);
    expect(p.immunity & 15, 0);
  });

  test('经验全队2倍仅结算一次，多把不叠乘，开关关闭恢复正常', () {
    final g = game();
    for (final p in g.players) {
      p.levelUp(data, 10);
      p.exp = 0;
      g.addGoods('7:33');
      g.equip(p, '7:33');
    }
    var b = g.battle = GameBattle(
      g,
      monsters: [1],
      background: [2, 2, 2],
      randomFight: true,
    )..totalExp = 10;
    b.forceWin();
    b.forceWin();
    expect(g.players.map((p) => p.exp), [20, 20, 20]);
    g.setPreference('ringBlade', {'experienceOn': false});
    b = g.battle = GameBattle(
      g,
      monsters: [1],
      background: [2, 2, 2],
      randomFight: true,
    )..totalExp = 10;
    b.forceWin();
    expect(g.players.map((p) => p.exp), [30, 30, 30]);
  });

  test('百草地右一格隐藏点：师父前一次领取，见师父后不能领', () {
    final script = data.scripts['2:12']!;
    final spawn = script.commands.singleWhere(
      (c) => c.opcode == 32 && c.arg(0) == 4,
    );
    expect(spawn.args, [4, 18, 5, 2]);
    for (final beforeMaster in [true, false]) {
      final g = game()..cursor = (ScriptCursor(script)..running = false);
      if (beforeMaster) g.flags.add(1);
      expect(g.triggerEvent(4), true);
      for (var i = 0; i < 60; i++) {
        g.update();
        if (g.operation != null) g.press(GameKey.confirm);
      }
      expect(g.inventory['7:33'] ?? 0, beforeMaster ? 1 : 0);
      g.triggerEvent(4);
      for (var i = 0; i < 60; i++) {
        g.update();
        if (g.operation != null) g.press(GameKey.confirm);
      }
      expect(g.inventory['7:33'] ?? 0, beforeMaster ? 1 : 0);
    }
  });

  test('多年以后无机阁先只显示柳清风，小梅由原剧情NPC按时进场', () {
    final g = game()..map = data.maps['2:7'];
    g.player!
      ..x = 11
      ..y = 8;
    g.cursor = ScriptCursor(data.scripts['2:18']!)
      ..pointer = data.scripts['2:18']!.addresses[1134]!;
    g.partyFollow.synchronize();
    expect(g.partyFollow.followers, isEmpty);
    final xiaomei = GameActor.load(data, 2, 6)!
      ..x = 17
      ..y = 7;
    g.npcs[21] = xiaomei;
    expect(
      g.partyFollow.worldActors.where(
        (pose) => pose.actor.name == xiaomei.name,
      ),
      hasLength(1),
    );
  });
}

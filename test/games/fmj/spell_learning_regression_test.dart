import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bbk_flutter/games/fmj/data/game_data.dart';
import 'package:bbk_flutter/games/fmj/engine/game_actor.dart';
import 'package:bbk_flutter/games/fmj/engine/game_engine.dart';
import 'package:bbk_flutter/games/fmj/ui/system_font_layout.dart';
import 'game_engine_test.dart' show loadData;

/// 真实ROM的成长法术数量在学全后归零；覆盖逐级、跳级、读旧档和战斗入口。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GameData data;
  late Map<String, dynamic> initial;
  setUpAll(() async {
    data = await loadData();
    initial = GameData.decodeObject(
      File('test/games/fmj/fixtures/navigation_start.json').readAsStringSync(),
    );
  });
  GameEngine game() =>
      GameEngine(data, textLayout: FlutterSystemFontLayout())
        ..restore(GameData.decodeObject(jsonEncode(initial)));

  // 人工核对ROM：柳35级18种，小梅35级30种，萍芷33级16种。
  for (final sample in [
    (1, '柳清风', 35, 18),
    (2, '慕容小梅', 35, 30),
    (3, '袁萍芷', 33, 16),
  ]) {
    test('${sample.$2}逐级升到60级不遗忘法术', () {
      final actor = GameActor.load(data, 1, sample.$1)!;
      var previous = actor.magics(data);
      for (var level = actor.level + 1; level <= 60; level++) {
        actor.levelUp(data, level);
        final current = actor.magics(data);
        expect(current, containsAll(previous), reason: '${sample.$2}的$level级');
        if (level >= sample.$3) expect(current, hasLength(sample.$4));
        previous = current;
      }
      expect(actor.level, 60);
    });

    test('${sample.$2}从初始等级直接升至60级也学全法术', () {
      final actor = GameActor.load(data, 1, sample.$1)!..levelUp(data, 60);
      expect(actor.magics(data), hasLength(sample.$4));
      expect(actor.learned, sample.$4);
    });
  }

  test('满级无术旧档读回自动修复全队，其他进度与数值保持原值', () {
    final g = game();
    final raw = g.snapshot();
    final actors = [
      for (final id in [1, 2, 3])
        (GameActor.load(data, 1, id)!
              ..level = 60
              ..learned = 0
              ..x = g.player!.x
              ..y = g.player!.y
              ..hp = 1
              ..mp = 0
              ..attack = 1234
              ..exp = 98765)
            .toJson(),
    ];
    raw['players'] = actors;
    raw['money'] = 12345;
    raw['inventory'] = {'9:1': 1234};

    g.restore(GameData.decodeObject(jsonEncode(raw)));

    expect(g.players.map((p) => p.magics(data).length), [18, 30, 16]);
    for (var i = 0; i < actors.length; i++) {
      expect(g.players[i].toJson(), {
        ...actors[i],
        'learned': [18, 30, 16][i],
      });
    }
    expect(g.money, 12345);
    expect(g.inventory, {'9:1': 1234});
    final repaired = jsonEncode(g.snapshot());
    g.restore(GameData.decodeObject(repaired));
    expect(jsonEncode(g.snapshot()), repaired, reason: '再次读档不能重复奖励或改变进度');
  });

  test('旧档缺失法术只补到当前等级，不提前发放后续法术', () {
    final g = game();
    g.player!
      ..level = 10
      ..learned = 0;
    g.restore(GameData.decodeObject(jsonEncode(g.snapshot())));
    expect(g.player!.magics(data), ['3:1', '1:1', '1:8', '3:10', '1:2']);
  });

  test('额外剧情法术及已学法术在升级和读档后保留且不重复', () {
    final g = game();
    final p = g.player!
      ..levelUp(data, 35)
      ..extraMagic.addAll(['1:16', '1:7']);
    p.levelUp(data, 60);
    g.restore(GameData.decodeObject(jsonEncode(g.snapshot())));
    final spells = g.player!.magics(data);
    expect(spells, hasLength(19));
    expect(spells, containsAll(['1:16', '1:7']));
    expect(spells.where((id) => id == '1:7'), hasLength(1));
    expect(g.player!.extraMagic, ['1:16', '1:7']);
  });

  test('已满级再调用升级仍可修复法术，不重算属性或免费恢复', () {
    final p = GameActor.load(data, 1, 1)!
      ..level = 60
      ..learned = 0
      ..hp = 1
      ..mp = 0
      ..attack = 1234;
    final original = p.toJson();
    p.levelUp(data, 60);
    expect(p.toJson(), {...original, 'learned': 18});
  });

  test('真正战斗升过35级后保留神剑御魔，技能快捷键可以选择并排入行动', () {
    final g = game();
    g.player!.levelUp(data, 35);
    g.player!.exp = data.record(12, 2, 1)!.word(4 + 34 * 20 + 14) - 1;
    var battle = GameBattle(
      g,
      monsters: [1],
      background: [2, 2, 2],
      randomFight: true,
    );
    g.battle = battle;
    battle.totalExp = 1;
    battle.forceWin();
    expect(g.player!.level, 36);
    expect(g.player!.magics(data), hasLength(18));
    for (var i = 0; i < 400 && g.battle != null; i++) {
      battle.update();
    }
    expect(
      battle.victoryShown.where((c) => c.kind == 'learn'),
      isEmpty,
      reason: '跨过末尾零值不能重复提示学会全部法术',
    );

    battle = GameBattle(
      g,
      monsters: [1],
      background: [2, 2, 2],
      randomFight: true,
    );
    g.battle = battle;
    battle.quickMagic();
    final menu = g.menus.last;
    expect(menu.ids, hasLength(18));
    expect(g.magicName('1:7'), '神剑御魔');
    menu.selected = menu.ids.indexOf('1:7');
    g.press(GameKey.confirm);
    if (battle.targetKind.isNotEmpty) g.press(GameKey.confirm);
    expect(
      [
        if (battle.current != null) battle.current!,
        ...battle.queue,
      ].any((action) => action.resource == '1:7'),
      isTrue,
    );
  });

  test('初始角色的法术列表保持原有解锁范围', () {
    expect(GameActor.load(data, 1, 1)!.magics(data), ['3:1']);
    expect(GameActor.load(data, 1, 2)!.magics(data), hasLength(4));
    expect(GameActor.load(data, 1, 3)!.magics(data), hasLength(5));
  });
}

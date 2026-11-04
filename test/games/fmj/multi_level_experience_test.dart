import 'package:flutter_test/flutter_test.dart';
import 'package:bbk_flutter/games/fmj/data/game_data.dart';
import 'package:bbk_flutter/games/fmj/engine/game_engine.dart';
import 'package:bbk_flutter/games/fmj/engine/game_actor.dart';
import 'package:bbk_flutter/games/fmj/ui/system_font_layout.dart';
import 'game_engine_test.dart' show loadData;

/// 一次战斗的大额经验必须逐级结算：扣除真实门槛、保留余量、学习法术和发放提示。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GameData data;
  setUpAll(() async => data = await loadData());
  GameEngine game() => GameEngine(data, textLayout: FlutterSystemFontLayout())
    ..screen = 'play'
    ..intro = null
    ..players.addAll([1, 2, 3].map((id) => GameActor.load(data, 1, id)!));
  int needed(int actor, int level) =>
      data.record(12, 2, actor)!.word(4 + (level - 1) * 20 + 14);
  GameBattle win(GameEngine g, int exp) {
    final b = g.battle = GameBattle(
      g,
      monsters: [1],
      background: [2, 2, 2],
      randomFight: true,
    )..totalExp = exp;
    b.forceWin();
    return b;
  }

  test('单场足够经验可从10连升到15，精确保留余量和永久加成', () {
    final g = game(), p = g.player!;
    p.levelUp(data, 10);
    p.exp = 3;
    p.attack += 77;
    p.maxHp += 50;
    final expected = GameActor.fromJson(p.toJson());
    expected.levelUp(data, 15);
    final reward =
        [
          for (var l = 10; l < 15; l++) needed(1, l),
        ].fold<int>(0, (a, b) => a + b) +
        7;
    final b = win(g, reward);
    expect(p.level, 15);
    expect(p.exp, 10);
    expect(p.attack, expected.attack);
    expect(p.maxHp, expected.maxHp);
    final before = p.toJson();
    b.forceWin();
    expect(p.toJson(), before, reason: '同场不能重复发经验');
  });
  test('经验恰好满足多级门槛，升级后剩余为零', () {
    final g = game(), p = g.player!;
    p.levelUp(data, 20);
    p.exp = 0;
    win(
      g,
      [
        for (var l = 20; l < 25; l++) needed(1, l),
      ].fold<int>(0, (a, b) => a + b),
    );
    expect(p.level, 25);
    expect(p.exp, 0);
  });
  test('全队百万经验连续升至60，不截断法术，不影响阵亡队员和已有满级队员', () {
    final g = game();
    g.players[0].levelUp(data, 60);
    g.players[0].exp = 42;
    g.players[1].levelUp(data, 10);
    g.players[1].exp = 0;
    final b = g.battle = GameBattle(
      g,
      monsters: [1],
      background: [2, 2, 2],
      randomFight: true,
    )..totalExp = 1000000;
    g.players[2].hp = 0;
    final dead = g.players[2].toJson(),
        total = [
          for (var l = 10; l < 60; l++) needed(2, l),
        ].fold<int>(0, (a, b) => a + b);
    b.forceWin();
    expect(g.players[0].exp, 42);
    expect(g.players[1].level, 60);
    expect(g.players[1].exp, 1000000 - total);
    final expected = GameActor.load(data, 1, 2)!..levelUp(data, 60);
    expect(g.players[1].learned, expected.learned);
    expect(g.players[1].magics(data), expected.magics(data));
    expect(g.players[2].toJson(), dead);
  });
  test('大环刀全队倍率只乘一次且装备加成不重复，单场多级升级提示逐级保留', () {
    final g = game();
    for (final p in g.players) {
      p.levelUp(data, 10);
      p.exp = 0;
      g.addGoods('7:33');
      g.equip(p, '7:33');
    }
    final threshold = [
      for (var l = 10; l < 14; l++) needed(1, l),
    ].fold<int>(0, (a, b) => a + b);
    final reward = (threshold + 1) ~/ 2;
    final projected = GameActor.fromJson(g.player!.toJson())..levelUp(data, 14);
    final b = win(g, reward);
    expect(b.totalExp, reward * 2);
    expect(g.player!.level, 14);
    expect(g.player!.exp, reward * 2 - threshold);
    final messages = <VictoryCard>[...b.victoryShown];
    for (var i = 0; i < 6000 && g.battle != null; i++) {
      b.update();
      b.key(GameKey.confirm, false);
      for (final c in b.victoryShown) {
        if (!messages.contains(c)) messages.add(c);
      }
    }
    expect(
      messages.where((c) => c.kind == 'level' && c.text.contains('柳清风')),
      hasLength(4),
    );
    expect(g.player!.attack, projected.attack);
  });
}

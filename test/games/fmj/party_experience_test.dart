import 'package:flutter_test/flutter_test.dart';
import 'package:bbk_flutter/games/fmj/data/game_data.dart';
import 'package:bbk_flutter/games/fmj/engine/game_actor.dart';
import 'package:bbk_flutter/games/fmj/engine/game_engine.dart';
import 'package:bbk_flutter/games/fmj/ui/system_font_layout.dart';
import 'game_engine_test.dart' show loadData;

/// 使用真实成长表和胜利结算，防止满级队员截断其他队员的经验奖励。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GameData data;
  setUpAll(() async => data = await loadData());

  GameEngine game(List<int> ids) =>
      GameEngine(data, textLayout: FlutterSystemFontLayout())
        ..screen = 'play'
        ..intro = null
        ..players.addAll(ids.map((id) => GameActor.load(data, 1, id)!));

  GameBattle victory(GameEngine game, {int experience = 20}) {
    final battle = GameBattle(
      game,
      monsters: [1],
      background: [2, 2, 2],
      randomFight: true,
    )..totalExp = experience;
    game.battle = battle;
    battle.forceWin();
    return battle;
  }

  for (final ids in <List<int>>[
    [1, 2],
    [2, 1],
  ]) {
    for (final maxPosition in [0, 1]) {
      test('队列$ids第${maxPosition + 1}位满级，另一人仍获得经验', () {
        final g = game(ids);
        final capped = g.players[maxPosition];
        final growing = g.players[1 - maxPosition];
        capped.levelUp(data, 255);
        capped.exp = 7;
        growing.levelUp(data, 10);
        growing.exp = 0;

        victory(g);

        expect(growing.exp, 20);
        expect(growing.level, 10);
        expect(capped.exp, 7, reason: '满级角色本身不继续累加经验');
      });
    }
  }

  test('前一人满级，后一人仍能升到满级并领取升级提示', () {
    final g = game([1, 2]);
    final capped = g.players.first..levelUp(data, 255);
    final growing = g.players.last;
    final chain = data.record(12, 2, growing.index)!;
    final maxLevel = chain.byte(2);
    growing.levelUp(data, maxLevel - 1);
    growing.exp = chain.word(4 + (growing.level - 1) * 20 + 14) - 10;
    final beforeHp = growing.maxHp;

    final battle = victory(g, experience: 15);
    for (var i = 0; i < 300 && g.battle != null; i++) {
      battle.update();
    }

    expect(growing.level, maxLevel);
    expect(growing.exp, 5);
    expect(growing.maxHp, greaterThanOrEqualTo(beforeHp));
    expect(
      battle.victoryShown.any(
        (card) => card.kind == 'level' && card.text.contains(growing.name),
      ),
      isTrue,
    );
    expect(capped.level, data.record(12, 2, capped.index)!.byte(2));
  });

  test('三人队伍的中间队员满级也不影响后续队员，连续胜利不丢经验', () {
    final g = game([1, 2, 3]);
    for (final p in g.players) {
      p.levelUp(data, 10);
      p.exp = 0;
    }
    g.players[1].levelUp(data, 255);

    final first = victory(g);
    final money = g.money;
    first.forceWin();
    expect(g.players.first.exp, 20, reason: '同一场胜利不能重复发奖励');
    expect(g.money, money);
    victory(g);

    expect(g.players.first.exp, 40);
    expect(g.players[1].exp, 0);
    expect(g.players.last.exp, 40);
  });

  test('全队满级仍结算金钱，阵亡队员沿用原规则不领经验', () {
    final g = game([1, 2]);
    for (final p in g.players) {
      p.levelUp(data, 255);
      p.exp = 3;
    }
    final battle = victory(g);
    expect(g.players.map((p) => p.exp), [3, 3]);
    expect(g.money, battle.totalMoney);
    expect(battle.phase, 'win');

    final next = game([1, 2]);
    next.players.first.levelUp(data, 255);
    next.players.last.exp = 0;
    final dead = GameBattle(
      next,
      monsters: [1],
      background: [2, 2, 2],
      randomFight: true,
    );
    next.battle = dead;
    next.players.last.hp = 0;
    dead.forceWin();
    expect(next.players.last.exp, 0);
  });
}

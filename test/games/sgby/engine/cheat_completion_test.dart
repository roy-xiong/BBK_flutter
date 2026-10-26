import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:bbk_flutter/games/sgby/data/services/game_save_codec.dart';
import 'package:bbk_flutter/games/sgby/domain/models/game_world.dart';
import 'package:bbk_flutter/games/sgby/domain/models/game_options.dart';
import 'package:bbk_flutter/games/sgby/domain/models/game_order.dart';
import 'package:bbk_flutter/games/sgby/domain/models/game_battle.dart';
import 'package:bbk_flutter/games/sgby/domain/use_cases/game_enhancements.dart';
import 'package:bbk_flutter/games/sgby/domain/use_cases/strategy_commands.dart';
import 'package:bbk_flutter/games/sgby/domain/use_cases/computer_strategy.dart';
import 'package:bbk_flutter/games/sgby/domain/use_cases/execute_strategy_order.dart';
import 'package:bbk_flutter/games/sgby/domain/use_cases/special_generals.dart';
import 'package:bbk_flutter/games/sgby/domain/use_cases/battle_engine.dart';
import 'package:bbk_flutter/games/sgby/engine/core/native_game_session.dart';
import 'package:bbk_flutter/games/sgby/engine/core/strategy_turn_flow.dart';
import '../support/game_database.dart';

void main() {
  final database = loadGameDatabase(), codec = GameSaveCodec();
  GameWorld world() {
    final w = database.loadPeriod(1, seed: 1);
    database.beginGame(w, 5);
    return w;
  }

  GameOrder order(
    int command, {
    int person = 64,
    int city = 3,
    int target = 56,
    List<int> fighters = const [],
  }) => GameOrder(
    orderId: command,
    person: person,
    city: city,
    object: target,
    arms: 0,
    food: 5000,
    money: 0,
    consume: 0,
    timeCount: 0,
    fighters: fighters,
  );
  GameBattle battle(GameWorld w) {
    final b = GameBattle(
      mode: 1,
      city: 3,
      sourceCity: 8,
      way: 3,
      mapId: 116,
      playerFood: 5000,
      enemyFood: 5000,
      people: [
        5,
        58,
        60,
        ...List<int?>.filled(7, null),
        64,
        ...List<int?>.filled(9, null),
      ],
    );
    BattleEngine(database).initialize(w, b);
    return b;
  }

  test('新开关默认值、上限严格范围及偏好往返', () {
    final options = GameOptions();
    expect(options.enabled('autoSaveAfterTurn'), isTrue);
    for (final key in [
      'diplomacyProtection',
      'hideSpecialGenerals',
      'enemyArmsLimitEnabled',
    ]) {
      expect(options.enabled(key), isFalse);
    }
    expect(options.enemyArmsLimit, 200000);
    for (final invalid in [null, 799, 200001, 800.0, '800']) {
      expect(options.setEnemyArmsLimit(invalid), isFalse);
      expect(options.enemyArmsLimit, 200000);
    }
    for (final limit in [800, 100000, 200000]) {
      expect(options.setEnemyArmsLimit(limit), isTrue);
      expect(GameOptions(options.toJson()).enemyArmsLimit, limit);
    }
  });
  test('敌将上限替代原算法，降低时裁剪，提高时不补兵', () {
    final w = world(),
        options = GameOptions({
          'enemyArmsLimitEnabled': true,
          'enemyArmsLimit': 800,
        }),
        enhance = GameEnhancements(database, GameOptions());
    final commands = StrategyCommands(database, options: options),
        enemy = w.person(64)!.copyWith(belong: 1);
    expect(commands.maximumArms(enemy, world: w), 800);
    final own = commands.maximumArms(w.person(5)!, world: w);
    expect(own, isNot(800));
    final live = GameEnhancements(database, options);
    w.setPerson(64, enemy.copyWith(arms: 180000));
    live.applyEnemyArmsLimit(w);
    expect(w.person(64)!.arms, 800);
    live.apply(w, 'sgby_enemy_arms_limit_value', parameters: {'value': 200000});
    expect(w.person(64)!.arms, 800);
    expect(commands.maximumArms(w.person(64)!, world: w), 200000);
    expect(enhance.options.enabled('enemyArmsLimitEnabled'), isFalse);
  });
  test('敌军后续AI征兵使用新上限，不增加玩家兵力', () {
    for (final limit in [800, 200000]) {
      var reachesLimit = false;
      for (final seed in [1, 42, 12345]) {
        final w = world();
        w.random.restore(seed);
        final options = GameOptions({
          'enemyArmsLimitEnabled': true,
          'enemyArmsLimit': limit,
        });
        final service = GameEnhancements(database, options);
        final own = [
          for (final person in w.persons)
            if (person.belong == 6) person.arms,
        ];
        service.applyEnemyArmsLimit(w);
        ComputerStrategy(database, options: options)(w, activity: 100);
        service.applyEnemyArmsLimit(w);
        expect([
          for (final person in w.persons)
            if (person.belong == 6) person.arms,
        ], own);
        final enemy = w.persons.where(
          (p) => p.belong > 0 && p.belong != 6 && p.belong != 65535,
        );
        expect(enemy.every((p) => p.arms <= limit), isTrue);
        reachesLimit |= enemy.any((p) => p.arms == limit);
      }
      expect(reachesLimit, isTrue, reason: 'AI应能按$limit的新上限征兵');
    }
  });

  test('20万兵力存档及旧版1存档读取，超出硬上限拒绝', () {
    final w = world();
    w.setPerson(64, w.person(64)!.copyWith(arms: 200000));
    expect(codec.decode(codec.encode(w)).person(64)!.arms, 200000);
    final legacy = codec.encode(world())..['version'] = 1;
    expect(codec.decode(legacy).period, 1);
    final invalid =
        jsonDecode(jsonEncode(codec.encode(w))) as Map<String, dynamic>;
    invalid['world']['persons'][64]['Arms'] = 200001;
    expect(() => codec.decode(invalid), throwsFormatException);
  });
  test('超过65535的总兵力和粮耗不截断，一击必杀完整扣除20万', () {
    final w = world(),
        b = battle(w),
        engine = BattleEngine(database)..oneHitKill = true;
    for (final id in [5, 58, 60]) {
      w.setPerson(id, w.person(id)!.copyWith(arms: 200000));
    }
    w.setPerson(64, w.person(64)!.copyWith(arms: 200000));
    expect(engine.allArms(w, b, 0), 600000);
    engine.consumeFood(w, b);
    expect(b.playerFood, 4742);
    engine.beginCommand(w, b, const BattleCommand(0, 0, target: 10));
    expect(w.person(64)!.arms, 0);
  });
  test('敌军外交保护不消费随机数并正常归队执行者', () {
    for (final command in [6, 15, 16, 17, 18, 19]) {
      final w = world();
      w.setPerson(64, w.person(64)!.copyWith(belong: 1));
      final before = w.person(56)!.toJson(), seed = w.random.state;
      final reports = ExecuteStrategyOrder(
        database,
        dialogs: database.strategyDialogs,
      )(w, order(command), diplomacyProtection: true);
      expect(w.person(56)!.toJson(), before, reason: 'command=$command');
      expect(w.random.state, seed);
      expect(reports, isEmpty);
      expect(w.cityOfPerson(64), 3);
    }
  });
  test('策反保护按当前城市归属判断，关闭时仍执行原规则', () {
    final w = world();
    w.setPerson(64, w.person(64)!.copyWith(belong: 1));
    w.setPerson(56, w.person(56)!.copyWith(belong: 1));
    w.setCity(0, w.city(0)!.copyWith(belong: 6));
    final seed = w.random.state;
    ExecuteStrategyOrder(database, dialogs: database.strategyDialogs)(
      w,
      order(17),
      diplomacyProtection: true,
    );
    expect(w.random.state, seed);
    ExecuteStrategyOrder(database, dialogs: database.strategyDialogs)(
      w,
      order(15),
      diplomacyProtection: false,
    );
    expect(w.random.state, isNot(seed));
  });
  test('特殊君主无继任者时整个世界和开关保持不变', () {
    final w = world(),
        options = GameOptions(),
        service = GameEnhancements(database, GameOptions());
    for (var id = 0; id < w.persons.length; id++) {
      if (id != 185 && w.person(id)!.belong == 186) {
        w.setPerson(id, w.person(id)!.copyWith(belong: 0));
      }
    }
    w.setPerson(185, w.person(185)!.copyWith(belong: 186));
    final before = jsonEncode(w.toJson());
    expect(service.apply(w, 'sgby_hide_special_generals').isSuccess, isFalse);
    expect(jsonEncode(w.toJson()), before);
    expect(options.enabled('hideSpecialGenerals'), isFalse);
  });
  test('隐藏清理出征人员及目标失效命令，空队退还粮草且不计死亡', () {
    final w = world(), service = SpecialGenerals(database);
    w.addOrder(
      order(27, person: 0, city: 0, target: 3, fighters: [185]),
      atEnd: true,
    );
    w.addOrder(
      order(27, person: 1, city: 0, target: 3, fighters: [186, 56]),
      atEnd: true,
    );
    w.addOrder(order(16, person: 57, city: 0, target: 185));
    final food = w.city(0)!.food, record = jsonEncode(w.battleRecord.toJson());
    expect(service.hide(w).isSuccess, isTrue);
    expect(w.orders.length, 1);
    expect(w.orders.single.fighters, [56]);
    expect(w.city(0)!.food, (food + 5000).clamp(0, 65535));
    expect(w.cityOfPerson(57), 0);
    expect(jsonEncode(w.battleRecord.toJson()), record);
    for (final id in [185, 186]) {
      expect(w.cityOfPerson(id), isNull);
      expect(w.person(id)!.arms, 0);
    }
  });
  test('隐藏备份随档位往返，关闭后恢复且不跨局复活', () {
    final w = world(),
        service = SpecialGenerals(database),
        arms = w.person(185)!.arms;
    expect(service.hide(w).isSuccess, isTrue);
    final restored = codec.decode(codec.encode(w));
    expect(restored.hiddenGenerals.length, 2);
    final session = NativeGameSession(database)..replaceWorld(restored);
    expect(restored.hiddenGenerals, isEmpty);
    expect(restored.person(185)!.arms, arms);
    final fresh = world();
    session.replaceWorld(fresh);
    expect(fresh.hiddenGenerals, isEmpty);
    session.dispose();
  });
  test('损坏的特殊武将备份拒绝覆盖活动进度', () {
    final w = world();
    SpecialGenerals(database).hide(w);
    final envelope =
        jsonDecode(jsonEncode(codec.encode(w))) as Map<String, dynamic>;
    envelope['world']['hiddenGenerals'][0]['index'] = 5;
    expect(() => codec.decode(envelope), throwsFormatException);
  });
  test('战斗中隐藏或恢复失败且开关不切换', () {
    final w = world(),
        options = GameOptions(),
        service = GameEnhancements(database, options);
    expect(
      service
          .apply(w, 'sgby_hide_special_generals', battle: battle(w))
          .isSuccess,
      isFalse,
    );
    expect(options.enabled('hideSpecialGenerals'), isFalse);
    expect(w.hiddenGenerals, isEmpty);
  });
  test('回合完成只在安全战略地图排队自动存档，默认第一档先于自动下一回合', () {
    final w = world(),
        options = GameOptions({'autoEndTurn': true}),
        session = NativeGameSession(
          database,
          options: GameOptions({'autoEndTurn': true}),
        );
    session.replaceWorld(w);
    session.resolvingTurn = true;
    session.completeStrategyTurn();
    expect(session.takeRequests(), isEmpty);
    session.resolvingTurn = false;
    session.completeStrategyTurn();
    final requests = session.takeRequests();
    expect(requests.map((r) => r.type), [
      GameRequestType.autoSave,
      GameRequestType.advanceTurn,
    ]);
    expect(requests.first.index, 0);
    expect(identical(requests.first.world, w), isTrue);
    session.options.toggle('autoSaveAfterTurn', enabled: false);
    session.options.toggle('autoEndTurn', enabled: false);
    session.completeStrategyTurn();
    expect(session.takeRequests(), isEmpty);
    expect(options.enabled('autoEndTurn'), isTrue);
    session.dispose();
  });
  test('真实月度流程全部结束才发起自动存档，读档取消旧请求', () {
    final w = world();
    for (var i = 0; i < w.cities.length; i++) {
      w.setCity(i, w.city(i)!.copyWith(belong: i == 37 ? 1 : 6));
    }
    for (var id = 0; id < w.persons.length; id++) {
      if (w.person(id)!.belong > 0 && w.person(id)!.belong != 65535) {
        w.setPerson(id, w.person(id)!.copyWith(belong: 6));
      }
    }
    final session = NativeGameSession(database)..replaceWorld(w);
    StrategyTurnFlow(session).start();
    expect(session.takeRequests(), isEmpty);
    for (var i = 0; i < 5000 && session.resolvingTurn; i++) {
      session.advance(const Duration(milliseconds: 200), speed: 8);
    }
    expect(w.month, 2);
    final requests = session.takeRequests();
    expect(requests.where((r) => r.type == GameRequestType.autoSave).length, 1);
    session.completeStrategyTurn();
    session.replaceWorld(world());
    expect(session.takeRequests(), isEmpty);
    session.dispose();
  });
}

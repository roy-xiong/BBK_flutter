import 'package:flutter_test/flutter_test.dart';
import 'package:bbk_flutter/games/sgby/domain/models/game_options.dart';
import 'package:bbk_flutter/games/sgby/domain/models/game_order.dart';
import 'package:bbk_flutter/games/sgby/domain/use_cases/strategy_commands.dart';
import 'package:bbk_flutter/games/sgby/engine/core/native_game_session.dart';
import 'package:bbk_flutter/games/sgby/engine/core/strategy_turn_flow.dart';
import '../support/game_database.dart';

/// 使用真实下令、战场和月结链验证各场旧俘虏的收尾不被后场覆盖。
void main() {
  for (final scenario in [
    (lostCity: null, sameFaction: false),
    (lostCity: 3, sameFaction: false),
    (lostCity: 4, sameFaction: false),
    (lostCity: 3, sameFaction: true),
  ]) {
    final lostCity = scenario.lostCity;
    test('S04 双战斗逐场收尾，败城=$lostCity，同势力继承=${scenario.sameFaction}', () {
      final database = loadGameDatabase();
      final world = database.loadPeriod(1, seed: 1);
      database.beginGame(world, 5);
      for (var city = 0; city < world.cities.length; city++) {
        for (final id in world.personsInCity(city)) {
          world.removePerson(city, id);
        }
        world.setCity(
          city,
          world
              .city(city)!
              .copyWith(
                belong: 6,
                state: 0,
                food: 20000,
                money: 20000,
                mothballArms: 0,
                satrapId: 0,
              ),
        );
      }
      for (var id = 0; id < world.persons.length; id++) {
        world.setPerson(
          id,
          world
              .person(id)!
              .copyWith(belong: 0, oldBelong: 0, arms: 0, thew: 100),
        );
      }
      world.setPerson(5, world.person(5)!.copyWith(belong: 6));
      world.addPerson(8, 5);

      // 每个被攻城均有在任守将，确保进入真实战场而非无人城直接占领。
      for (final entry in [
        (3, 1, 64, 70),
        (4, scenario.sameFaction ? 1 : 2, scenario.sameFaction ? 0 : 65, 71),
      ]) {
        final (city, belong, defender, captive) = entry;
        world.setCity(city, world.city(city)!.copyWith(belong: belong));
        world.setPerson(
          defender,
          world
              .person(defender)!
              .copyWith(belong: belong, arms: 10, force: 30, iq: 30, thew: 100),
        );
        world.addPerson(city, defender);
        world.setPerson(
          captive,
          world.person(captive)!.copyWith(belong: 65535, oldBelong: 4, arms: 0),
        );
        world.addPerson(city, captive);
      }
      // 保留第三敌城，避免第二场胜利后统一结局清除session.world。
      world.setCity(37, world.city(37)!.copyWith(belong: 3));
      for (final id in [56, 58]) {
        world.setPerson(
          id,
          world
              .person(id)!
              .copyWith(belong: 6, arms: 20000, force: 100, iq: 100, thew: 100),
        );
        world.addPerson(8, id);
      }
      final commands = StrategyCommands(database);
      expect(
        commands
            .expedition(world, 8, 3, [56], 5000, attackAnyCity: true)
            .success,
        isTrue,
      );
      expect(
        commands
            .expedition(world, 8, 4, [58], 5000, attackAnyCity: true)
            .success,
        isTrue,
      );

      final options = GameOptions({
        'worldActivity': 0,
        'battleLoserOutcome': 'death',
        'autoBattle': true,
        'oneHitKill': true,
        'invincible': true,
        'animationsDisabled': true,
        'autoSaveAfterTurn': false,
      });
      final session = NativeGameSession(database, options: options)
        ..replaceWorld(world);
      final enteredCities = <int>{};
      StrategyTurnFlow(session).start();
      var ticks = 0;
      while (session.resolvingTurn && ticks++ < 30000) {
        session.advance(const Duration(milliseconds: 200), speed: 8);
        final battle = session.activeBattle;
        if (battle != null && battle.entered) {
          if (enteredCities.add(battle.city) && battle.city == 4) {
            // 第一场的收尾必须在第二场进入前完成，不能延迟到月结。
            expect(world.cityOfPerson(70), lostCity == 3 ? 3 : isNull);
          }
          // 混合胜负用确定性结果注入验证流程收尾；null场景仍由真实自动战斗决胜。
          if (battle.city == lostCity) battle.result = 2;
        }
      }
      expect(session.resolvingTurn, isFalse);
      expect(enteredCities, containsAll([3, 4]));
      expect(
        world.city(3)!.belong,
        scenario.sameFaction
            ? 65
            : lostCity == 3
            ? 1
            : 6,
      );
      if (scenario.sameFaction) {
        // 第二城君主0战死后，守住第一城的64继承；改归属并不代表第一城破城。
        expect(world.person(64)!.belong, 65);
        expect(world.battleRecord.deadPeople, contains(0));
      }
      expect(world.city(4)!.belong, lostCity == 4 ? 2 : 6);
      expect(world.cityOfPerson(70), lostCity == 3 ? 3 : isNull);
      expect(world.cityOfPerson(71), lostCity == 4 ? 4 : isNull);
      session.dispose();
    });
  }
  test('S04 同城连续三次易主，各场旧俘虏在下一场前完成收尾', () {
    final database = loadGameDatabase();
    final world = database.loadPeriod(1, seed: 1);
    database.beginGame(world, 5);
    for (var city = 0; city < world.cities.length; city++) {
      for (final id in world.personsInCity(city)) {
        world.removePerson(city, id);
      }
      world.setCity(
        city,
        world
            .city(city)!
            .copyWith(
              belong: 6,
              state: 0,
              food: 20000,
              money: 20000,
              mothballArms: 0,
              satrapId: 0,
            ),
      );
    }
    for (var id = 0; id < world.persons.length; id++) {
      world.setPerson(
        id,
        world.person(id)!.copyWith(belong: 0, oldBelong: 0, arms: 0, thew: 100),
      );
    }
    world.setCity(3, world.city(3)!.copyWith(belong: 1));
    world.setCity(37, world.city(37)!.copyWith(belong: 2));
    for (final entry in [
      (5, 8, 6),
      (56, 8, 6),
      (58, 8, 6),
      (64, 3, 1),
      (65, 37, 2),
    ]) {
      final (id, city, belong) = entry;
      world.setPerson(
        id,
        world
            .person(id)!
            .copyWith(belong: belong, arms: 20000, force: 100, iq: 100),
      );
      world.addPerson(city, id);
    }
    world.setPerson(
      70,
      world.person(70)!.copyWith(belong: 65535, oldBelong: 4),
    );
    world.addPerson(3, 70);
    final commands = StrategyCommands(database);
    expect(
      commands.expedition(world, 8, 3, [56], 5000, attackAnyCity: true).success,
      isTrue,
    );
    // 模拟电脑已合法提交的进攻命令，队列位于两次玩家进攻之间。
    expect(
      world.addFightOrder(
        const GameOrder(
          orderId: 27,
          person: 0,
          city: 37,
          object: 3,
          arms: 0,
          food: 5000,
          money: 0,
          consume: 0,
          timeCount: 0,
        ),
        [65],
      ),
      isTrue,
    );
    world.removePerson(37, 65);
    expect(
      commands.expedition(world, 8, 3, [58], 5000, attackAnyCity: true).success,
      isTrue,
    );
    final session = NativeGameSession(
      database,
      options: GameOptions({
        'worldActivity': 0,
        'battleLoserOutcome': 'death',
        'autoBattle': true,
        'animationsDisabled': true,
        'autoSaveAfterTurn': false,
      }),
    )..replaceWorld(world);
    addTearDown(session.dispose);
    final entered = <Object>{}, modes = <int>[];
    StrategyTurnFlow(session).start();
    for (var tick = 0; session.resolvingTurn && tick < 30000; tick++) {
      session.advance(const Duration(milliseconds: 200), speed: 8);
      final battle = session.activeBattle;
      if (battle == null || !battle.entered || !entered.add(battle)) continue;
      modes.add(battle.mode);
      if (modes.length == 2) {
        expect(world.cityOfPerson(70), isNull);
        // 第二场新出现的俘虏未参与首场，也不属于第二场准备时的旧俘虏。
        // 第三场准备时才会成为它的旧俘虏，不能被之前的收尾误处置。
        world.setPerson(
          71,
          world.person(71)!.copyWith(belong: 65535, oldBelong: 4),
        );
        world.addPerson(3, 71);
      } else if (modes.length == 3) {
        expect(world.cityOfPerson(71), 3);
      }
      // 本用例只验证逐场收尾与归属顺序，确定性注入双方进攻均获胜的结果。
      battle.result = battle.mode == 0 ? 2 : 1;
    }
    expect(session.resolvingTurn, isFalse);
    expect(modes, [1, 0, 1]);
    expect(world.city(3)!.belong, 6);
    expect(world.cityOfPerson(70), isNull);
    expect(world.cityOfPerson(71), isNull);
    expect(world.battleRecord.deadPeople, containsAll([70, 71]));
  });
}

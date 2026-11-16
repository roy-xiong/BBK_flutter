import 'package:flutter_test/flutter_test.dart';
import 'package:bbk_flutter/games/sgby/data/services/game_save_codec.dart';
import 'package:bbk_flutter/games/sgby/domain/models/game_order.dart';
import 'package:bbk_flutter/games/sgby/domain/models/game_world.dart';
import 'package:bbk_flutter/games/sgby/domain/use_cases/execute_strategy_order.dart';

import '../support/game_database.dart';

/// 覆盖实际抓到的“势力劝降后，在途武将变为城外在野”及排队外交目标易主。
void main() {
  final database = loadGameDatabase();

  /// 构造空队列，避免剧本原有归属、人员位置和命令干扰外交分支。
  GameWorld fresh() {
    final base = database.loadPeriod(1, seed: 3);
    return GameWorld(
      period: base.period,
      year: base.year,
      month: base.month,
      persons: [
        for (final person in base.persons)
          person.copyWith(belong: 65535, arms: 0),
      ],
      cities: [
        for (final city in base.cities)
          city.copyWith(
            belong: 6,
            satrapId: 0,
            personQueue: 0,
            persons: 0,
            money: 1000,
            food: 1000,
            mothballArms: 1000,
          ),
      ],
      tools: base.tools,
      personQueue: List<int>.filled(base.persons.length, 0),
      goodsQueue: base.goodsQueue,
      randomSeed: 3,
    )..playerRulerIndex = 11;
  }

  /// 正常命令的人物是武将编号；出征命令由 addFightOrder 分配出征槽编号。
  GameOrder order(int command, int person, int city, int target) => GameOrder(
    orderId: command,
    person: person,
    city: city,
    object: target,
    arms: 0,
    food: 0,
    money: 0,
    consume: 0,
    timeCount: 0,
  );

  for (final command in [15, 16, 17, 19]) {
    test('排队外交$command的目标已加入己方时跳过并归还执行者', () {
      final world = fresh();
      world.setPerson(56, world.person(56)!.copyWith(belong: 6, iq: 200));
      world.setPerson(64, world.person(64)!.copyWith(belong: 1, devotion: 0));
      world.setCity(1, world.city(1)!.copyWith(belong: 1, satrapId: 65));
      world.addPerson(1, 64);
      expect(world.addOrder(order(command, 56, 0, 64)), isTrue);
      // 模拟命令先下达、目标随后被其他命令收编，结算不能继续攻击新同僚。
      world.setPerson(64, world.person(64)!.copyWith(belong: 6));
      world.setCity(1, world.city(1)!.copyWith(belong: 6));
      final before = world.person(64)!.toJson();
      final seed = world.random.state;

      ExecuteStrategyOrder(database, dialogs: database.strategyDialogs)(
        world,
        world.orders.single,
        worldActivity: 100,
      );

      expect(world.person(64)!.toJson(), before);
      expect(world.city(1)!.belong, 6);
      expect(world.cityOfPerson(56), 0);
      expect(world.random.state, seed);
    });
  }

  for (final invalidBelong in [0, 65535]) {
    test('外交执行者或目标归属为$invalidBelong时不继续制造新势力', () {
      for (final invalidActor in [false, true]) {
        final world = fresh();
        world.setPerson(
          56,
          world
              .person(56)!
              .copyWith(belong: invalidActor ? invalidBelong : 6, iq: 200),
        );
        world.setPerson(
          64,
          world
              .person(64)!
              .copyWith(belong: invalidActor ? 1 : invalidBelong, devotion: 0),
        );
        world.setCity(1, world.city(1)!.copyWith(belong: 1, satrapId: 65));
        world.addPerson(1, 64);
        final before = world.person(64)!.toJson();
        final seed = world.random.state;

        ExecuteStrategyOrder(database, dialogs: database.strategyDialogs)(
          world,
          order(17, 56, 0, 64),
          worldActivity: 100,
        );

        expect(world.person(64)!.toJson(), before);
        expect(world.city(1)!.belong, 1);
        expect(world.random.state, seed);
      }
    });
  }

  for (final mixedExpedition in [false, true]) {
    test('劝降收编在途武将并清理命令，混合出征=$mixedExpedition', () {
      final world = fresh();
      for (final city in [1, 2]) {
        world.setCity(city, world.city(city)!.copyWith(belong: 91));
      }
      world.setCity(2, world.city(2)!.copyWith(satrapId: 91));
      world.setCity(3, world.city(3)!.copyWith(belong: 12));
      world.setPerson(56, world.person(56)!.copyWith(belong: 6, iq: 200));
      world.setPerson(6, world.person(6)!.copyWith(belong: 6));
      for (final id in [90, 88, 129, 146, 97, 98, 170]) {
        world.setPerson(
          id,
          world.person(id)!.copyWith(belong: 91, arms: 8000, devotion: 80),
        );
      }
      world.setPerson(90, world.person(90)!.copyWith(iq: 0, character: 0));
      world.addPerson(2, 90);
      world.addPerson(2, 88);
      world.setPerson(
        65,
        world.person(65)!.copyWith(belong: 65535, oldBelong: 91),
      );
      world.addPerson(2, 65);
      world.setPerson(66, world.person(66)!.copyWith(belong: 0, oldBelong: 91));
      world.addPerson(2, 66);
      final captive = world.person(65)!.toJson();
      final wild = world.person(66)!.toJson();
      expect(world.addOrder(order(19, 56, 0, 90)), isTrue);
      final surrender = world.orders.single;
      expect(world.addOrder(order(14, 146, 2, 1)), isTrue);
      expect(
        world.addOrder(
          order(13, 129, 2, 1).copyWith(food: 200, money: 100, arms: 300),
        ),
        isTrue,
      );
      expect(world.addOrder(order(3, 6, 0, 0)), isTrue);
      world.setPerson(147, world.person(147)!.copyWith(belong: 12, arms: 9000));
      expect(
        world.addFightOrder(order(27, 0, 2, 3).copyWith(food: 400), [
          97,
          98,
          if (mixedExpedition) 147,
        ]),
        isTrue,
      );
      final expedition = world.orders.last;
      // 携带物资已在下令时扣除；取消命令只能退还一次。
      world.setCity(
        2,
        world.city(2)!.copyWith(food: 400, money: 900, mothballArms: 700),
      );

      // 种子3的两次判定为9、27，满足本场100%、30%的劝降成功条件。
      ExecuteStrategyOrder(database, dialogs: database.strategyDialogs)(
        world,
        surrender,
        worldActivity: 100,
      );

      for (final id in [90, 88, 129, 146, 97, 98, 170]) {
        expect(world.person(id)!.belong, 6, reason: '武将$id应随势力加入');
        expect(world.person(id)!.arms, 8000);
        expect(world.cityOfPerson(id), id == 170 ? 1 : 2);
      }
      expect(world.person(65)!.toJson(), captive);
      expect(world.person(66)!.toJson(), wild);
      expect(world.city(1)!.belong, 6);
      expect(world.city(2)!.belong, 6);
      expect(world.city(2)!.food, mixedExpedition ? 600 : 1000);
      expect(world.city(2)!.money, 1000);
      expect(world.city(2)!.mothballArms, 1000);
      expect(world.cityOfPerson(56), 0);
      expect(world.orders.any((pending) => pending.person == 6), isTrue);
      expect(world.orders.any((pending) => pending.person == 129), isFalse);
      expect(world.orders.any((pending) => pending.person == 146), isFalse);
      final remaining = world.orders.where((pending) => pending.orderId == 27);
      if (mixedExpedition) {
        expect(remaining.single.fighters, [147]);
        expect(remaining.single.queueSlot, expedition.queueSlot);
        expect(remaining.single.food, 400);
        expect(world.cityOfPerson(147), isNull);
      } else {
        expect(remaining, isEmpty);
      }
      final located = <int>[
        for (var city = 0; city < world.cities.length; city++)
          ...world.personsInCity(city),
      ];
      expect(located.length, located.toSet().length);
      // 调用方正常消费当前命令后，修复结果仍满足存档引用和人员队列约束。
      world.removeOrder(surrender);
      final codec = GameSaveCodec();
      expect(codec.decode(codec.encode(world)).person(129)!.belong, 6);
    });
  }
}

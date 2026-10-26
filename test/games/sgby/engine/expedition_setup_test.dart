import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:bbk_flutter/games/sgby/domain/models/game_world.dart';
import 'package:bbk_flutter/games/sgby/domain/use_cases/strategy_commands.dart';
import 'package:bbk_flutter/games/sgby/domain/use_cases/resolve_battle.dart';
import 'package:bbk_flutter/games/sgby/domain/use_cases/battle_engine.dart';
import 'package:bbk_flutter/games/sgby/domain/models/game_order.dart';
import 'package:bbk_flutter/games/sgby/engine/core/native_game_session.dart';
import 'package:bbk_flutter/games/sgby/engine/core/strategy_command_flow.dart';
import '../support/game_database.dart';

({
  NativeGameSession session,
  GameWorld world,
  int city,
  int target,
  List<int> people,
})
fixture() {
  final database = loadGameDatabase(), world = database.loadPeriod(1, seed: 1);
  database.beginGame(world, 5);
  final city = world.citiesOf(5).first;
  world.setCity(city, world.city(city)!.copyWith(food: 12345, money: 5000));
  final people = world.personsInCity(city, belong: 6);
  for (final id in people) {
    world.setPerson(id, world.person(id)!.copyWith(arms: 100));
  }
  final target = world.cities.indexWhere((c) => c.belong != 6);
  final session = NativeGameSession(database)..replaceWorld(world);
  session.options.toggle('attackAnyCity', enabled: true);
  return (
    session: session,
    world: world,
    city: city,
    target: target,
    people: people,
  );
}

void selectTarget(NativeGameSession session, int id) {
  final at = session.resources.constant(6);
  session.world!
    ..cursorX = at[id * 2]
    ..cursorY = at[id * 2 + 1];
  session.input(NativeInput.confirm);
}

void main() {
  for (final quick in [false]) {
    test('${quick ? '快捷' : '普通'}出征必须先选将、再选粮草、最后确认城市，携粮不再固定5000', () {
      final f = fixture();
      try {
        final before = jsonEncode(f.world.toJson());
        StrategyCommandFlow(
          f.session,
          f.city,
          27,
        ).start(quickExpedition: quick);
        expect(f.session.scene, NativeScene.menu);
        expect(jsonEncode(f.world.toJson()), before);
        f.session.input(NativeInput.confirm);
        f.session.input(NativeInput.cancel);
        expect(f.session.scene, NativeScene.number);
        expect(f.world.orders, isEmpty);
        f.session.input(NativeInput.confirm);
        expect(f.session.scene, NativeScene.targetCity);
        selectTarget(f.session, f.target);
        final order = f.world.orders.single;
        expect(order.food, 12345);
        expect(order.fighters, [f.people.first]);
        expect(f.world.city(f.city)!.food, 0);
      } finally {
        f.session.dispose();
      }
    });
  }
  for (final stage in ['generals', 'food', 'target']) {
    test('取消 $stage 阶段不扣钱粮、不移除武将、不产生出征命令', () {
      final f = fixture();
      try {
        final before = jsonEncode(f.world.toJson());
        StrategyCommandFlow(
          f.session,
          f.city,
          27,
        ).start(quickExpedition: false);
        if (stage != 'generals') {
          f.session.input(NativeInput.confirm);
          f.session.input(NativeInput.cancel);
        }
        if (stage == 'target') f.session.input(NativeInput.confirm);
        f.session.input(NativeInput.cancel);
        expect(f.session.scene, NativeScene.strategy);
        // 选择目标时地图光标可以改变，世界资源和命令队列必须完全保持原值。
        expect(jsonEncode(f.world.toJson()), before);
      } finally {
        f.session.dispose();
      }
    });
  }
  test('零兵力武将最终提交被拒绝，混合队伍也不能绕过且资源不变', () {
    final f = fixture();
    try {
      f.world.setPerson(
        f.people.first,
        f.world.person(f.people.first)!.copyWith(arms: 0),
      );
      final before = jsonEncode(f.world.toJson());
      final commands = StrategyCommands(f.session.resources);
      for (final fighters in [
        [f.people.first],
        [f.people.first, f.people[1]],
      ]) {
        final result = commands.expedition(
          f.world,
          f.city,
          f.target,
          fighters,
          100,
          attackAnyCity: true,
        );
        expect(result.success, isFalse);
        expect(result.message, contains('兵力'));
        expect(jsonEncode(f.world.toJson()), before);
      }
    } finally {
      f.session.dispose();
    }
  });
  test('零兵力人员从选将候选剔除，第一名可出征人员必须有兵', () {
    final f = fixture();
    try {
      f.world.setPerson(
        f.people.first,
        f.world.person(f.people.first)!.copyWith(arms: 0),
      );
      StrategyCommandFlow(f.session, f.city, 27).start(quickExpedition: false);
      f.session.input(NativeInput.confirm);
      if (f.session.scene == NativeScene.menu) {
        f.session.input(NativeInput.cancel);
      }
      f.session.input(NativeInput.confirm);
      selectTarget(f.session, f.target);
      expect(f.world.orders.single.fighters, [f.people[1]]);
    } finally {
      f.session.dispose();
    }
  });
  test('全城兵力为零时快捷出征拒绝进入选将，粮草不变', () {
    final f = fixture();
    try {
      for (final id in f.people) {
        f.world.setPerson(id, f.world.person(id)!.copyWith(arms: 0));
      }
      StrategyCommandFlow(f.session, f.city, 27).start(quickExpedition: true);
      expect(f.session.scene, NativeScene.report);
      expect(f.world.orders, isEmpty);
      expect(f.world.city(f.city)!.food, 12345);
    } finally {
      f.session.dispose();
    }
  });
  test('行军途中兵力归零不进入战场，全队归零归队并退粮', () {
    for (final allZero in [false, true]) {
      final f = fixture();
      try {
        final ids = f.people.take(2).toList();
        final result = StrategyCommands(
          f.session.resources,
        ).expedition(f.world, f.city, f.target, ids, 100, attackAnyCity: true);
        expect(result.success, isTrue);
        for (final id in allZero ? ids : [ids.first]) {
          f.world.setPerson(id, f.world.person(id)!.copyWith(arms: 0));
        }
        final prepared = ResolveBattle(
          f.session.resources,
        ).prepare(f.world, f.world.orders.single);
        expect(f.world.cityOfPerson(ids.first), f.city);
        if (allZero) {
          expect(prepared.battle, isNull);
          expect(prepared.reports, isEmpty);
          expect(f.world.city(f.city)!.food, 12345);
        } else {
          expect(
            prepared.battle!.people.whereType<int>(),
            isNot(contains(ids.first)),
          );
          expect(prepared.battle!.people.first, ids[1]);
        }
      } finally {
        f.session.dispose();
      }
    }
  });
  test('守城候选与最终指定守将均排除零兵力人员', () {
    final f = fixture();
    try {
      final zero = f.people.first, defender = f.people[1];
      f.world.setPerson(zero, f.world.person(zero)!.copyWith(arms: 0));
      final attacker = f.world.persons.indexWhere(
        (p) => p.belong > 0 && p.belong != 6 && p.belong != 65535 && p.arms > 0,
      );
      expect(attacker, greaterThanOrEqualTo(0));
      final order = GameOrder(
        orderId: 27,
        person: 0,
        city: f.target,
        object: f.city,
        arms: 0,
        food: 100,
        money: 0,
        consume: 0,
        timeCount: 0,
        fighters: [attacker],
      );
      final resolver = ResolveBattle(f.session.resources);
      expect(resolver.prepare(f.world, order).defenders, isNot(contains(zero)));
      final battle = resolver
          .prepare(f.world, order, selectedDefenders: [zero, defender])
          .battle!;
      expect(battle.people.whereType<int>(), isNot(contains(zero)));
      expect(battle.people.first, defender);
    } finally {
      f.session.dispose();
    }
  });
  test('战场初始化的最后防线使零兵力槽不可行动且不生成死亡报告', () {
    final f = fixture();
    try {
      final ids = f.people.take(2).toList();
      StrategyCommands(
        f.session.resources,
      ).expedition(f.world, f.city, f.target, ids, 100, attackAnyCity: true);
      final battle = ResolveBattle(
        f.session.resources,
      ).prepare(f.world, f.world.orders.single).battle!;
      final id = battle.people[1]!;
      f.world.setPerson(id, f.world.person(id)!.copyWith(arms: 0));
      final reports = BattleEngine(
        f.session.resources,
      ).initialize(f.world, battle);
      expect(battle.units[1].state, 8);
      expect(battle.units[1].move, 0);
      expect(reports.where((report) => report.person == id), isEmpty);
    } finally {
      f.session.dispose();
    }
  });
}

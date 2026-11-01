import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bbk_flutter/games/sgby/data/repositories/game_save_repository.dart';
import 'package:bbk_flutter/games/sgby/data/services/game_save_codec.dart';
import 'package:bbk_flutter/games/sgby/domain/models/game_options.dart';
import 'package:bbk_flutter/games/sgby/domain/models/game_world.dart';
import 'package:bbk_flutter/games/sgby/domain/use_cases/resolve_battle.dart';
import 'package:bbk_flutter/games/sgby/domain/use_cases/strategy_commands.dart';
import 'package:bbk_flutter/games/sgby/engine/core/native_game_session.dart';
import 'package:bbk_flutter/games/sgby/engine/core/strategy_turn_flow.dart';
import '../support/game_database.dart';

void main() {
  final database = loadGameDatabase();
  GameWorld expedition() {
    final world = database.loadPeriod(1, seed: 1);
    database.beginGame(world, 5);
    final commands = StrategyCommands(database);
    for (final source in world.citiesOf(5)) {
      final people = world
          .personsInCity(source, belong: 6)
          .where((id) => (world.person(id)?.arms ?? 0) > 0)
          .toList();
      if (people.isEmpty) continue;
      for (final target in commands.neighbours(source)) {
        if (world.city(target)?.belong == 6) continue;
        if (commands.expedition(world, source, target, [
          people.first,
        ], 100).success) {
          return world;
        }
      }
    }
    throw StateError('真实资源未找到有效出征路线');
  }

  test('S06 无效出征目标回退有效备份，下次保存保留有效备份', () async {
    final dir = await Directory.systemTemp.createTemp('sgby-save-regression-');
    final repository = GameSaveRepository(directoryProvider: () async => dir);
    try {
      final world = expedition(), original = world.orders.single;
      await repository.save(0, world);
      await repository.save(0, world);
      final main = File('${dir.path}/games/sgby/slot_0.json');
      final broken = jsonDecode(await main.readAsString());
      broken['world']['orders'][0]['Object'] = 65535;
      await main.writeAsString(jsonEncode(broken));
      final restored = (await repository.load(0))!;
      expect(restored.orders.single.object, original.object);
      await repository.save(0, restored);
      final backup = GameSaveCodec().decode(
        jsonDecode(await File('${main.path}.backup').readAsString()),
      );
      expect(backup.orders.single.object, original.object);
    } finally {
      await repository.flush();
      await dir.delete(recursive: true);
    }
  });

  for (final mutation in [
    'badTarget',
    'emptyFighters',
    'duplicateFighter',
    'fighterInCity',
    'reusedFighter',
  ]) {
    test('S06 Codec拒绝语义无效的出征订单 $mutation', () {
      final world = expedition(), order = world.orders.single;
      switch (mutation) {
        case 'badTarget':
          world.replaceOrders([order.copyWith(object: 65535)]);
        case 'emptyFighters':
          world.replaceOrders([order.copyWith(fighters: [])]);
        case 'duplicateFighter':
          world.replaceOrders([
            order.copyWith(
              fighters: [order.fighters.first, order.fighters.first],
            ),
          ]);
        case 'fighterInCity':
          world.addPerson(order.city, order.fighters.first);
        case 'reusedFighter':
          world.replaceOrders([order, order.copyWith(person: 1, queueSlot: 1)]);
      }
      final codec = GameSaveCodec();
      final json = jsonDecode(jsonEncode(codec.encode(world)));
      expect(() => codec.decode(json), throwsFormatException);
    });
  }

  test('S06 运行时坏目标准备阶段归还出征将和携粮且不重复归队', () {
    final world = expedition(), original = world.orders.single;
    final broken = original.copyWith(object: 65535);
    final food = world.city(original.city)!.food;
    final result = ResolveBattle(database).prepare(world, broken);
    expect(result.battle, isNull);
    expect(world.cityOfPerson(original.fighters.first), original.city);
    expect(world.city(original.city)!.food, food + original.food);
    expect(world.battleRecord.killedGenerals, 0);
    ResolveBattle(database).prepare(world, broken);
    expect(world.city(original.city)!.food, food + original.food);
    expect(
      world
          .personsInCity(original.city)
          .where((id) => id == original.fighters.first),
      hasLength(1),
    );
  });

  test('S06 真实月结取消坏出征订单后武将不会丢失', () {
    final world = expedition(), original = world.orders.single;
    world.replaceOrders([original.copyWith(object: 65535)]);
    final session = NativeGameSession(
      database,
      options: GameOptions({'worldActivity': 0, 'autoSaveAfterTurn': false}),
    )..replaceWorld(world);
    addTearDown(session.dispose);
    StrategyTurnFlow(session).start();
    for (var i = 0; session.resolvingTurn && i < 5000; i++) {
      session.advance(const Duration(milliseconds: 200), speed: 8);
    }
    expect(session.resolvingTurn, isFalse);
    expect(world.orders, isEmpty);
    expect(world.cityOfPerson(original.fighters.first), original.city);
  });
}

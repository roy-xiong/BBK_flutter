import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:bbk_flutter/games/sgby/domain/models/game_battle.dart';
import 'package:bbk_flutter/games/sgby/domain/models/game_options.dart';
import 'package:bbk_flutter/games/sgby/domain/use_cases/special_generals.dart';
import 'package:bbk_flutter/games/sgby/domain/use_cases/game_enhancements.dart';
import 'package:bbk_flutter/games/sgby/domain/use_cases/strategy_commands.dart';
import 'package:bbk_flutter/games/sgby/engine/core/battle_flow.dart';
import 'package:bbk_flutter/games/sgby/engine/core/native_game_session.dart';
import 'package:bbk_flutter/games/sgby/engine/core/strategy_command_flow.dart';
import 'package:bbk_flutter/games/sgby/engine/resources/baye_database.dart';
import '../support/game_database.dart';

/// 审计缺陷的真实领域、输入与流程回归，不通过测试专用生产入口改变行为。
void main() {
  final database = loadGameDatabase();
  fresh() {
    final world = database.loadPeriod(1, seed: 1);
    database.beginGame(world, 5);
    world.setCity(0, world.city(0)!.copyWith(belong: 6, money: 1000));
    world.setPerson(56, world.person(56)!.copyWith(belong: 6, thew: 100));
    world.addPerson(0, 56);
    return world;
  }

  test('S01 结局报告被存档中断后退出和读档均清理旧报告回调', () {
    for (final exitFirst in [true, false]) {
      final lost = fresh(), replacement = fresh();
      final session = NativeGameSession(database)..replaceWorld(lost);
      addTearDown(session.dispose);
      for (final city in lost.citiesOf(5)) {
        lost.setCity(city, lost.city(city)!.copyWith(belong: 1));
      }
      expect(session.checkGameOver(), isTrue);
      session.openSaveMenu();
      expect(session.scene, NativeScene.saveSlots);
      session.input(NativeInput.cancel);
      if (exitFirst) {
        session.input(NativeInput.cancel);
        session.input(NativeInput.down);
        session.input(NativeInput.down);
        session.input(NativeInput.confirm);
        session.input(NativeInput.confirm);
        expect(session.world, isNull);
      }
      session.replaceWorld(replacement);
      session.showReport('新的普通操作提示');
      session.closeReport();
      session.advance(const Duration(seconds: 10));
      expect(session.world, same(replacement));
      expect(session.scene, NativeScene.strategy);
    }
  });

  test('S02 行动菜单查询战况不会拆开位移事务', () {
    final world = fresh();
    for (final id in [5, 0]) {
      world.setPerson(id, world.person(id)!.copyWith(arms: 5000));
    }
    final battle = GameBattle(
      mode: 1,
      city: 8,
      sourceCity: 3,
      way: 0,
      mapId: 113,
      playerFood: 5000,
      enemyFood: 5000,
      people: [
        5,
        ...List<int?>.filled(9, null),
        0,
        ...List<int?>.filled(9, null),
      ],
    );
    final session = NativeGameSession(database, options: GameOptions())
      ..replaceWorld(world);
    addTearDown(session.dispose);
    final flow = BattleFlow(session, battle, completed: () {})..start();
    for (var i = 0; i < 40; i++) {
      if (session.scene == NativeScene.report) session.closeReport();
      session.advance(const Duration(milliseconds: 100));
    }
    battle
      ..width = 15
      ..height = 8
      ..viewX = 0
      ..viewY = 0
      ..cityX = 13
      ..cityY = 6
      ..result = 0
      ..focusX = 2
      ..focusY = 2
      ..map = Uint8List.fromList(List.filled(120, 1));
    for (var i = 0; i < 20; i++) {
      battle.units[i]
        ..state = i == 0 || i == 10 ? 0 : 8
        ..hp = 90
        ..mp = 90
        ..active = 0;
    }
    battle.units[0]
      ..x = 2
      ..y = 2;
    battle.units[10]
      ..x = 12
      ..y = 6;
    flow.draw();
    session.input(NativeInput.confirm);
    flow.tap(72, 40);
    expect(session.scene, NativeScene.menu);
    expect(battle.units[0].x, 4);
    // 即使由快捷键直接转发，也只能在普通战场打开战况。
    session.onBattleInput?.call(NativeInput.search);
    expect(session.scene, NativeScene.menu);
    session.input(NativeInput.cancel);
    expect(battle.units[0].x, 2);
    expect(battle.units[0].active, 0);
    expect(session.scene, NativeScene.battle);
    session.input(NativeInput.search);
    expect(session.scene, NativeScene.battleSituation);
    session.input(NativeInput.confirm);
    expect(session.scene, NativeScene.battle);
  });

  for (final dismiss in [NativeInput.confirm, NativeInput.cancel]) {
    test('S03 侦察成功展示所选敌城情报并可用$dismiss返回地图', () {
      final world = fresh();
      for (final id in world.personsInCity(0).toList()) {
        world.removePerson(0, id);
      }
      world.addPerson(0, 56);
      world.setCity(3, world.city(3)!.copyWith(belong: 1));
      final session = NativeGameSession(database)..replaceWorld(world);
      addTearDown(session.dispose);
      StrategyCommandFlow(session, 0, 23).start();
      session.input(NativeInput.confirm);
      final positions = database.constant(6);
      world.cursorX = positions[6];
      world.cursorY = positions[7];
      session.input(NativeInput.confirm);
      expect(session.scene, NativeScene.cityInfo);
      expect(world.city(0)!.money, 980);
      expect(world.person(56)!.thew, 90);
      expect(world.orders.single.object, 3);
      expect(world.cityOfPerson(56), isNull);
      session.input(dismiss);
      expect(session.scene, NativeScene.strategy);
    });
  }

  test('S05 输送途中拒绝隐藏，订单和两城物资保持原子性', () {
    final world = fresh(), special = SpecialGenerals(database);
    final ids = special.indexes(world),
        destination = StrategyCommands(database).neighbours(0).first;
    final id = ids.first;
    for (final s in ids) {
      world.setPerson(s, world.person(s)!.copyWith(belong: 0, oldBelong: 0));
    }
    for (final city in [0, destination]) {
      world.setCity(
        city,
        world
            .city(city)!
            .copyWith(belong: 6, money: 1000, food: 1000, mothballArms: 1000),
      );
    }
    world.setPerson(id, world.person(id)!.copyWith(belong: 6, thew: 100));
    world.addPerson(0, id);
    expect(
      StrategyCommands(database)
          .make(
            world,
            StrategyAction(
              command: 13,
              city: 0,
              person: id,
              target: destination,
              money: 100,
              food: 200,
              arms: 300,
            ),
          )
          .success,
      isTrue,
    );
    final before = jsonEncode(world.toJson());
    expect(special.hide(world).isSuccess, isFalse);
    expect(jsonEncode(world.toJson()), before);
    expect(world.orders.single.person, id);
    expect(world.hiddenGenerals, isEmpty);
    final options = GameOptions();
    final settings = jsonEncode(options.toJson());
    final enhancements = GameEnhancements(database, options);
    expect(
      enhancements.apply(world, 'sgby_hide_special_generals').isSuccess,
      isFalse,
    );
    expect(jsonEncode(options.toJson()), settings);
    expect(jsonEncode(world.toJson()), before);
  });

  for (final fix in [0, 1]) {
    test('C01 fixAlienateComsumeThew=$fix决定扣体力对象，始终校验执行者', () {
      final rules =
          jsonDecode(
                File('assets/sgby/game/refined_rules.json').readAsStringSync(),
              )
              as Map<String, dynamic>;
      rules['config']['fixAlienateComsumeThew'] = fix;
      final db = BayeDatabase(
        archive: database.archive,
        codec: database.codec,
        font: database.font,
        refinedRules: rules,
      );
      final world = fresh();
      world.setPerson(64, world.person(64)!.copyWith(belong: 1, thew: 100));
      final commands = StrategyCommands(db);
      world.setPerson(56, world.person(56)!.copyWith(thew: 19));
      expect(
        commands
            .make(
              world,
              const StrategyAction(
                command: 15,
                city: 0,
                person: 56,
                target: 64,
              ),
            )
            .success,
        isFalse,
      );
      world.setPerson(56, world.person(56)!.copyWith(thew: 100));
      expect(
        commands
            .make(
              world,
              const StrategyAction(
                command: 15,
                city: 0,
                person: 56,
                target: 64,
              ),
            )
            .success,
        isTrue,
      );
      expect(world.person(56)!.thew, fix == 0 ? 100 : 80);
      expect(world.person(64)!.thew, fix == 0 ? 80 : 100);
    });
  }

  for (final thew in [0, 1, 7, 8, 100]) {
    test('C02 移动体力$thew按移动门槛准入，运输扣减最低为0', () {
      final world = fresh(), commands = StrategyCommands(database);
      final destination = commands.neighbours(0).first;
      world.setCity(destination, world.city(destination)!.copyWith(belong: 6));
      world.setPerson(56, world.person(56)!.copyWith(thew: thew));
      expect(
        commands
            .make(
              world,
              StrategyAction(
                command: 14,
                city: 0,
                person: 56,
                target: destination,
              ),
            )
            .success,
        isTrue,
      );
      expect(
        world.person(56)!.thew,
        (thew - commands.thewCost(13)).clamp(0, 255),
      );
    });
  }
}

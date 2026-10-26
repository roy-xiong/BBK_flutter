import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:bbk_flutter/games/sgby/data/services/game_save_codec.dart';
import 'package:bbk_flutter/games/sgby/domain/models/game_battle.dart';
import 'package:bbk_flutter/games/sgby/domain/models/game_options.dart';
import 'package:bbk_flutter/games/sgby/domain/models/game_order.dart';
import 'package:bbk_flutter/games/sgby/domain/models/game_world.dart';
import 'package:bbk_flutter/games/sgby/domain/use_cases/resolve_battle.dart';
import 'package:bbk_flutter/games/sgby/engine/core/battle_flow.dart';
import 'package:bbk_flutter/games/sgby/engine/core/native_game_session.dart';
import '../support/game_database.dart';

/// 从原内核战场初始化样本进入真实流程，然后固定两个单位以隔离自动选点阶段。
({
  NativeGameSession session,
  GameBattle battle,
  GameWorld world,
  BattleFlow flow,
})
_start() {
  final database = loadGameDatabase();
  final sample =
      (jsonDecode(
                    File(
                      'test/games/sgby/fixtures/reference_battle_init.json',
                    ).readAsStringSync(),
                  )
                  as List)
              .first
          as Map;
  final codec = GameSaveCodec(), base = database.loadPeriod(1, seed: 1);
  database.beginGame(base, 5);
  final envelope = codec.encode(base);
  final saved = Map<String, dynamic>.from(envelope['world']! as Map)
    ..addAll(Map<String, dynamic>.from(sample['before'] as Map));
  final world = codec.decode({...envelope, 'world': saved});
  final battle = ResolveBattle(database)
      .prepare(
        world,
        GameOrder(
          orderId: 27,
          person: 0,
          city: 8,
          object: 3,
          arms: 0,
          food: 5000,
          money: 0,
          consume: 0,
          timeCount: 0,
          fighters: [5, 58, 60],
        ),
      )
      .battle!;
  final session = NativeGameSession(
    database,
    options: GameOptions({'freeMovement': true}),
  )..replaceWorld(world);
  final flow = BattleFlow(session, battle, completed: () {})..start();
  for (var i = 0; i < 40; i++) {
    if (session.scene == NativeScene.report) session.closeReport();
    session.advance(const Duration(milliseconds: 100));
  }
  for (var i = 0; i < 20; i++) {
    battle.units[i].state = i == 0 || i == 10 ? 0 : 8;
    battle.units[i].active = 0;
  }
  battle.units[0]
    ..x = 2
    ..y = 2;
  battle.units[10]
    ..x = 10
    ..y = 2;
  battle.focusX = 2;
  battle.focusY = 2;
  return (session: session, battle: battle, world: world, flow: flow);
}

void main() {
  for (final speed in [1, 8]) {
    test('自动战斗${speed}x显示范围和逐格光标，确认前不直接改变我军坐标', () {
      final f = _start(), battle = f.battle, session = f.session;
      try {
        session.options.toggle('autoBattle', enabled: true);
        session.advance(const Duration(milliseconds: 1), speed: speed);
        expect(
          (battle.units[0].x, battle.units[0].y),
          (2, 2),
          reason: '原增强脚本先展示范围并逐个发送方向键，确认后才提交坐标',
        );
        final focusSteps = <(int, int)>[(2, 2)];
        for (
          var i = 0;
          i < 100 && battle.units[0].x == 2 && battle.units[0].y == 2;
          i++
        ) {
          session.advance(const Duration(milliseconds: 50), speed: speed);
          final point = (battle.focusX, battle.focusY);
          if (focusSteps.last != point) focusSteps.add(point);
        }
        expect(focusSteps.length, greaterThan(2));
        for (var i = 1; i < focusSteps.length; i++) {
          expect(
            (focusSteps[i].$1 - focusSteps[i - 1].$1).abs() +
                (focusSteps[i].$2 - focusSteps[i - 1].$2).abs(),
            1,
          );
        }
        expect((battle.units[0].x, battle.units[0].y), isNot((2, 2)));
      } finally {
        session.dispose();
      }
    });
  }

  test('逐格选点途中关闭自动战斗，不留下延时移动或攻击', () {
    final f = _start(), session = f.session, unit = f.battle.units[0];
    try {
      session.options.toggle('autoBattle', enabled: true);
      for (var i = 0; i < 13; i++) {
        session.advance(const Duration(milliseconds: 100));
      }
      expect(f.battle.focusX, greaterThan(2));
      expect(unit.x, 2);
      final focus = (f.battle.focusX, f.battle.focusY);
      session.options.toggle('autoBattle', enabled: false);
      for (var i = 0; i < 20; i++) {
        session.advance(const Duration(milliseconds: 100));
      }
      expect((unit.x, unit.y, unit.active), (2, 2, 0));
      expect((f.battle.focusX, f.battle.focusY), focus);
      expect(session.scene, NativeScene.battle);
    } finally {
      session.dispose();
    }
  });

  test('确认移动后关闭自动战斗，回到动作菜单且不偷偷攻击', () {
    final f = _start(), session = f.session, unit = f.battle.units[0];
    try {
      final target = f.battle.people[10]!;
      final arms = f.world.person(target)!.arms;
      session.options.toggle('autoBattle', enabled: true);
      for (var i = 0; i < 100 && unit.x == 2; i++) {
        session.advance(const Duration(milliseconds: 50));
      }
      expect(unit.x, isNot(2));
      session.options.toggle('autoBattle', enabled: false);
      for (var i = 0; i < 10; i++) {
        session.advance(const Duration(milliseconds: 100));
      }
      expect(session.scene, NativeScene.menu);
      expect(unit.active, 0);
      expect(f.world.person(target)!.arms, arms);
    } finally {
      session.dispose();
    }
  });

  test('按原脚本优先选择最近敌军的武将，规划不改变坐标或随机序列', () {
    final f = _start();
    try {
      f.battle.units[1]
        ..state = 0
        ..active = 0
        ..x = 9
        ..y = 3;
      final positions = [for (final u in f.battle.units) (u.x, u.y)];
      final random = f.world.random.state;
      final plan = f.flow.ai.planPlayer(f.world, f.battle);
      expect(plan?.command.source, 1);
      expect([for (final u in f.battle.units) (u.x, u.y)], positions);
      expect(f.world.random.state, random);
    } finally {
      f.session.dispose();
    }
  });

  test('选点中读入另一局，旧自动步骤不能修改新局', () {
    final f = _start(), session = f.session;
    try {
      session.options.toggle('autoBattle', enabled: true);
      session.advance(const Duration(milliseconds: 100));
      final database = loadGameDatabase(),
          world = database.loadPeriod(2, seed: 2);
      database.beginGame(world, 5);
      session.replaceWorld(world);
      for (var i = 0; i < 20; i++) {
        session.advance(const Duration(milliseconds: 100), speed: 8);
      }
      expect(session.world, same(world));
      expect(session.activeBattle, isNull);
      expect((f.battle.units[0].x, f.battle.units[0].y), (2, 2));
      expect(session.scene, NativeScene.strategy);
    } finally {
      session.dispose();
    }
  });
}

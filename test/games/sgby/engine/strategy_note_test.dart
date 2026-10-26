import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:bbk_flutter/games/sgby/domain/models/game_options.dart';
import 'package:bbk_flutter/games/sgby/engine/core/native_game_session.dart';
import 'package:bbk_flutter/games/sgby/engine/core/strategy_turn_flow.dart';
import 'package:bbk_flutter/games/sgby/engine/rendering/baye_draw_command.dart';

import '../support/game_database.dart';

String _text(NativeGameSession session) => session.canvas.commands
    .where((op) => op.kind == BayeDrawKind.glyph)
    .map((op) => op.text)
    .join();

void main() {
  for (final speed in [1, 8]) {
    test('结束策略$speed倍按原君主顺序显示策略中，展示期间不执行电脑和月结', () {
      final database = loadGameDatabase();
      final world = database.loadPeriod(1, seed: 1);
      database.beginGame(world, 5);
      final session = NativeGameSession(database)..replaceWorld(world);
      try {
        final before = jsonEncode(world.toJson());
        final enemies = database.rulers(world).where((id) => id != 5).toList();
        final flow = StrategyTurnFlow(session)..start();
        for (var i = 0; i < enemies.length; i++) {
          final expected =
              '${database.personName(world.period, enemies[i])}${database.text(64, 163)}';
          expect(_text(session), contains(expected));
          expect(session.scene, NativeScene.report);
          expect(jsonEncode(world.toJson()), before);
          expect(session.resolvingTurn, isTrue);
          // 原GamDelay(5,false)不因键盘、触摸或重复结束策略而跳过。
          session.input(NativeInput.confirm);
          session.tap(120, 135);
          flow.start();
          expect(_text(session), contains(expected));
          session.advance(Duration(microseconds: 48000 ~/ speed), speed: speed);
          expect(_text(session), contains(expected));
          expect(jsonEncode(world.toJson()), before);
          session.advance(Duration(microseconds: 2000 ~/ speed), speed: speed);
        }
        expect(jsonEncode(world.toJson()), isNot(before));
      } finally {
        session.dispose();
      }
    });
  }

  test('提示期间读档或销毁会话，旧回调不会结算新世界', () {
    for (final dispose in [false, true]) {
      final database = loadGameDatabase();
      final oldWorld = database.loadPeriod(1, seed: 1);
      database.beginGame(oldWorld, 5);
      final session = NativeGameSession(database)..replaceWorld(oldWorld);
      StrategyTurnFlow(session).start();
      final replacement = database.loadPeriod(2, seed: 73);
      database.beginGame(replacement, database.rulers(replacement).first);
      if (dispose) {
        session.dispose();
      } else {
        session.replaceWorld(replacement);
      }
      final before = jsonEncode(replacement.toJson());
      for (var i = 0; i < 100; i++) {
        session.advance(const Duration(milliseconds: 200), speed: 8);
      }
      expect(jsonEncode(replacement.toJson()), before);
      if (!dispose) {
        expect(session.resolvingTurn, isFalse);
        expect(session.scene, NativeScene.strategy);
      }
      session.dispose();
    }
  });

  test('提示结束后月结仅执行一次，自动存档和自动策略请求仍按顺序排队', () {
    final database = loadGameDatabase();
    final world = database.loadPeriod(1, seed: 1);
    database.beginGame(world, 5);
    // 保留一个没有部队的敌城，隔离战争和年末事件，仅检查回合事务边界。
    for (var i = 0; i < world.cities.length; i++) {
      world.setCity(i, world.city(i)!.copyWith(belong: i == 37 ? 1 : 6));
    }
    for (var i = 0; i < world.persons.length; i++) {
      final person = world.person(i)!;
      if (person.belong != 0 && person.belong != 65535) {
        world.setPerson(i, person.copyWith(belong: 6));
      }
    }
    final session = NativeGameSession(
      database,
      options: GameOptions({'autoEndTurn': true}),
    )..replaceWorld(world);
    try {
      final flow = StrategyTurnFlow(session)..start();
      flow.start();
      for (var i = 0; i < 5000 && session.resolvingTurn; i++) {
        session.advance(const Duration(milliseconds: 200), speed: 8);
      }
      expect(world.month, 2);
      expect(session.resolvingTurn, isFalse);
      expect(session.scene, NativeScene.strategy);
      expect(session.takeRequests().map((r) => r.type), [
        GameRequestType.autoSave,
        GameRequestType.advanceTurn,
      ]);
    } finally {
      session.dispose();
    }
  });
}

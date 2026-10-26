import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:bbk_flutter/games/sgby/data/services/game_save_codec.dart';
import 'package:bbk_flutter/games/sgby/domain/models/game_options.dart';
import 'package:bbk_flutter/games/sgby/domain/models/game_order.dart';
import 'package:bbk_flutter/games/sgby/domain/use_cases/resolve_battle.dart';
import 'package:bbk_flutter/games/sgby/domain/use_cases/strategy_commands.dart';
import 'package:bbk_flutter/games/sgby/engine/core/native_game_session.dart';
import 'package:bbk_flutter/games/sgby/engine/core/battle_flow.dart';
import 'package:bbk_flutter/games/sgby/engine/core/strategy_turn_flow.dart';
import 'package:bbk_flutter/games/sgby/engine/resources/baye_archive.dart';
import 'package:bbk_flutter/games/sgby/engine/resources/baye_database.dart';
import 'package:bbk_flutter/games/sgby/engine/resources/bitmap_font.dart';
import 'package:bbk_flutter/games/sgby/engine/resources/gbk_codec.dart';

/// 检验流程能完成异步报告/动画边界并回到可输入状态，不通过应用编译验证。
void main() {
  late BayeDatabase database;
  setUpAll(() {
    database = BayeDatabase(
      archive: BayeArchive(
        File('assets/sgby/game/SGBY-Reset-4X.lib').readAsBytesSync(),
      ),
      codec: GbkCodec(
        File('assets/sgby/game/gbk_unicode.bin').readAsBytesSync(),
      ),
      font: BitmapFont(
        File('assets/sgby/game/fallback_font12.bin').readAsBytesSync(),
      ),
      refinedRules:
          jsonDecode(
                File('assets/sgby/game/refined_rules.json').readAsStringSync(),
              )
              as Map<String, dynamic>,
    );
  });
  test('自动战斗逐行动推进并结束，不依赖Timer或宿主按键', () {
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
    final world = codec.decode(<String, dynamic>{...envelope, 'world': saved});
    final order = GameOrder(
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
    );
    final battle = ResolveBattle(database).prepare(world, order).battle!;
    final options = GameOptions({
      'autoBattle': true,
      'oneHitKill': true,
      'animationsDisabled': true,
    });
    final session = NativeGameSession(database, options: options)
      ..replaceWorld(world);
    var finished = false;
    BattleFlow(session, battle, completed: () => finished = true).start();
    for (var i = 0; i < 3000 && !finished; i++) {
      session.advance(const Duration(milliseconds: 200), speed: 8);
    }
    expect(finished, isTrue);
    expect(battle.result, 1);
    expect(battle.day, lessThanOrEqualTo(30));
    expect(world.battleRecord.killedSoldiers, greaterThan(0));
    session.dispose();
  });
  test('统一或全军覆没的结局提示结束后回主菜单并释放旧局', () {
    for (final won in [true, false]) {
      final world = database.loadPeriod(1, seed: 1);
      database.beginGame(world, 5);
      for (var i = 0; i < world.cities.length; i++) {
        world.setCity(i, world.city(i)!.copyWith(belong: won ? 6 : 1));
      }
      final session = NativeGameSession(database)..replaceWorld(world);
      expect(session.scene, NativeScene.report);
      for (var i = 0; i < 11; i++) {
        session.advance(const Duration(milliseconds: 200));
      }
      expect(session.scene, NativeScene.mainMenu);
      expect(session.world, isNull);
      expect(session.resolvingTurn, isFalse);
      session.dispose();
    }
  });

  test('文字菜单首尾循环并把滚动窗口同步到最后一项', () {
    final session = NativeGameSession(database);
    int? selected;
    final entries = List.generate(18, (index) => '菜单$index');
    session.canvasMenu(entries, (value) => selected = value);
    session.input(NativeInput.up);
    session.input(NativeInput.confirm);
    expect(selected, 17);
    session.canvasMenu(
      entries,
      (value) => selected = value,
      initialSelection: 17,
    );
    session.input(NativeInput.down);
    session.input(NativeInput.confirm);
    expect(selected, 0);
    session.canvasMenu(['唯一选项'], (value) => selected = value);
    session.input(NativeInput.up);
    session.input(NativeInput.confirm);
    expect(selected, 0);
    session.dispose();
  });

  test('下令后结束回合能归队和推进月份，重复调用不会结算两次', () {
    final world = database.loadPeriod(1, seed: 1);
    database.beginGame(world, 5);
    for (var i = 0; i < world.cities.length; i++) {
      world.setCity(i, world.city(i)!.copyWith(belong: i == 37 ? 1 : 6));
    }
    for (var i = 0; i < world.persons.length; i++) {
      final p = world.person(i)!;
      if (p.belong != 0 && p.belong != 65535) {
        world.setPerson(i, p.copyWith(belong: 6));
      }
    }
    final command = StrategyCommands(
      database,
    ).make(world, StrategyAction(command: 1, city: 0, person: 56));
    expect(command.success, isTrue);
    expect(world.cityOfPerson(56), isNull);
    final session = NativeGameSession(database)..replaceWorld(world);
    final flow = StrategyTurnFlow(session);
    flow.start();
    flow.start();
    for (var i = 0; i < 5000 && session.resolvingTurn; i++) {
      session.advance(const Duration(milliseconds: 200), speed: 8);
    }
    expect(session.resolvingTurn, isFalse);
    expect(world.month, 2);
    expect(world.orders, isEmpty);
    expect(world.cityOfPerson(56), 0);
    session.dispose();
  });
}

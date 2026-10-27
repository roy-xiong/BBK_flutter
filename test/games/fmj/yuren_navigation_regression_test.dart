import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:bbk_flutter/games/fmj/data/game_data.dart';
import 'package:bbk_flutter/games/fmj/engine/game_actor.dart';
import 'package:bbk_flutter/games/fmj/engine/game_engine.dart';
import 'package:bbk_flutter/games/fmj/ui/system_font_layout.dart';
import 'game_engine_test.dart' show loadData;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GameData data;
  setUpAll(() async => data = await loadData());

  GameEngine engine() {
    final game = GameEngine(
      data,
      textLayout: FlutterSystemFontLayout(),
      random: math.Random(24),
    );
    game.screen = 'play';
    game.intro = null;
    game.preferences['modernUi'] = true;
    game.preferences['runSpeed'] = 1;
    return game;
  }

  /// 只重建问题涉及的公开剧情状态，不带入用户的存档文件、存档槽或个人目录。
  GameEngine postTomb() {
    final game = engine();
    game.map = data.maps['1:30'];
    game.cursor = ScriptCursor(data.scripts['2:50']!)..running = false;
    game.players.add(
      GameActor.load(data, 1, 1)!
        ..x = 4
        ..y = 10,
    );
    game.screenX = 0;
    game.screenY = 7;
    game.flags.addAll([
      11,
      12,
      13,
      14,
      15,
      16,
      17,
      18,
      19,
      21,
      25,
      31,
      65,
      66,
      67,
      68,
      69,
      70,
      101,
      201,
      202,
      203,
      204,
      205,
      206,
      207,
      208,
      209,
      210,
      211,
      212,
      214,
      215,
      216,
      217,
      218,
      219,
      220,
      221,
      222,
      224,
      225,
      226,
      227,
      228,
      229,
      230,
      231,
      232,
      233,
      234,
      235,
      236,
      238,
      239,
      240,
      241,
      243,
      244,
      245,
      246,
      247,
      248,
      249,
      250,
      251,
      252,
      253,
      254,
      264,
      1077,
      1095,
      1100,
      1114,
      1118,
      1130,
      2000,
      2001,
      2002,
      2008,
      2009,
    ]);
    game.variables[1] = 3;
    game.inventory.addAll({
      '14:5': 1,
      '14:6': 1,
      '6:13': 1,
      '13:1': 1,
      '14:8': 1,
      '14:9': 1,
      '14:10': 1,
      '14:11': 1,
    });
    game.preferences.addAll({
      'randomBattleDisabled': true,
      'autoBattle': true,
      'invincible': true,
      'oneHitKill': true,
    });
    return game;
  }

  Future<GameOperation?> arrive(GameEngine game) async {
    for (var frame = 0; frame < 30000; frame++) {
      if (game.navigation.planning) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      game.update();
      if (frame % 10 == 0) await Future<void>.delayed(Duration.zero);
      expect(game.error, isEmpty);
      final op = game.operation;
      if (op?.kind == 'choice') return op;
      if (op != null && {'dialogue', 'message', 'timed'}.contains(op.kind)) {
        game.press(GameKey.confirm);
      }
      if (game.menus.isNotEmpty) game.press(GameKey.cancel);
      if (game.ended) return null;
      if (game.canSave &&
          game.navigation.active == null &&
          !game.navigation.planning &&
          game.route.isEmpty) {
        return null;
      }
    }
    fail('问题场景路线未结束：${game.notice} / ${game.cursor?.script.id}');
  }

  test('追踪愚人居游走NPC不得把玩家带进单向出口', () async {
    final game = engine();
    game.map = data.maps['1:31'];
    game.cursor = ScriptCursor(data.scripts['2:52']!)..running = false;
    game.players.add(
      GameActor.load(data, 1, 1)!
        ..x = 14
        ..y = 7,
    );
    game.screenX = 10;
    game.screenY = 4;
    game.flags.addAll([254, 2008]);
    game.inventory['14:5'] = 1;
    final npc = GameActor.load(data, 2, 32)!
      ..x = 16
      ..y = 7;
    game.npcs[30] = npc;
    expect(npc.state, 1);
    expect(game.map!.canWalk(16, 7), isTrue);
    expect(game.map!.canWalk(16, 7, player: true), isFalse);
    try {
      await game.navigation.startGoal();
      for (var frame = 0; frame < 8; frame++) {
        game.update();
        await Future<void>.delayed(Duration.zero);
      }
      expect(game.cursor?.script.id, '2:52', reason: '追踪房内人物不能触发15,7的离开事件');
      expect(game.map?.id, '1:31');
    } finally {
      game.navigation.cancel();
    }
  });

  test('万能钥匙优先保留给山洞和客栈中的任务卡片', () {
    final game = engine();
    game.flags.addAll([229, 234, 264, 1077]);
    game.inventory['14:2'] = 2;
    final lamp = game.navigation.sideGoals.singleWhere(
      (g) => g.label == '南北村：紫瞳魔灯',
    );
    expect(lamp.ready, isFalse, reason: '剩余两把钥匙需取得小鬼卡片和不点卡片');
  });

  test('自由游走人物长时间等待后仍处于玩家可达区域', () {
    final game = engine();
    game.map = data.maps['1:31'];
    game.cursor = ScriptCursor(data.scripts['2:52']!)..running = false;
    game.players.add(
      GameActor.load(data, 1, 1)!
        ..x = 14
        ..y = 7,
    );
    final npc = GameActor.load(data, 2, 32)!
      ..x = 4
      ..y = 11;
    game.npcs[30] = npc;
    for (var frame = 0; frame < 1500; frame++) {
      game.update();
      expect(game.map!.canWalk(npc.x, npc.y, player: true), isTrue);
    }
  });

  test('受影响旧档一次性补齐遗漏卡片和钥匙，保留其余进度与物品', () {
    final game = postTomb();
    final legacy = game.snapshot()..remove('navigationRevision');
    final flags = Set.of(game.flags);
    final actors = game.players.map((p) => p.toJson()).toList();
    game.restore(legacy);
    expect(game.inventory['14:2'], 1);
    expect(game.inventory['14:7'], 1);
    expect(game.inventory['6:13'], 1);
    expect(game.flags.containsAll(flags), isTrue);
    expect(game.flags.difference(flags), {1099, 2010});
    expect(game.players.map((p) => p.toJson()).toList(), actors);
    expect(game.navigation.nextGoal.scriptId, '2:52');
    expect(game.useGoods('14:2'), isTrue);
    expect(game.useGoods('14:7'), isTrue);
    game.restore(game.snapshot());
    expect(game.inventory['14:2'] ?? 0, 0);
    expect(game.inventory['14:7'] ?? 0, 0);
  });

  test('新版存档自行选择用完钥匙时不触发旧版补偿', () {
    final game = postTomb();
    game.restore(game.snapshot());
    expect(game.inventory['14:2'] ?? 0, 0);
    expect(game.inventory['14:7'] ?? 0, 0);
  });

  test('当前转折路口旧进度恢复后，正常完成愚人居三条支线并继续结局', () async {
    final game = postTomb();
    game.player?.levelUp(data, 28);
    game.players.add(GameActor.load(data, 1, 2)!..levelUp(data, 27));
    game.preferences['runSpeed'] = 2;
    game.restore(game.snapshot()..remove('navigationRevision'));
    try {
      for (final expected in ['奉还', '交出', '奉还']) {
        await game.navigation.startGoal();
        final choice = await arrive(game);
        expect(game.cursor?.script.id, '2:52', reason: game.notice);
        expect(choice?.options, contains(expected));
        game.choose(choice!.options.indexOf(expected), expected: choice);
        await arrive(game);
      }
      // 本回放选择“奉还”，与先选“不给”获得261标志是不同原剧情分支。
      expect(game.flags.containsAll({2301, 2302, 2303}), isTrue);
      for (final id in ['14:5', '14:6', '14:7']) {
        expect(game.inventory[id] ?? 0, 0);
      }
      expect(game.inventory['6:13'], 1);
      for (var goal = 0; goal < 50 && !game.ended; goal++) {
        await game.navigation.startGoal();
        var choice = await arrive(game);
        while (choice != null) {
          game.choose(choice.options.length - 1, expected: choice);
          choice = await arrive(game);
        }
      }
      expect(game.ended, isTrue, reason: '旧进度恢复后必须能继续完成结局：${game.notice}');
    } finally {
      game.navigation.cancel();
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}

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
    // 原NPC的state=1、delay=5，正常游走可以踏进玩家不能进入的地图边缘。
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

  test('万能钥匙必须为山洞和客栈中的任务卡片保留，不能先耗在紫瞳魔灯', () {
    final game = engine();
    game.flags.addAll([229, 234, 264, 1077]);
    game.inventory['14:2'] = 2;
    final lamp = game.navigation.sideGoals.singleWhere(
      (goal) => goal.label == '南北村：紫瞳魔灯',
    );
    expect(lamp.ready, isFalse, reason: '剩余两把钥匙仍需取得小鬼卡片和不点卡片');
  });
}

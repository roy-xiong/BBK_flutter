import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bbk_flutter/games/fmj/engine/game_actor.dart';
import 'package:bbk_flutter/games/fmj/engine/game_engine.dart';
import 'package:bbk_flutter/games/fmj/ui/game_view_model.dart';
import 'package:bbk_flutter/games/fmj/ui/system_font_layout.dart';
import 'game_engine_test.dart' show loadData;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('新版静止场景不每40ms通知及重绘，菜单仍立即更新', () async {
    final game = GameEngine(
      await loadData(),
      textLayout: FlutterSystemFontLayout(),
    );
    game.screen = 'play';
    game.disableSave = true; // 此用例只测画面发布，不启动平台存档插件。
    game.intro = null;
    game.map = game.data.maps.values.first;
    game.players.add(
      GameActor(1, 1)
        ..x = 8
        ..y = 8,
    );
    game.setPreference('modernUi', true);
    final model = GameViewModel()..engine = game;
    var notifications = 0;
    model.addListener(() => notifications++);
    try {
      for (var frame = 0; frame < 200; frame++) {
        model.advanceFrame();
      }
      expect(notifications, 1, reason: '静止8秒只发布第一次画面');
      final revision = model.sceneRevision;
      model.action((g) => g.openMainMenu());
      expect(game.menus, isNotEmpty);
      expect(notifications, 2);
      expect(model.sceneRevision, revision, reason: '菜单不需要重新光栅化地图');
      model.press(GameKey.down);
      expect(game.menus.last.selected, 1);
      expect(notifications, greaterThan(2));
    } finally {
      model.dispose();
    }
  });

  test('新版跳过像素场景后，长对白分页与经典模式完全一致', () async {
    final data = await loadData();
    for (final wide in [false, true]) {
      final game = GameEngine(data, textLayout: FlutterSystemFontLayout());
      game.screen = 'play';
      game.setPreference('wideView', wide);
      final text = List.filled(25, '柳清风：别怕，我来救你。袁姑娘，住手！').join();
      for (final start in [0, 20, 80]) {
        final op = GameOperation('dialogue', text: text, args: [1])
          ..start = start;
        game.operation = op;
        game.setPreference('modernUi', false);
        final expected = op.next;
        game.setPreference('modernUi', true);
        expect(op.next, expected);
        expect(op.next, greaterThan(start));
      }
    }
  });

  test('对白最后一页的确认抬起不穿透到战斗选敌', () async {
    final game = GameEngine(
      await loadData(),
      textLayout: FlutterSystemFontLayout(),
    );
    game.screen = 'play';
    game.players.add(GameActor.load(game.data, 1, 1)!);
    game.setPreference('autoBattle', true);
    final battle = GameBattle(
      game,
      monsters: [10],
      background: [2, 2, 2],
      randomFight: true,
    );
    game.battle = battle;
    game.operation = GameOperation('dialogue', text: '护灯兽：谁在这里撒野。');
    game.render();
    game.press(GameKey.confirm);
    expect(game.operation, isNull);
    expect(battle.targetKind, isEmpty);
    game.update();
    expect(battle.phase, 'perform');
  });

  test('真实跨图规划期间主隔离区心跳仍推进，且只读规划不改变存档', () async {
    final game = GameEngine(
      await loadData(),
      textLayout: FlutterSystemFontLayout(),
    );
    game.restore(
      jsonDecode(
            File(
              'test/games/fmj/fixtures/navigation_start.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>,
    );
    final before = jsonEncode(game.snapshot());
    var beats = 0;
    final heartbeat = Timer.periodic(
      const Duration(milliseconds: 1),
      (_) => beats++,
    );
    try {
      await game.navigation.startGoal(const GameGoal('跨图规划响应测试', '3:9', 1));
      expect(beats, greaterThan(0));
      expect(jsonEncode(game.snapshot()), before);
    } finally {
      heartbeat.cancel();
      game.navigation.cancel();
    }
  });
}

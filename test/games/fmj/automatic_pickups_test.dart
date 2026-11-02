import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bbk_flutter/games/fmj/data/game_data.dart';
import 'package:bbk_flutter/games/fmj/data/save_repository.dart';
import 'package:bbk_flutter/games/fmj/engine/game_actor.dart';
import 'package:bbk_flutter/games/fmj/engine/game_engine.dart';
import 'package:bbk_flutter/games/fmj/ui/game_cheat_panel.dart';
import 'package:bbk_flutter/games/fmj/ui/game_view_model.dart';
import 'package:bbk_flutter/games/fmj/ui/system_font_layout.dart';
import 'game_engine_test.dart' show loadData;

/// 从正式地图、脚本与一键导航进入，断言真实领取和原剧情条件，不在测试中补奖励。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GameData data;
  setUpAll(() async => data = await loadData());
  GameEngine game() => GameEngine(
    data,
    textLayout: FlutterSystemFontLayout(),
    random: math.Random(24),
  )..setPreference('randomBattleDisabled', true);

  Future<void> drive(GameEngine g, {bool stopAtChoice = false}) async {
    for (var frame = 0; frame < 90000; frame++) {
      if (g.navigation.planning) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      g.update();
      expect(g.error, isEmpty);
      if (g.operation?.kind == 'choice') {
        if (stopAtChoice) return;
        fail('不应自动进入选择：${g.operation?.scriptId}/${g.operation?.address}');
      }
      if (g.operation != null &&
          {'dialogue', 'message', 'timed'}.contains(g.operation?.kind)) {
        g.press(GameKey.confirm);
      }
      if (frame % 20 == 0) await Future<void>.delayed(Duration.zero);
      if (g.cursor?.running == false &&
          g.operation == null &&
          !g.navigation.planning &&
          g.navigation.active == null &&
          g.route.isEmpty) {
        return;
      }
    }
    fail('拾取导航未结束：${g.cursor?.script.id}/${g.notice}');
  }

  Future<GameEngine> scene(
    String script,
    String map,
    int x,
    int y, {
    Set<int> flags = const {},
  }) async {
    final g = game()
      ..screen = 'play'
      ..intro = null
      ..map = data.maps[map]
      ..cursor = ScriptCursor(data.scripts[script]!)
      ..players.add(
        GameActor.load(data, 1, 1)!
          ..x = x
          ..y = y,
      )
      ..flags.addAll(flags);
    await drive(g);
    return g;
  }

  Future<void> until(GameEngine g, bool Function() condition) async {
    for (var frame = 0; frame < 20000; frame++) {
      if (condition()) return;
      if (g.navigation.planning) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      g.update();
      expect(g.error, isEmpty);
      if (g.operation?.kind == 'choice') fail('意外选择：${g.operation?.scriptId}');
      if (g.operation != null &&
          {'dialogue', 'message', 'timed'}.contains(g.operation?.kind)) {
        g.press(GameKey.confirm);
      }
      if (frame % 20 == 0) await Future<void>.delayed(Duration.zero);
    }
    fail('未领取目标：${g.notice}');
  }

  test('全83地图185脚本扫描出144个纯拾取点，剧情战斗奖励不当宝箱', () {
    final g = game();
    final points = g.pickups.points;
    expect(data.maps.length, 83);
    expect(data.scripts.length, 185);
    expect(points.length, 144);
    expect(points.map((p) => p.scriptId).toSet().length, 56);
    expect(points.where((p) => p.types.contains(9)).length, 68);
    expect(points.where((p) => p.types.contains(18)).length, 58);
    expect(points.where((p) => p.money > 0).length, 10);
    expect(
      points.any((p) => p.scriptId == '7:1' && p.event == 21),
      false,
      reason: '捡钱袋后有归还选择与战斗，沿用原支线，不伪装成自动领奖',
    );
    Directory('build/validation').createSync(recursive: true);
    File('build/validation/pickup-catalog.json').writeAsStringSync(
      jsonEncode([
        for (final p in points)
          {
            'script': p.scriptId,
            'event': p.event,
            'kind': p.kind,
            'items': [
              for (final id in p.items) {'id': id, 'name': g.goodsName(id)},
            ],
            'money': p.money,
            'addresses': p.addresses.toList(),
          },
      ]),
    );
  });

  test('开关可保存为布尔设置，默认关闭以兼容原导航', () {
    final g = game();
    expect(g.preferences['autoPickup'], false);
    g.setPreference('autoPickup', true);
    expect(g.preferences['autoPickup'], true);
    g.setPreference('autoPickup', 'true');
    expect(g.preferences['autoPickup'], true);
  });

  test('开局先取百草地钨龙剑等三件物品，再与师父推进剧情', () async {
    final g = game()..startNewGame();
    await drive(g);
    expect(g.cursor?.script.id, '2:12');
    expect(g.flags.contains(1021), false);
    g.setPreference('autoPickup', true);
    await g.navigation.startGoal(const GameGoal('见师父', '2:2', 9));
    expect(g.flags.contains(1021), false, reason: '规划不能提前修改真实库存和旗标');
    await drive(g);
    expect(g.inventory['7:9'], 1);
    expect(g.flags, containsAll([1020, 1021, 1121]));
    expect(g.cursor?.script.id, '2:2');
    expect(g.flags.contains(1), false, reason: '最终仍须走完师父的原版对话');
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('关闭开关直接见师父，不领取百草地隐藏剑', () async {
    final g = game()..startNewGame();
    await drive(g);
    await g.navigation.startGoal(const GameGoal('见师父', '2:2', 9));
    await drive(g);
    expect(g.inventory['7:9'] ?? 0, 0);
    expect(g.flags.contains(1021), false);
  });

  test('师父之后百草地出口已改变，不能绕出口强拿或伪造钨龙剑', () async {
    final g = await scene('2:12', '1:2', 19, 3, flags: {1020, 1121});
    g.setPreference('autoPickup', true);
    await g.navigation.startGoal(const GameGoal('回三清宫', '2:1', 0));
    await until(g, () => g.cursor?.script.id != '2:12');
    g.navigation.cancel();
    expect(g.inventory['7:9'] ?? 0, 0);
    expect(g.flags.contains(1021), false);
  });

  test('已领取后用掉或卖掉物品，旧档不重复发放', () async {
    final g = await scene('2:12', '1:2', 19, 3, flags: {1, 1020, 1021, 1121});
    final old = g.snapshot()..remove('pickupDeferred');
    g.restore(GameData.decodeObject(jsonEncode(old)));
    g.setPreference('autoPickup', true);
    await g.navigation.startGoal(const GameGoal('见师父', '2:2', 9));
    await drive(g);
    expect(g.inventory['7:9'] ?? 0, 0);
    expect(g.flags.contains(1021), true);
  });

  test('酆都城水井实际交互领移魂刀，不只看见物品名就加背包', () async {
    final g = await scene('11:1', '1:43', 25, 12);
    g.setPreference('autoPickup', true);
    await g.navigation.startGoal(const GameGoal('酆都城', '11:1', 0));
    await until(g, () => g.flags.contains(1094));
    g.navigation.cancel();
    expect(g.inventory['7:23'], 1);
  });

  test('金币隐藏点一次领取，不重复刷钱', () async {
    final g = await scene('2:10', '2:3', 7, 8);
    g.setPreference('autoPickup', true);
    await g.navigation.startGoal(const GameGoal('清风居', '2:10', 0));
    await until(g, () => g.money == 200);
    g.navigation.cancel();
    expect(g.money, 200);
    final before = g.money;
    await g.navigation.startGoal(const GameGoal('清风居', '2:10', 0));
    for (var i = 0; i < 100; i++) {
      g.update();
      if (g.navigation.planning) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
    }
    g.navigation.cancel();
    expect(g.money, before);
  });

  test('歇息台子按来路给奖励，不能把全部分支都当成本次宝箱内容', () async {
    final g = await scene('2:40', '1:17', 5, 5, flags: {108});
    g.setPreference('autoPickup', true);
    await g.navigation.startGoal(const GameGoal('歇息台子', '2:40', 0));
    await until(g, () => g.flags.contains(76));
    g.navigation.cancel();
    expect(g.inventory['7:24'], 1);
    expect(g.inventory['4:3'] ?? 0, 0);
    expect(g.inventory['5:4'] ?? 0, 0);
  });

  test('取消后台规划，不领取物品，不继续移动', () async {
    final g = game()..startNewGame();
    await drive(g);
    g.setPreference('autoPickup', true);
    final before = jsonEncode(g.snapshot());
    final pending = g.navigation.startGoal(const GameGoal('见师父', '2:2', 9));
    g.navigation.cancel();
    await pending;
    expect(jsonEncode(g.snapshot()), before);
    expect(g.route, isEmpty);
    expect(g.navigation.active, isNull);
  });

  test('观星亭锁箱停下确认，取消不扣钥匙且不重复打扰', () async {
    final g = await scene(
      '2:33',
      '1:12',
      12,
      4,
      flags: {260, 1077, 1095, 1099},
    );
    g.addGoods('14:2');
    g.setPreference('autoPickup', true);
    await g.navigation.startGoal(const GameGoal('查看观星亭', '2:33', 0));
    await drive(g, stopAtChoice: true);
    expect(g.operation?.kind, 'choice');
    expect(g.inventory['14:2'], 1);
    expect(g.inventory['7:32'] ?? 0, 0);
    g.choose(0, expected: g.operation);
    g.setPreference('autoPickup', false);
    await drive(g);
    expect(g.inventory['14:2'], 1);
    expect(g.flags.contains(1104), false);
    expect(g.pickups.deferred, contains('2:33/1'));
  });

  test('锁箱手动确认才扣一把钥匙，重读档不重复给武器', () async {
    final g = await scene(
      '2:33',
      '1:12',
      12,
      4,
      flags: {260, 1077, 1095, 1099},
    );
    g.addGoods('14:2');
    g.setPreference('autoPickup', true);
    await g.navigation.startGoal(const GameGoal('观星亭', '2:33', 0));
    await drive(g, stopAtChoice: true);
    g.choose(1, expected: g.operation);
    g.setPreference('autoPickup', false);
    await drive(g);
    expect(g.inventory['14:2'] ?? 0, 0);
    expect(g.inventory['7:32'], 1);
    expect(g.flags.contains(1104), true);
    final before = jsonEncode(g.snapshot());
    g.restore(GameData.decodeObject(before));
    expect(jsonEncode(g.snapshot()), before);
  });

  test('没有万能钥匙不进入锁箱选择，不妨碍原目标', () async {
    final g = await scene('2:33', '1:12', 12, 4, flags: {260});
    g.setPreference('autoPickup', true);
    await g.navigation.startGoal(const GameGoal('观星亭', '2:33', 0));
    for (var i = 0; i < 100; i++) {
      g.update();
      if (g.navigation.planning) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      expect(g.operation?.kind, isNot('choice'));
    }
    g.navigation.cancel();
    expect(g.inventory['7:32'] ?? 0, 0);
    expect(g.flags.contains(1104), false);
  });

  test('三张任务卡未齐时，不推荐消耗预留钥匙的可选锁箱', () async {
    final g = await scene('2:33', '1:12', 12, 4, flags: {260});
    g.addGoods('14:2', 3);
    g.setPreference('autoPickup', true);
    await g.navigation.startGoal(const GameGoal('观星亭', '2:33', 0));
    for (var frame = 0; frame < 150; frame++) {
      g.update();
      if (g.navigation.planning) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      expect(g.operation?.kind, isNot('choice'));
    }
    g.navigation.cancel();
    expect(g.inventory['14:2'], 3);
  });

  test('刷钱跨图途中切换拾取开关，不清除刷钱导航', () async {
    final g = await scene('7:1', '1:39', 18, 16, flags: {1117, 218, 224});
    g.moneyFarm.toggle();
    expect(g.moneyFarm.active, true);
    g.moneyFarm.tick();
    expect(g.navigation.active, isNotNull);
    final active = g.navigation.active;
    g.setPreference('autoPickup', true);
    expect(g.navigation.active, same(active));
    expect(g.moneyFarm.active, true);
    g.moneyFarm.tick();
    expect(g.moneyFarm.active, true);
    g.moneyFarm.stop();
  });

  test('取消的锁箱随档保存，开关重新开启后才重试', () async {
    final g = await scene(
      '2:33',
      '1:12',
      12,
      4,
      flags: {260, 1077, 1095, 1099},
    );
    g.addGoods('14:2');
    g.setPreference('autoPickup', true);
    await g.navigation.startGoal(const GameGoal('观星亭', '2:33', 0));
    await drive(g, stopAtChoice: true);
    g.choose(0, expected: g.operation);
    g.navigation.cancel();
    await drive(g);
    final saved = GameData.decodeObject(jsonEncode(g.snapshot()));
    g.restore(saved);
    expect(g.pickups.deferred, contains('2:33/1'));
    expect(g.flags.contains(2334), true);
    g.setPreference('autoPickup', false);
    g.setPreference('autoPickup', true);
    expect(g.pickups.deferred, isEmpty);
    expect(g.flags.contains(2334), false);
    await g.navigation.startGoal(const GameGoal('观星亭', '2:33', 0));
    await drive(g, stopAtChoice: true);
    expect(g.operation?.kind, 'choice');
    expect(g.inventory['14:2'], 1);
    g.navigation.cancel();
  });

  test('拾取开关经真实持久化后保留，旧设置无此字段默认关闭', () async {
    final directory = await Directory.systemTemp.createTemp(
      'fmj-pickup-prefs-',
    );
    final repository = SaveRepository(directory: directory);
    final model = GameViewModel(repository: repository)
      ..engine = game()
      ..loading = false;
    GameViewModel? reopened;
    try {
      model.engine!.setPreference('autoPickup', true);
      await model.persist(rethrowOnFailure: true);
      reopened = GameViewModel(repository: repository);
      await reopened.initialize();
      expect(reopened.engine!.preferences['autoPickup'], true);
      final saved = await repository.read();
      expect((saved!['preferences'] as Map)['autoPickup'], true);
    } finally {
      reopened?.dispose();
      model.dispose();
      await repository.flush();
      await directory.delete(recursive: true);
    }
  });

  testWidgets('作弊页能操作拾取开关', (tester) async {
    final directory = Directory.systemTemp.createTempSync('fmj-pickup-widget-');
    final repository = SaveRepository(directory: directory);
    final model = GameViewModel(repository: repository)
      ..engine = game()
      ..loading = false;
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: GameCheatPanel(model: model)),
        ),
      );
      final tile = find.widgetWithText(SwitchListTile, '一键直达拾取物品');
      await tester.scrollUntilVisible(tile, 200);
      await tester.tap(tile);
      await tester.pump();
      expect(model.engine!.preferences['autoPickup'], true);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      model.dispose();
      var done = false;
      repository.flush().then((_) => done = true);
      for (var i = 0; i < 100 && !done; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(done, true);
      await tester.runAsync(() => directory.delete(recursive: true));
    }
  });
}

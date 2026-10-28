import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bbk_flutter/games/fmj/data/game_data.dart';
import 'package:bbk_flutter/games/fmj/engine/game_engine.dart';
import 'package:bbk_flutter/games/fmj/ui/game_view_model.dart';
import 'package:bbk_flutter/games/fmj/ui/modern_game_view.dart';
import 'package:bbk_flutter/games/fmj/ui/system_font_layout.dart';
import 'package:bbk_flutter/ui/core/desktop_window_service.dart';
import 'game_engine_test.dart' show loadData;

/// 覆盖本轮真实交易、完整刷钱循环、取消以及点击地图的坐标和碰撞边界。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GameData data;
  setUpAll(() async => data = await loadData());
  GameEngine create() {
    final g = GameEngine(
      data,
      textLayout: FlutterSystemFontLayout(),
      random: math.Random(24),
    );
    final initial =
        jsonDecode(
              File(
                'test/games/fmj/fixtures/navigation_start.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    g.restore(initial);
    g.preferences['modernUi'] = true;
    return g;
  }

  test('出售与购买数量均使用向上增加、向下减少', () {
    final g = create()..inventory['6:12'] = 3;
    g.openInventory(mode: 'sell');
    g.press(GameKey.confirm);
    g.press(GameKey.up);
    expect(g.menus.last.purchase?.quantity, 1);
    g.press(GameKey.down);
    expect(g.menus.last.purchase?.quantity, 0);
  });

  test('鼠标目标不可达时走到阻碍前，不穿墙、不走到其他事件', () {
    final g = create();
    g.npcs.clear();
    final cells = List<int>.filled(20 * 14, 128);
    for (var y = 0; y < 14; y++) {
      cells[y * 20 + 10] = 0;
    }
    g.map = GameMap({
      'id': 'test',
      'name': '碰撞测试',
      'width': 20,
      'height': 14,
      'tiles': 1,
      'cells': cells,
    });
    g.player!
      ..x = 6
      ..y = 6;
    g.cursor?.running = false;
    final dynamic engine = g;
    expect(engine.walkTo(13, 6, nearest: true), true);
    expect(g.route.last, (9, 6));
    expect(g.route.every((p) => p.$1 < 10), true);
    g.navigation.cancel();
  });

  testWidgets('点击彩色地图使用镜头坐标进入真实路线，菜单覆盖时不穿透', (tester) async {
    final g = create();
    g.npcs.clear();
    g.cursor?.running = false;
    g.player!
      ..x = 10
      ..y = 7;
    g.map = GameMap({
      'id': 'test',
      'name': '点击测试',
      'width': 30,
      'height': 20,
      'tiles': 1,
      'cells': List<int>.filled(600, 128),
    });
    final vm = GameViewModel()
      ..engine = g
      ..loading = false;
    await tester.runAsync(vm.prepareModernArt);
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 640,
            height: 430,
            child: ModernGameView(model: vm),
          ),
        ),
      );
      await tester.pump();
      final rect = tester.getRect(
        find.byKey(const ValueKey('modern-scene-region')),
      );
      await tester.tapAt(
        rect.topLeft + Offset(rect.width * .675, rect.height * .45),
      );
      await tester.pump();
      expect(g.route, isNotEmpty);
      g.navigation.cancel();
      g.openMainMenu();
      await tester.pump();
      await tester.tapAt(
        rect.topLeft + Offset(rect.width * .675, rect.height * .45),
      );
      expect(g.route, isEmpty);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      vm.dispose();
    }
  });

  test('Esc不再被窗口全局拦截和最小化', () {
    expect(
      DesktopWindowService.handleKey(
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.escape,
          logicalKey: LogicalKeyboardKey.escape,
          timeStamp: Duration.zero,
        ),
      ),
      false,
    );
  });

  test('朱雀现身与天师魂魄地图帧复用同身份战斗原画，天道保持统一设计', () {
    final hd = GameData.decodeObject(
      File('assets/fmj/modern/enhanced-art.json').readAsStringSync(),
    );
    expect(hd['frames']['mechanism:42/0'], hd['frames']['battle:monster:35/0']);
    expect(hd['frames']['mechanism:36/0'], hd['frames']['battle:monster:38/0']);
    expect(hd['frames']['mechanism:31/0'], isNotNull);
  });

  test('一键刷钱连续完成三轮真实战斗和出售，仅卖富贵珠，取消后停止', () async {
    final g = create();
    final stage = Map<String, dynamic>.from(
      data.stages.firstWhere((s) => s['scriptId'] == '7:1'),
    );
    g.selectStage(stage);
    for (var i = 0; i < 200; i++) {
      g.update();
      if (const {'timed', 'dialogue', 'message'}.contains(g.operation?.kind)) {
        g.press(GameKey.confirm);
      }
      if (g.cursor?.running != true && g.operation == null) break;
    }
    g.flags
      ..remove(221)
      ..add(1117);
    g.preferences.addAll({
      'modernUi': true,
      'invincible': true,
      'oneHitKill': true,
      'normalAttackAll': true,
      'randomBattleDisabled': true,
      'runSpeed': 4,
    });
    g.inventory['9:1'] = 7;
    final startMoney = g.money;
    final dynamic farm = (g as dynamic).moneyFarm;
    farm.toggle();
    final visited = <String>{};
    var sawBattle = false;
    for (var i = 0; i < 45000 && farm.rounds < 3; i++) {
      g.update();
      visited.add(g.cursor?.script.id ?? '');
      sawBattle |= g.battle != null;
      if (g.navigation.planning) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      } else if (i % 20 == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(g.error, isEmpty);
      expect(farm.active, true, reason: g.notice);
    }
    expect(farm.rounds, 3);
    expect(sawBattle, true);
    expect(visited, containsAll(['7:1', '7:2', '7:5']));
    expect(g.inventory['6:12'] ?? 0, 0);
    expect(g.inventory['9:1'], 7);
    expect(g.money - startMoney, 31950 * 3);
    farm.toggle();
    expect(farm.active, false);
    expect(g.navigation.active, isNull);
    expect(g.route, isEmpty);
    final after = g.money;
    for (var i = 0; i < 30; i++) {
      g.update();
    }
    expect(g.money, after);
    g.navigation.cancel();
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('关闭条件存在时不刷写剧情旗标；普通方向输入立即中断刷钱', () {
    final g = create();
    g.flags.add(221);
    final dynamic farm = (g as dynamic).moneyFarm;
    farm.toggle();
    expect(farm.active, false);
    expect(g.flags.contains(221), true);
    expect(g.notice, contains('剧情'));
    g.flags
      ..remove(221)
      ..add(1117);
    farm.toggle();
    expect(farm.active, true);
    g.press(GameKey.left);
    expect(farm.active, false);
    g.navigation.cancel();
  });
}

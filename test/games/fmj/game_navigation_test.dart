import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bbk_flutter/games/fmj/engine/game_engine.dart';
import 'package:bbk_flutter/games/fmj/data/game_data.dart';
import 'package:bbk_flutter/games/fmj/ui/game_page.dart';
import 'package:bbk_flutter/games/fmj/ui/game_controls.dart';
import 'package:bbk_flutter/games/fmj/ui/game_view_model.dart';
import 'package:bbk_flutter/games/fmj/ui/modern_game_view.dart';
import 'package:bbk_flutter/games/fmj/ui/modern_map_camera.dart';
import 'package:bbk_flutter/games/fmj/ui/system_font_layout.dart';
import 'game_engine_test.dart' show loadData;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final initial =
      jsonDecode(
            File(
              'test/games/fmj/fixtures/navigation_start.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  late GameData data;
  setUpAll(() async {
    data = await loadData();
  });
  GameEngine engine() => GameEngine(
    data,
    textLayout: FlutterSystemFontLayout(),
    random: math.Random(24),
  );

  Future<void> drive(GameEngine game, {int limit = 15000}) async {
    for (var i = 0; i < limit; i++) {
      game.update();
      // 让只读规划交还事件循环，实际游戏仍以固定 40ms 步长推进。
      if (i % 25 == 0) await Future<void>.delayed(Duration.zero);
      if (game.navigation.active == null && !game.navigation.planning) return;
      final op = game.operation;
      if (op != null && {'dialogue', 'message', 'timed'}.contains(op.kind)) {
        game.press(GameKey.confirm);
      }
      expect(game.error, isEmpty);
      expect(op?.kind, isNot('choice'), reason: '导航不能代替玩家回答分支');
      if (game.battle != null) return;
    }
    fail('导航未在 $limit 帧内到达或交还剧情操作：${game.notice}');
  }

  test('无机阁实际失败存档：只读规划后正常跨图到护灯试炼入口', () async {
    final game = engine();
    game.restore(initial);
    game.setPreference('randomBattleDisabled', true);
    final before = jsonEncode(game.snapshot());
    await game.navigation.startGoal();
    expect(jsonEncode(game.snapshot()), before);
    expect(game.route, isNotEmpty);
    await drive(game);
    expect(game.cursor?.script.id, '2:19');
    expect(game.navigation.active, isNull);
    expect(game.flags.contains(11), isFalse, reason: '到达入口不等于自动完成护灯试炼');
    expect(game.error, isEmpty);
  });

  test('装备芦藤甲后从李府跨地图抵达蛇窟，保留道具与装备', () async {
    final game = engine();
    final stage = Map<String, dynamic>.from(game.data.stages[32])
      ..addAll({
        'scriptId': '5:15',
        'mapId': '2:20',
        'x': 12,
        'y': 9,
        'event': 0,
      });
    game.selectStage(stage);
    for (var i = 0; i < 300; i++) {
      game.update();
      if ({'dialogue', 'timed', 'message'}.contains(game.operation?.kind)) {
        game.press(GameKey.confirm);
      }
    }
    // 关闭随机遭遇只用于复现路线；正式游戏默认保留随机战斗。
    game.setPreference('randomBattleDisabled', true);
    final equipment = jsonEncode(game.players.map((p) => p.equipment).toList());
    final flags = Set<int>.of(game.flags);
    await game.navigation.startGoal(const GameGoal('到蛇窟深处除妖', '4:8', 43));
    await drive(game);
    expect(game.cursor?.script.id, '4:8');
    expect(game.flags.contains(215), isFalse, reason: '除妖战斗仍由玩家触发和完成');
    expect(game.flags.containsAll(flags), isTrue);
    expect(
      jsonEncode(game.players.map((p) => p.equipment).toList()),
      equipment,
    );
  });

  test('规划期间取消后，异步旧结果不会重新启动自动移动', () async {
    final game = engine();
    game.restore(initial);
    final planning = game.navigation.startGoal();
    game.navigation.cancel();
    await planning;
    expect(game.navigation.active, isNull);
    expect(game.navigation.planning, isFalse);
    expect(game.route, isEmpty);
  });

  test('新版投影上下左右分别平行屏幕纵轴与横轴', () {
    final camera = ModernMapCamera(
      mapWidth: 46,
      mapHeight: 46,
      playerX: 24,
      playerY: 18,
      wide: true,
    );
    final origin = camera.point(24, 18);
    expect(camera.point(24, 17) - origin, const Offset(0, -32));
    expect(camera.point(24, 19) - origin, const Offset(0, 32));
    expect(camera.point(23, 18) - origin, const Offset(-32, 0));
    expect(camera.point(25, 18) - origin, const Offset(32, 0));
  });

  Future<void> capture(WidgetTester tester, String name) async {
    await tester.pump();
    expect(tester.takeException(), isNull);
    final boundary =
        tester.renderObject(find.byKey(const Key('capture')))
            as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes != null) {
        Directory('build/validation').createSync(recursive: true);
        File(
          'build/validation/$name.png',
        ).writeAsBytesSync(bytes.buffer.asUint8List());
      }
      image.dispose();
    });
  }

  testWidgets('原版竖屏红白机布局、横屏悬浮布局和方向按钮均可操作', (tester) async {
    final model = GameViewModel()
      ..engine = engine()
      ..loading = false;
    final game = model.engine;
    if (game == null) fail('缺少会话');
    game.restore(initial);
    for (final size in [const Size(390, 844), const Size(1000, 600)]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: RepaintBoundary(
            key: const Key('capture'),
            child: GamePage(viewModel: model),
          ),
        ),
      );
      await tester.pump();
      if (size.height > size.width) {
        expect(
          find.byKey(const ValueKey('fmj-quick-travel-large')),
          findsOneWidget,
        );
        expect(find.text('B'), findsOneWidget);
        expect(find.text('A'), findsOneWidget);
        expect(find.byType(PortraitGameControlsPanel), findsOneWidget);
        expect(find.text('SELECT'), findsOneWidget);
        expect(find.text('START'), findsOneWidget);
      } else {
        expect(find.byType(GameControlsOverlay), findsNothing);
        expect(find.byType(PortraitGameControlsPanel), findsNothing);
        expect(find.text('A'), findsNothing);
        expect(find.text('B'), findsNothing);
      }
      await capture(tester, 'controls-${size.width.toInt()}');
    }
    // 键盘继续经过同一个会话入口，按钮重排不改变碰撞/剧情位置。
    final before = game.player?.y;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(game.player?.y, lessThanOrEqualTo(before ?? 0));
    await tester.pumpWidget(const SizedBox.shrink());
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  testWidgets('新版三清宫、室内、战斗和菜单输出实际画面', (tester) async {
    final model = GameViewModel()
      ..engine = engine()
      ..loading = false;
    final game = model.engine;
    if (game == null) fail('缺少会话');
    await tester.runAsync(() => model.prepareModernArt());
    expect(
      model.modernArt,
      isNotNull,
      reason: model.modernArtError?.toString(),
    );
    game.restore(initial);
    tester.view.physicalSize = const Size(960, 576);
    tester.view.devicePixelRatio = 1;
    Widget page() => MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(
        body: RepaintBoundary(
          key: const Key('capture'),
          child: ModernGameView(model: model),
        ),
      ),
    );
    await tester.pumpWidget(page());
    await capture(tester, 'new-interior');
    game.map = game.data.maps['1:1'];
    game.sceneName = '三清宫';
    game.player?.x = 24;
    game.player?.y = 18;
    game.npcs.clear();
    await tester.pumpWidget(page());
    await capture(tester, 'new-outdoor');
    game.openMainMenu();
    await tester.pumpWidget(page());
    await capture(tester, 'new-menu');
    game.menus.clear();
    game.battle = GameBattle(
      game,
      monsters: [1, 2],
      background: const [2, 2, 2],
      randomFight: true,
    );
    await tester.pumpWidget(page());
    await capture(tester, 'new-battle');
    await tester.pumpWidget(const SizedBox.shrink());
    model.dispose();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

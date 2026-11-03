import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bbk_flutter/games/fmj/data/game_data.dart';
import 'package:bbk_flutter/games/fmj/data/save_repository.dart';
import 'package:bbk_flutter/games/fmj/engine/game_engine.dart';
import 'package:bbk_flutter/games/fmj/engine/game_actor.dart';
import 'package:bbk_flutter/games/fmj/ui/modern_art.dart';
import 'package:bbk_flutter/games/fmj/ui/modern_scene.dart';
import 'package:bbk_flutter/games/fmj/ui/modern_map_camera.dart';
import 'package:bbk_flutter/games/fmj/ui/modern_game_view.dart';
import 'package:bbk_flutter/games/fmj/ui/game_controls.dart';
import 'package:bbk_flutter/games/fmj/ui/game_page.dart';
import 'package:bbk_flutter/games/fmj/ui/game_view_model.dart';
import 'package:bbk_flutter/games/fmj/ui/system_font_layout.dart';
import 'package:bbk_flutter/ui/core/desktop_window_service.dart';
import 'game_engine_test.dart' show loadData;

/// 通过真实菜单、长按和桌面生命周期验证本轮交互，不调用本地应用编译。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GameData data;
  setUpAll(() async => data = await loadData());
  GameEngine game() => GameEngine(data, textLayout: FlutterSystemFontLayout())
    ..restore(
      GameData.decodeObject(
        File(
          'test/games/fmj/fixtures/navigation_start.json',
        ).readAsStringSync(),
      ),
    )
    ..preferences['hapticsEnabled'] = false;

  Future<void> dispose(
    WidgetTester tester,
    GameViewModel vm,
    SaveRepository saves,
    Directory dir,
  ) async {
    await tester.pumpWidget(const SizedBox.shrink());
    vm.dispose();
    var done = false;
    saves.flush().then((_) => done = true);
    for (var i = 0; i < 100 && !done; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(done, isTrue);
    await tester.runAsync(() => dir.delete(recursive: true));
  }

  test('出售先选数量，预览和取消都不减库存，确认只出售指定数量', () {
    final g = game();
    g.inventory.clear();
    g.inventory['9:1'] = 5;
    g.money = 100;
    g.openInventory(mode: 'sell');
    g.press(GameKey.confirm);
    expect(g.inventory['9:1'], 5);
    expect(g.money, 100);
    expect(g.menus.last.kind, 'sell-quantity');
    g.press(GameKey.up);
    g.press(GameKey.up);
    expect(g.inventory['9:1'], 5);
    g.press(GameKey.cancel);
    expect(g.money, 100);
    expect(g.inventory['9:1'], 5);
    g.press(GameKey.confirm);
    g.press(GameKey.up);
    g.press(GameKey.up);
    g.press(GameKey.confirm);
    expect(g.inventory['9:1'], 3);
    expect(g.money, 100 + g.goods('9:1')!.word(20) * 2);
  });

  testWidgets('长按一键前往连续触发，松开后停止', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GameControlsOverlay(
            hapticsEnabled: false,
            onInput: (input) {
              if (input == GameControl.quickTravel) taps++;
            },
          ),
        ),
      ),
    );
    final touch = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('fmj-quick-travel-large'))),
    );
    await tester.pump(const Duration(milliseconds: 150));
    expect(taps, 1);
    // 按连续帧模拟按住过程；一次跳过600ms会把新创建的延迟计时器也推迟到末帧。
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(taps, greaterThanOrEqualTo(4));
    await touch.up();
    final stopped = taps;
    await tester.pump(const Duration(seconds: 1));
    expect(taps, stopped);
  });

  testWidgets('Q长按等同连续A，松开后不再推进后续对白', (tester) async {
    final g = game();
    final dir = Directory.systemTemp.createTempSync('fmj-q-repeat-');
    final saves = SaveRepository(directory: dir);
    // 同一仓库拥有测试清理的写入队列。
    final model = GameViewModel(repository: saves)
      ..engine = g
      ..loading = false;
    try {
      g.operation = GameOperation('timed', text: '第一条');
      await tester.pumpWidget(MaterialApp(home: GamePage(viewModel: model)));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyQ);
      expect(g.operation, isNull);
      final second = GameOperation('timed', text: '第二条');
      g.operation = second;
      await tester.pump(const Duration(milliseconds: 319));
      expect(g.operation, same(second));
      await tester.pump(const Duration(milliseconds: 110));
      expect(g.operation, isNull);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyQ);
      final third = GameOperation('timed', text: '第三条');
      g.operation = third;
      await tester.pump(const Duration(seconds: 1));
      expect(g.operation, same(third));
    } finally {
      await dispose(tester, model, saves, dir);
    }
  });

  for (final platform in [TargetPlatform.macOS, TargetPlatform.windows]) {
    testWidgets('$platform失焦或隐藏仍推进游戏，弹窗及移动端规则不被放开', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      final g = game(),
          dir = Directory.systemTemp.createTempSync('fmj-background-');
      final saves = SaveRepository(directory: dir);
      final model = GameViewModel(repository: saves)
        ..engine = g
        ..loading = false;
      try {
        await tester.pumpWidget(MaterialApp(home: GamePage(viewModel: model)));
        for (final state in [
          AppLifecycleState.inactive,
          AppLifecycleState.hidden,
        ]) {
          tester.binding.handleAppLifecycleStateChanged(state);
          final ticks = g.ticks;
          model.advanceFrame();
          expect(model.paused, isFalse);
          expect(g.ticks, greaterThan(ticks));
        }
        model.setPaused(true);
        final ticks = g.ticks;
        model.advanceFrame();
        expect(g.ticks, ticks);
      } finally {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await dispose(tester, model, saves, dir);
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  testWidgets('桌面Esc恢复游戏取消，不请求最小化窗口', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    var minimized = 0;
    const channel = MethodChannel('bbk_flutter/window');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method == 'minimize') minimized++;
      return null;
    });
    final g = game(),
        dir = Directory.systemTemp.createTempSync('fmj-minimize-');
    final saves = SaveRepository(directory: dir);
    final model = GameViewModel(repository: saves)
      ..engine = g
      ..loading = false;
    try {
      await tester.pumpWidget(MaterialApp(home: GamePage(viewModel: model)));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(minimized, 0);
      expect(g.menus.last.kind, 'main');
    } finally {
      await dispose(tester, model, saves, dir);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      );
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('桌面弹窗显示时Esc正常关闭，组件释放后没有残留快捷键回调', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    var calls = 0;
    const channel = MethodChannel('bbk_flutter/window');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls++;
      return null;
    });
    try {
      await tester.pumpWidget(
        MaterialApp(
          builder: (_, child) => DesktopWindowShortcuts(child: child!),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => const AlertDialog(title: Text('测试弹窗')),
                ),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(calls, 0);
      await tester.pumpAndSettle();
      expect(find.text('测试弹窗'), findsNothing);
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: const Text('已释放'))),
      );
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(calls, 0);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      );
      debugDefaultTargetPlatformOverride = null;
    }
  });

  test('建业当铺杂货铺北侧原事件格归属北向屋顶，李府原石狮与木桶不变成坟椅', () {
    final hd = GameData.decodeObject(
      File('assets/fmj/modern/enhanced-art.json').readAsStringSync(),
    );
    for (final x in [9, 22]) {
      final m = data.maps['1:39']!;
      expect(m.event(x, 10), greaterThan(0));
      final rows = (hd['buildings']['1:39'] as List).cast<Map>();
      final b = rows.singleWhere((b) => b['x'] == x - 1 && b['y'] == 10);
      expect(b['key'], 'building:house-north');
      expect(b['cells'], contains(10 * m.width + x));
    }
    final lions = (hd['buildings']['1:37'] as List).cast<Map>().where(
      (b) => b['x'] == 28 && [8, 12].contains(b['y']),
    );
    expect(lions, hasLength(2));
    expect(lions.every((b) => b['key'] == 'scenery:stone-lion-right'), isTrue);
    final m = data.maps['1:37']!, bucketCell = 15 * m.width + 45;
    expect(m.cell(45, 15) & 127, 64);
    expect(
      (hd['decorations']['1:37'] as List).any(
        (b) =>
            b['key'] == 'furniture:wooden-bucket' &&
            (b['cells'] as List).contains(bucketCell),
      ),
      isTrue,
    );
  });

  testWidgets('窄屏购买出售子金光符时，默认无需滚动就能完整阅读说明', (tester) async {
    final g = game();
    g.preferences['modernUi'] = true;
    g.inventory['12:5'] = 2;
    final model = GameViewModel()
      ..engine = g
      ..loading = false;
    await tester.runAsync(() => model.prepareModernArt());
    tester.view.physicalSize = const Size(360, 250);
    tester.view.devicePixelRatio = 1;
    try {
      for (final mode in ['buy', 'sell']) {
        g.menus.clear();
        g.openInventory(mode: mode, items: ['12:5']);
        await tester.pumpWidget(
          MaterialApp(home: ModernGameView(model: model)),
        );
        await tester.pump();
        final description = find.text(g.goods('12:5')!.text(30));
        expect(description, findsOneWidget);
        final pane = find
            .ancestor(
              of: description,
              matching: find.byType(SingleChildScrollView),
            )
            .first;
        final scroll = tester.state<ScrollableState>(
          find.descendant(of: pane, matching: find.byType(Scrollable)),
        );
        expect(
          scroll.position.maxScrollExtent,
          closeTo(0, .1),
          reason: '$mode 子金光符应在详情区域完整显示',
        );
      }
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      model.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    }
  });

  if (Platform.environment['FMJ_EXPORT_APPROVED_ART'] == '1') {
    testWidgets('导出购买出售说明区与出售数量确认框', (tester) async {
      final g = game();
      g.preferences['modernUi'] = true;
      g.money = 5000;
      final vm = GameViewModel()
        ..engine = g
        ..loading = false;
      await tester.runAsync(() => vm.prepareModernArt());
      final font = FontLoader('BBK CJK')
        ..addFont(rootBundle.load('assets/fonts/NotoSansCJKsc-Regular.otf'));
      await font.load();
      final icons = FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await icons.load();
      final out = Directory('build/validation/current-scene-audit')
        ..createSync(recursive: true);
      tester.view.devicePixelRatio = 1;
      try {
        for (final width in [360, 800]) {
          tester.view.physicalSize = Size(width.toDouble(), width * .6 + 40);
          for (final mode in ['buy', 'sell', 'sale-confirm']) {
            g.menus.clear();
            g.inventory.clear();
            g.inventory.addAll({'12:5': 3, '9:1': 5, '7:2': 2});
            g.openInventory(
              mode: mode == 'buy' ? 'buy' : 'sell',
              items: ['12:5', '9:1', '7:2'],
            );
            if (mode == 'sale-confirm') {
              g.press(GameKey.confirm);
              g.changePurchaseQuantity(g.menus.last, 2);
            }
            await tester.pumpWidget(
              MaterialApp(
                theme: ThemeData.dark().copyWith(
                  textTheme: ThemeData.dark().textTheme.apply(
                    fontFamily: 'BBK CJK',
                  ),
                ),
                home: Scaffold(
                  body: RepaintBoundary(
                    key: const ValueKey('audit-ui'),
                    child: ModernGameView(model: vm),
                  ),
                ),
              ),
            );
            await tester.pump();
            final boundary =
                tester.renderObject(find.byKey(const ValueKey('audit-ui')))
                    as RenderRepaintBoundary;
            await tester.runAsync(() async {
              final image = await boundary.toImage(pixelRatio: 2);
              try {
                final png = await image.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                File(
                  '${out.path}/$mode-$width.png',
                ).writeAsBytesSync(png!.buffer.asUint8List());
              } finally {
                image.dispose();
              }
            });
          }
        }
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        vm.dispose();
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      }
    });

    testWidgets('导出本轮山门、客厅、狮子木桶和北向店铺的正式绘制画面', (tester) async {
      await tester.runAsync(() async {
        final art = await ModernArt.load();
        final g = game();
        final font = FontLoader('BBK CJK')
          ..addFont(rootBundle.load('assets/fonts/NotoSansCJKsc-Regular.otf'));
        await font.load();
        final actors =
            jsonDecode(
                  File(
                    'test/games/fmj/fixtures/approved_map_actors.json',
                  ).readAsStringSync(),
                )
                as Map;
        final out = Directory('build/validation/current-scene-audit')
          ..createSync(recursive: true);
        try {
          for (final item in [
            ('1:1', 23, 41, 'sanqing-gate'),
            ('2:20', 10, 8, 'lifu-hall'),
            ('1:37', 29, 10, 'lifu-lions'),
            ('1:37', 44, 16, 'lifu-bucket-well'),
            ('1:39', 16, 10, 'jianye-north-shops'),
          ]) {
            g.map = data.maps[item.$1];
            g.npcs.clear();
            g.players.clear();
            for (final row in actors[item.$1] as List) {
              final a = GameActor.load(
                data,
                row['type'] as int,
                row['index'] as int,
              );
              if (a != null) {
                a.x = row['x'] as int;
                a.y = row['y'] as int;
                g.npcs[g.npcs.length + 1] = a;
              }
            }
            final recorder = ui.PictureRecorder(), canvas = Canvas(recorder);
            final camera = ModernMapCamera(
              mapWidth: g.map!.width,
              mapHeight: g.map!.height,
              playerX: item.$2,
              playerY: item.$3,
              wide: true,
            );
            ModernScenePainter(
              g,
              art,
              cameraOverride: camera,
              textStyle: const TextStyle(fontFamily: 'BBK CJK'),
            ).paint(canvas, const Size(640, 384));
            final picture = recorder.endRecording(),
                image = await picture.toImage(640, 384);
            try {
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              File(
                '${out.path}/${item.$4}.png',
              ).writeAsBytesSync(bytes!.buffer.asUint8List());
            } finally {
              image.dispose();
              picture.dispose();
            }
          }
        } finally {
          art.dispose();
        }
      });
    });
  }
}

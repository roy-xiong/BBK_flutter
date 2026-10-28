import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bbk_flutter/games/fmj/data/game_data.dart';
import 'package:bbk_flutter/games/fmj/data/save_repository.dart';
import 'package:bbk_flutter/games/fmj/engine/game_engine.dart';
import 'package:bbk_flutter/games/fmj/ui/game_controls.dart';
import 'package:bbk_flutter/games/fmj/ui/game_page.dart';
import 'package:bbk_flutter/games/fmj/ui/game_view_model.dart';
import 'package:bbk_flutter/games/fmj/ui/system_font_layout.dart';
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
    g.press(GameKey.down);
    g.press(GameKey.down);
    expect(g.inventory['9:1'], 5);
    g.press(GameKey.cancel);
    expect(g.money, 100);
    expect(g.inventory['9:1'], 5);
    g.press(GameKey.confirm);
    g.press(GameKey.down);
    g.press(GameKey.down);
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
      tester.getCenter(find.text('一键前往当前目标')),
    );
    await tester.pump(const Duration(milliseconds: 150));
    expect(taps, 1);
    await tester.pump(const Duration(milliseconds: 600));
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

  testWidgets('桌面Esc请求最小化窗口，不向游戏提交取消键', (tester) async {
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
      expect(minimized, 1);
      expect(g.menus, isEmpty);
    } finally {
      await dispose(tester, model, saves, dir);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      );
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

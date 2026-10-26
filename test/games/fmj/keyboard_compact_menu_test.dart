import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bbk_flutter/games/fmj/engine/game_engine.dart';
import 'package:bbk_flutter/games/fmj/ui/game_page.dart';
import 'package:bbk_flutter/games/fmj/ui/game_view_model.dart';
import 'package:bbk_flutter/games/fmj/ui/modern_game_view.dart';
import 'package:bbk_flutter/games/fmj/ui/system_font_layout.dart';
import 'game_engine_test.dart' show loadData;

/// 回归真实键盘入口、生产帧驱动和窄屏菜单，避免只验证脱离页面的计时工具。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Future<GameViewModel> model() async {
    final data = await loadData();
    final game = GameEngine(data, textLayout: FlutterSystemFontLayout())
      ..restore(
        jsonDecode(
              File(
                'test/games/fmj/fixtures/navigation_start.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>,
      )
      ..setPreference('modernUi', true);
    game.npcs.clear();
    game.player?.x = 13;
    game.player?.y = 17;
    final vm = GameViewModel()
      ..engine = game
      ..loading = false;
    await vm.prepareModernArt();
    return vm;
  }

  testWidgets('一至四倍速，键盘短按280ms只走一格，系统重复事件不额外走路', (tester) async {
    final vm = (await tester.runAsync(model))!;
    try {
      await tester.pumpWidget(MaterialApp(home: GamePage(viewModel: vm)));
      for (var speed = 1; speed <= 4; speed++) {
        final game = vm.engine!;
        game.player?.y = 17;
        game.setPreference('runSpeed', speed);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowUp);
        await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowUp);
        vm.down(GameKey.up);
        for (var frame = 0; frame < 7; frame++) {
          vm.advanceFrame();
        }
        expect(game.player?.y, 16, reason: '$speed倍速短按不应提前触发长按');
        await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowUp);
        for (var frame = 0; frame < 15; frame++) {
          vm.advanceFrame();
        }
        expect(game.player?.y, 16, reason: '松开后不得补走');
      }
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      vm.dispose();
    }
  });

  testWidgets('长按门槛后才连走，暂停清除方向键，恢复不补发', (tester) async {
    final vm = (await tester.runAsync(model))!;
    try {
      await tester.pumpWidget(MaterialApp(home: GamePage(viewModel: vm)));
      final game = vm.engine!..setPreference('runSpeed', 4);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowUp);
      for (var frame = 0; frame < 8; frame++) {
        vm.advanceFrame();
      }
      expect(game.player?.y, 16);
      vm.advanceFrame();
      expect(game.player?.y, 15);
      vm.setPaused(true);
      for (var frame = 0; frame < 10; frame++) {
        vm.advanceFrame();
      }
      vm.setPaused(false);
      for (var frame = 0; frame < 10; frame++) {
        vm.advanceFrame();
      }
      expect(game.player?.y, 15);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowUp);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      vm.dispose();
    }
  });

  testWidgets('窄屏主菜单四项完整可见，属性、物品和系统子菜单可直接选择', (tester) async {
    final vm = (await tester.runAsync(model))!;
    try {
      for (final size in [
        const Size(315, 225),
        const Size(390, 270),
        const Size(1000, 600),
      ]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        vm.engine!.menus.clear();
        vm.engine!.openMainMenu();
        await tester.pumpWidget(
          MaterialApp(
            home: AnimatedBuilder(
              animation: vm,
              builder: (context, child) => ModernGameView(model: vm),
            ),
          ),
        );
        await tester.pump();
        for (final text in ['属性', '魔法', '物品', '系统']) {
          final target = find.text(text);
          expect(
            target.hitTestable(),
            findsOneWidget,
            reason: '$size $text 必须直接可见',
          );
          expect(
            tester.getRect(target).bottom,
            lessThanOrEqualTo(size.height - 30),
          );
        }
        for (final item in [('属性', '状态'), ('物品', '使用'), ('系统', '存储进度')]) {
          vm.action((game) {
            game.menus.clear();
            game.openMainMenu();
          });
          await tester.pump();
          await tester.tap(find.text(item.$1));
          await tester.pump();
          expect(find.text(item.$2).hitTestable(), findsWidgets);
        }
        expect(tester.takeException(), isNull);
      }
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      vm.dispose();
    }
  });
}

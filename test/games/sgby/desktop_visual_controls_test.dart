import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bbk_flutter/games/sgby/data/repositories/game_save_repository.dart';
import 'package:bbk_flutter/games/sgby/domain/models/game_definition.dart';
import 'package:bbk_flutter/games/sgby/domain/models/keyboard_bindings.dart';
import 'package:bbk_flutter/games/sgby/engine/core/native_game_session.dart';
import 'package:bbk_flutter/games/sgby/ui/core/game_keyboard.dart';
import 'package:bbk_flutter/games/sgby/ui/features/game/view_models/game_view_model.dart';
import 'package:bbk_flutter/games/sgby/ui/features/game/views/game_page.dart';
import 'support/game_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('sgby_flutter/controller'),
          (_) async => null,
        );
  });
  test('键盘冲突解除、默认别名、重开恢复和坏配置防御', () {
    final keys = KeyboardBindings();
    final q = LogicalKeyboardKey.keyQ.keyId, z = LogicalKeyboardKey.keyZ.keyId;
    expect(keys.resolve(z, GameKeyboard.defaults), GameInput.confirm);
    expect(keys.bind(GameInput.confirm, q, GameKeyboard.defaults), isTrue);
    expect(keys.resolve(q, GameKeyboard.defaults), GameInput.confirm);
    expect(keys.resolve(z, GameKeyboard.defaults), isNull);
    keys.bind(GameInput.cancel, q, GameKeyboard.defaults);
    expect(keys.resolve(q, GameKeyboard.defaults), GameInput.cancel);
    expect(
      keys.resolve(LogicalKeyboardKey.escape.keyId, GameKeyboard.defaults),
      isNull,
    );
    final restored = KeyboardBindings(jsonDecode(jsonEncode(keys.toJson())));
    expect(restored.resolve(q, GameKeyboard.defaults), GameInput.cancel);
    expect(
      KeyboardBindings({'confirm': 'bad'}).resolve(z, GameKeyboard.defaults),
      GameInput.confirm,
    );
    restored.reset();
    expect(restored.resolve(z, GameKeyboard.defaults), GameInput.confirm);
  });
  for (final platform in [TargetPlatform.macOS, TargetPlatform.windows]) {
    testWidgets('$platform 键盘映射、画风一键切换和全按钮隐藏恢复', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      final f = await tester.runAsync(() async {
        final directory = await Directory.systemTemp.createTemp(
          'sgby-desktop-controls-',
        );
        final vm = GameViewModel(
          saves: GameSaveRepository(directoryProvider: () async => directory),
        );
        await vm.initialize();
        return (vm: vm, directory: directory);
      });
      final vm = f!.vm;
      try {
        final db = loadGameDatabase(), world = db.loadPeriod(1, seed: 1);
        db.beginGame(world, 5);
        vm.session!.replaceWorld(world);
        final before = jsonEncode(world.toJson()), random = world.random.state;
        await tester.pumpWidget(MaterialApp(home: GamePage(viewModel: vm)));
        await tester.pump(const Duration(milliseconds: 32));
        expect(vm.usesBackgroundClock, isTrue);
        await tester.tap(find.byTooltip('切换彩色卡通'));
        await tester.pump(const Duration(milliseconds: 32));
        expect(vm.cartoonEnabled, isTrue);
        expect(jsonEncode(world.toJson()), before);
        expect(world.random.state, random);
        await tester.tap(find.byTooltip('键盘映射'));
        await tester.pump(const Duration(milliseconds: 250));
        expect(vm.paused, isTrue);
        await tester.tap(find.text('确认').last);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyQ);
        await tester.pump();
        expect(
          vm.keyboardAction(LogicalKeyboardKey.keyQ.keyId),
          GameInput.confirm,
        );
        await tester.tap(find.text('完成'));
        await tester.pump(const Duration(milliseconds: 250));
        expect(vm.paused, isFalse);
        await tester.tap(find.byTooltip('隐藏全部界面按钮'));
        await tester.pump();
        expect(find.byType(AppBar), findsNothing);
        expect(find.text('自动战斗'), findsNothing);
        expect(find.byTooltip('显示界面控件'), findsOneWidget);
        await tester.tap(find.byTooltip('显示界面控件'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
        await tester.tap(find.text('显示全部界面按钮'));
        await tester.pump(const Duration(milliseconds: 250));
        expect(find.byType(AppBar), findsOneWidget);
        expect(vm.controlsVisible, isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.f9);
        await tester.pump();
        expect(vm.cartoonEnabled, isFalse);
        expect(vm.session!.scene, NativeScene.strategy);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      } finally {
        vm.dispose();
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await f.directory.delete(recursive: true);
        });
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
  testWidgets('390宽手机卡通页面无顶部按钮溢出，恢复入口始终可点击', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    final f = await tester.runAsync(() async {
      final directory = await Directory.systemTemp.createTemp(
        'sgby-phone-controls-',
      );
      final vm = GameViewModel(
        saves: GameSaveRepository(directoryProvider: () async => directory),
      );
      await vm.initialize();
      return (vm: vm, directory: directory);
    });
    try {
      await tester.pumpWidget(MaterialApp(home: GamePage(viewModel: f!.vm)));
      await tester.pump(const Duration(milliseconds: 32));
      await tester.tap(find.byTooltip('切换彩色卡通'));
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('隐藏全部界面按钮'));
      await tester.pump();
      expect(find.byTooltip('显示界面控件'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    } finally {
      f!.vm.dispose();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await f.directory.delete(recursive: true);
      });
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    }
  });
}

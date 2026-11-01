import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bbk_flutter/games/sgby/data/repositories/game_save_repository.dart';
import 'package:bbk_flutter/games/sgby/ui/features/game/view_models/game_view_model.dart';
import 'package:bbk_flutter/games/sgby/ui/features/game/views/game_page.dart';
import 'support/game_database.dart';
import 'support/persistence_cleanup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('S07 系统repeat只重复方向操作，开关保持首次按下状态', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 900);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('sgby_flutter/controller'),
          (_) async => null,
        );
    final f = await tester.runAsync(() async {
      final dir = await Directory.systemTemp.createTemp('sgby-audit-input-');
      final vm = GameViewModel(
        saves: GameSaveRepository(directoryProvider: () async => dir),
      );
      await vm.initialize();
      return (dir: dir, vm: vm);
    });
    final vm = f!.vm;
    try {
      final db = loadGameDatabase(), world = db.loadPeriod(1, seed: 1);
      db.beginGame(world, 5);
      vm.session!.replaceWorld(world);
      await tester.pumpWidget(MaterialApp(home: GamePage(viewModel: vm)));
      await tester.pump(const Duration(milliseconds: 32));
      expect(vm.sgbyAutoBattleEnabled, false);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyB);
      final afterDown = vm.sgbyAutoBattleEnabled;
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.keyB);
      final afterRepeat = vm.sgbyAutoBattleEnabled;
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyB);
      expect(afterDown, true);
      expect(afterRepeat, true);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyV);
      final speedDown = vm.battleSpeedMultiplier;
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.keyV);
      final speedRepeat = vm.battleSpeedMultiplier;
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyV);
      expect(speedRepeat, speedDown);
      final x = world.cursorX;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
      expect(world.cursorX, x + 1);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
      expect(world.cursorX, x + 2);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      vm.dispose();
      await flushGamePersistence(tester, vm);
      await tester.runAsync(() => f.dir.delete(recursive: true));
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bbk_flutter/games/sgby/data/repositories/game_save_repository.dart';
import 'package:bbk_flutter/games/sgby/domain/models/game_definition.dart';
import 'package:bbk_flutter/games/sgby/engine/core/native_game_session.dart';
import 'package:bbk_flutter/games/sgby/engine/rendering/baye_draw_command.dart';
import 'package:bbk_flutter/games/sgby/ui/features/game/view_models/game_view_model.dart';
import 'support/game_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('画风、按钮显隐和键盘映射重开恢复；数字输入中切换不丢选值或回调', () async {
    final directory = await Directory.systemTemp.createTemp(
      'sgby-visual-prefs-',
    );
    final saves = GameSaveRepository(directoryProvider: () async => directory);
    final vm = GameViewModel(saves: saves);
    GameViewModel? restored;
    try {
      await vm.initialize();
      final db = loadGameDatabase(), world = db.loadPeriod(1, seed: 1);
      db.beginGame(world, 5);
      vm.session!.replaceWorld(world);
      int? value;
      vm.session!.chooseNumber(
        '出征粮草',
        1,
        10000,
        (selected) => value = selected,
        initial: 4321,
      );
      final pixels = vm.session!.canvas.snapshot(), random = world.random.state;
      vm.toggleCartoon();
      expect(vm.session!.scene, NativeScene.number);
      expect(vm.session!.canvas.snapshot(), pixels);
      expect(world.random.state, random);
      vm.setControls(false);
      vm.bindKeyboard(GameInput.confirm, LogicalKeyboardKey.keyQ.keyId);
      vm.session!.input(NativeInput.confirm);
      expect(value, 4321);
      for (var i = 0; i < 100; i++) {
        final settings = await saves.loadSettings();
        if (settings['cartoonEnabled'] == true &&
            settings['controlsVisible'] == false &&
            settings['keyboardBindings'] is Map) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      restored = GameViewModel(saves: saves);
      await restored.initialize();
      expect(restored.cartoonEnabled, isTrue);
      expect(restored.controlsVisible, isFalse);
      expect(
        restored.keyboardAction(LogicalKeyboardKey.keyQ.keyId),
        GameInput.confirm,
      );
    } finally {
      vm.dispose();
      restored?.dispose();
      await vm.flushPersistence();
      await directory.delete(recursive: true);
    }
  });
  test('菜单/数字框取消恢复完整文字层，现代指令不残留上一层选择', () {
    final db = loadGameDatabase(),
        session = NativeGameSession(loadGameDatabase());
    try {
      final world = db.loadPeriod(1, seed: 1);
      db.beginGame(world, 5);
      session.replaceWorld(world);
      final texts = session.canvas.commands
          .where((op) => op.kind == BayeDrawKind.glyph)
          .map((op) => op.text)
          .join();
      session.chooseNumber('出征粮草', 1, 1000, (value) => session.showStrategy());
      expect(
        session.canvas.commands
            .where((op) => op.kind == BayeDrawKind.glyph)
            .map((op) => op.text)
            .join(),
        contains('出征粮草'),
      );
      session.input(NativeInput.cancel);
      expect(
        session.canvas.commands
            .where((op) => op.kind == BayeDrawKind.glyph)
            .map((op) => op.text)
            .join(),
        texts,
      );
    } finally {
      session.dispose();
    }
  });
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bbk_flutter/games/sgby/data/repositories/game_save_repository.dart';
import 'package:bbk_flutter/games/sgby/domain/models/game_definition.dart';
import 'package:bbk_flutter/games/sgby/domain/models/keyboard_bindings.dart';
import 'package:bbk_flutter/games/sgby/ui/core/game_keyboard.dart';
import 'package:bbk_flutter/games/sgby/ui/features/game/view_models/game_view_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('实体按键重映射解除冲突，偏好可恢复且坏配置保留默认', () {
    final keys = KeyboardBindings();
    final q = LogicalKeyboardKey.keyQ.keyId;
    expect(
      keys.resolve(LogicalKeyboardKey.keyZ.keyId, GameKeyboard.defaults),
      GameInput.confirm,
    );
    keys.bind(GameInput.confirm, q, GameKeyboard.defaults);
    keys.bind(GameInput.cancel, q, GameKeyboard.defaults);
    final restored = KeyboardBindings(jsonDecode(jsonEncode(keys.toJson())));
    expect(restored.resolve(q, GameKeyboard.defaults), GameInput.cancel);
    expect(
      restored.resolve(LogicalKeyboardKey.keyZ.keyId, GameKeyboard.defaults),
      isNull,
    );
    expect(
      KeyboardBindings({
        'confirm': false,
      }).resolve(LogicalKeyboardKey.keyZ.keyId, GameKeyboard.defaults),
      GameInput.confirm,
    );
    restored.reset();
    expect(
      restored.resolve(LogicalKeyboardKey.keyZ.keyId, GameKeyboard.defaults),
      GameInput.confirm,
    );
  });
  test('键盘映射保存并在重启后恢复', () async {
    final directory = await Directory.systemTemp.createTemp('sgby-keyboard-');
    final saves = GameSaveRepository(directoryProvider: () async => directory);
    final vm = GameViewModel(saves: saves);
    GameViewModel? reopened;
    try {
      await vm.initialize();
      expect(vm.isReady, isTrue);
      vm.bindKeyboard(GameInput.confirm, LogicalKeyboardKey.keyQ.keyId);
      for (var i = 0; i < 100; i++) {
        final data = await saves.loadSettings();
        if ((data['keyboardBindings'] as Map?)?['confirm'] is List) break;
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      reopened = GameViewModel(saves: saves);
      await reopened.initialize();
      expect(
        reopened.keyboardAction(LogicalKeyboardKey.keyQ.keyId),
        GameInput.confirm,
      );
      expect(reopened.keyboardAction(LogicalKeyboardKey.keyZ.keyId), isNull);
    } finally {
      vm.dispose();
      reopened?.dispose();
      await vm.flushPersistence();
      await directory.delete(recursive: true);
    }
  });
}

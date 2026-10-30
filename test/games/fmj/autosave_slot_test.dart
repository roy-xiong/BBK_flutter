import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bbk_flutter/games/fmj/data/game_data.dart';
import 'package:bbk_flutter/games/fmj/data/save_repository.dart';
import 'package:bbk_flutter/games/fmj/engine/game_engine.dart';
import 'package:bbk_flutter/games/fmj/ui/game_view_model.dart';
import 'package:bbk_flutter/games/fmj/ui/modern_game_view.dart';
import 'package:bbk_flutter/games/fmj/ui/system_font_layout.dart';
import 'game_engine_test.dart' show loadData;

/// 真实文件落盘、重新初始化和读档入口串联验证，自动档不能只停留在内存。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GameData data;
  late Map<String, dynamic> initial;
  setUpAll(() async {
    data = await loadData();
    initial =
        jsonDecode(
              File(
                'test/games/fmj/fixtures/navigation_start.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
  });
  GameEngine engine() => GameEngine(data, textLayout: FlutterSystemFontLayout())
    ..restore(initial)
    ..setPreference('modernUi', true);

  test('首项为独立自动档，手动三档不覆盖，键盘A可读自动档', () {
    for (final modern in [true, false]) {
      final game = engine()..setPreference('modernUi', modern);
      game.saves[0] = Map<String, dynamic>.from(initial)..['money'] = 123;
      game.automaticSave = Map<String, dynamic>.from(initial)..['money'] = 190;
      game.openSaveMenu(load: true);
      expect(game.menus.last.items, hasLength(4));
      expect(game.menus.last.items.first, startsWith('自动存档'));
      game.press(GameKey.confirm);
      expect(game.money, 190);
      expect(game.menus, isEmpty);
      game.openSaveMenu(load: true);
      game.selectMenu(game.menus.last, 1);
      expect(game.money, 123, reason: '原手动第一档仍可通过新列表第二项读入');
      game.openSaveMenu(force: true);
      expect(game.menus.last.items, hasLength(3));
      game.selectMenu(game.menus.last, 2);
      expect(game.saves[2]?['money'], 123);
      expect(game.automaticSave?['money'], 190);
    }
  });

  test('周期在剧情中到期后，结束剧情第一帧立即落盘，重启后可读首项自动档', () async {
    final directory = Directory.systemTemp.createTempSync('fmj-auto-slot-');
    final repository = SaveRepository(directory: directory);
    final game = engine();
    game.cursor!.running = false;
    final model = GameViewModel(repository: repository)
      ..engine = game
      ..loading = false;
    GameViewModel? reopened;
    try {
      game.money = 190;
      model.advanceFrame();
      await repository.flush();
      expect((await repository.read())?['autosave']['money'], 190);
      game.operation = GameOperation('dialogue', args: [1], text: '尚未完成的剧情');
      game.money = 628;
      for (var i = 0; i < 130; i++) {
        model.advanceFrame();
      }
      await repository.flush();
      expect(
        (await repository.read())?['autosave']['money'],
        190,
        reason: '剧情中不能保存不可恢复的半途状态',
      );
      game.operation = null;
      model.advanceFrame();
      await repository.flush();
      expect((await repository.read())?['autosave']['money'], 628);
      game.openMainMenu();
      game.money = 700;
      model.setPaused(true);
      await repository.flush();
      expect(
        (await repository.read())?['autosave']['money'],
        700,
        reason: '离开/暂停时更新安全进度',
      );
      model.dispose();
      reopened = GameViewModel(repository: repository);
      await reopened.initialize();
      reopened.setPaused(true);
      final restored = reopened.engine!;
      expect(restored.money, 700);
      restored.money = 0;
      restored.openSaveMenu(load: true);
      expect(restored.menus.last.items.first, contains('自动存档'));
      restored.press(GameKey.confirm);
      expect(restored.money, 700);
      expect(restored.saves.every((s) => s == null), true);
    } finally {
      if (reopened == null) {
        model.dispose();
      } else {
        reopened.dispose();
      }
      await repository.flush();
      directory.deleteSync(recursive: true);
    }
  });

  testWidgets('彩色读档列表顶部自动档可点击，空自动档可取消', (tester) async {
    final game = engine();
    final model = GameViewModel()
      ..engine = game
      ..loading = false;
    await tester.runAsync(model.prepareModernArt);
    try {
      for (final hasSave in [false, true]) {
        game.menus.clear();
        game.automaticSave = hasSave
            ? (Map<String, dynamic>.from(initial)..['money'] = 190)
            : null;
        game.openSaveMenu(load: true);
        await tester.pumpWidget(
          MaterialApp(
            home: AnimatedBuilder(
              animation: model,
              builder: (_, _) => ModernGameView(model: model),
            ),
          ),
        );
        final first = find.text(game.saveSlotLabels(load: true).first);
        expect(first.hitTestable(), findsOneWidget);
        await tester.tap(first);
        await tester.pump();
        if (hasSave) {
          expect(game.money, 190);
          expect(game.menus, isEmpty);
        } else {
          expect(game.menus, hasLength(1));
          model.press(GameKey.cancel);
          await tester.pump();
          expect(game.menus, isEmpty);
        }
        expect(tester.takeException(), isNull);
      }
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      model.dispose();
    }
  });
}

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bbk_flutter/games/fmj/data/game_data.dart';
import 'package:bbk_flutter/games/fmj/data/save_repository.dart';
import 'package:bbk_flutter/games/fmj/engine/game_engine.dart';
import 'package:bbk_flutter/games/fmj/ui/game_page.dart';
import 'package:bbk_flutter/games/fmj/ui/game_view_model.dart';
import 'package:bbk_flutter/games/fmj/ui/system_font_layout.dart';
import 'game_engine_test.dart' show loadData;

/// 覆盖默认使用的真实提交路径，而不只断言默认高亮或直接调用choose绕过按键。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GameData data;
  setUpAll(() async => data = await loadData());
  GameEngine engine() => GameEngine(data, textLayout: FlutterSystemFontLayout())
    ..screen = 'play'
    ..intro = null
    ..preferences['modernUi'] = true;

  GameOperation open(GameEngine game, GameScript script, int index) {
    game.cursor = ScriptCursor(script)..pointer = index;
    game.update();
    expect(game.operation?.kind, 'choice');
    return game.operation!;
  }

  test('所有默认使用的四象、钥匙选择无需方向键即可按A确认原分支', () {
    var cases = 0;
    for (final script in data.scripts.values) {
      for (var index = 0; index < script.commands.length; index++) {
        final cmd = script.commands[index], options = cmd.text;
        if (cmd.opcode != 31 ||
            options is! List ||
            options.first != '取消' ||
            !options.any((v) => v is String && v.startsWith('使用'))) {
          continue;
        }
        cases++;
        final game = engine();
        // 使用同一真实会话进入并提交，确认必须跳到原第二项的地址。
        final op = open(game, script, index);
        expect(op.selected, 1);
        game.press(GameKey.confirm);
        expect(game.operation, isNull, reason: '${script.id}@${cmd.address}');
        expect(script.commands[game.cursor!.pointer].address, cmd.args.first);
      }
    }
    expect(cases, 10);
  });

  test('关闭前一段对白的确认抬起不误用道具，下一次完整按A才确认', () {
    final game = engine(), script = data.scripts['14:9']!;
    game.operation = GameOperation('dialogue', text: '前文')..next = 2;
    game.key(GameKey.confirm);
    expect(game.operation, isNull);
    final index = script.commands.indexWhere((c) => c.opcode == 31);
    final op = open(game, script, index);
    game.key(GameKey.confirm, down: false);
    expect(game.operation, same(op));
    game.press(GameKey.confirm);
    expect(game.operation, isNull);
  });

  test('杀死与放走等互斥剧情仍需明确移动选择，默认使用修复不扩大到这些分支', () {
    final game = engine(), script = data.scripts['5:18']!;
    final index = script.commands.indexWhere((c) => c.opcode == 31);
    final op = open(game, script, index);
    game.press(GameKey.confirm);
    expect(game.operation, same(op));
    game.press(GameKey.right);
    game.press(GameKey.confirm);
    expect(game.operation, isNull);
  });

  for (final keyboard in [true, false]) {
    testWidgets('${keyboard ? '回车' : '虚拟A'}无需按方向键即可使用万能钥匙', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final game = engine()
        ..preferences['manualLayout'] = true
        ..preferences['portraitControls'] = true;
      final script = data.scripts['14:9']!;
      open(game, script, script.commands.indexWhere((c) => c.opcode == 31));
      final directory = Directory.systemTemp.createTempSync('fmj-use-confirm-');
      final repository = SaveRepository(directory: directory);
      final model = GameViewModel(repository: repository)
        ..engine = game
        ..loading = false;
      await tester.runAsync(() => model.prepareModernArt());
      try {
        await tester.pumpWidget(MaterialApp(home: GamePage(viewModel: model)));
        await tester.pump();
        expect(find.textContaining('使用万能钥匙'), findsOneWidget);
        if (keyboard) {
          await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
        } else {
          await tester.tap(find.text('A').hitTestable());
        }
        await tester.pump();
        expect(game.operation, isNull);
        expect(script.commands[game.cursor!.pointer].address, 559);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        model.dispose();
        var written = false;
        repository.flush().then((_) => written = true);
        // 页面销毁提交的存档Future属于测试时间域；需同时推进真实I/O和虚拟帧。
        for (var i = 0; i < 100 && !written; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump(const Duration(milliseconds: 20));
        }
        expect(written, isTrue);
        await tester.runAsync(() => directory.delete(recursive: true));
      }
    });
  }
}

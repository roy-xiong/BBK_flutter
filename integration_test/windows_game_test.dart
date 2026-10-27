import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:bbk_flutter/games/fmj/data/save_repository.dart';
import 'package:bbk_flutter/games/fmj/engine/game_engine.dart';
import 'package:bbk_flutter/games/fmj/ui/game_page.dart';
import 'package:bbk_flutter/games/fmj/ui/game_view_model.dart';
import 'package:bbk_flutter/ui/core/app_theme.dart';
import 'package:bbk_flutter/ui/core/game_typography.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Windows 真机引擎：窗口消息、场景切换、菜单及同一行中文', (tester) async {
    final folder = await Directory.systemTemp.createTemp('bbk-windows-qa-');
    final repository = SaveRepository(directory: folder);
    final model = GameViewModel(repository: repository);
    final screenshots = <String, String>{};
    try {
      await model.initialize();
      expect(model.failure, isNull);
      await model.prepareModernArt();
      expect(model.modernArtError, isNull);
      final game = model.engine!;
      game.setPreference('modernUi', true);
      game.setPreference('runSpeed', 4);
      game.setPreference('autoBattle', true);
      game.setPreference('invincible', true);
      game.setPreference('oneHitKill', true);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: RepaintBoundary(
            key: const Key('qa-capture'),
            child: GamePage(viewModel: model),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 80));

      // 外部 Win32 探针在此期间发送 WM_NULL。即使 Dart 忙于同步逻辑，
      // 本地窗口仍必须响应，验证实际线程策略，而不是只检查 C++ 源码字符串。
      final busy = Stopwatch()..start();
      while (busy.elapsedMilliseconds < 2500) {
        game.update();
      }
      await tester.pump(const Duration(milliseconds: 80));
      var peakRss = ProcessInfo.currentRss;
      for (var stage = 0; stage < game.data.stages.length; stage++) {
        model.action((g) => g.selectStage(g.data.stages[stage]));
        for (var frame = 0; frame < 12; frame++) {
          final op = game.operation;
          if (op != null &&
              {'dialogue', 'message', 'timed'}.contains(op.kind)) {
            model.press(GameKey.confirm);
          }
          await tester.pump(const Duration(milliseconds: 40));
          expect(game.error, isEmpty);
          expect(tester.takeException(), isNull);
          if (ProcessInfo.currentRss > peakRss)
            peakRss = ProcessInfo.currentRss;
        }
      }
      model.setPaused(true);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: const RepaintBoundary(
            key: Key('qa-capture'),
            child: Scaffold(
              body: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '属性 魔法 物品 系统　柳清风 袁姑娘 小画家',
                      style: TextStyle(fontSize: 26),
                    ),
                    Text(
                      '酆都鬼城 鹤鸣山洞口　气血 690/690　Lv.49',
                      style: TextStyle(fontSize: 26),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final text = tester.widget<Text>(find.text('属性 魔法 物品 系统　柳清风 袁姑娘 小画家'));
      final context = tester.element(find.byWidget(text));
      expect(
        DefaultTextStyle.of(context).style.fontFamily,
        GameTypography.family,
      );
      final boundary =
          tester.renderObject(find.byKey(const Key('qa-capture')))
              as RenderRepaintBoundary;
      final image = await boundary.toImage();
      try {
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        if (bytes != null) {
          screenshots['windows-font-line'] = base64Encode(
            bytes.buffer.asUint8List(),
          );
        }
      } finally {
        image.dispose();
      }
      binding.reportData = {
        'screenshots': screenshots,
        'stages': game.data.stages.length,
        'peakRss': peakRss,
        'nativeProbe': 'WM_NULL',
      };
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      model.dispose();
      await repository.flush();
      await folder.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 8)));
}

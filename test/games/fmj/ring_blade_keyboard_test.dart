import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bbk_flutter/games/fmj/data/game_data.dart';
import 'package:bbk_flutter/games/fmj/engine/game_actor.dart';
import 'package:bbk_flutter/games/fmj/engine/game_engine.dart';
import 'package:bbk_flutter/games/fmj/ui/game_view_model.dart';
import 'package:bbk_flutter/games/fmj/ui/ring_blade_settings_page.dart';
import 'package:bbk_flutter/games/fmj/ui/system_font_layout.dart';
import 'game_engine_test.dart' show loadData;

/// 注入iOS平台和真实键盘遮挡高度，验证数字输入可关闭并能点到保存按钮。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GameData data;
  setUpAll(() async => data = await loadData());
  for (final entry in [
    (const Size(390, 844), 310.0),
    (const Size(320, 568), 260.0),
    (const Size(844, 390), 210.0),
  ]) {
    testWidgets('iOS ${entry.$1.width.toInt()}数字键盘上方可关闭和保存', (tester) async {
      tester.view.physicalSize = entry.$1;
      tester.view.devicePixelRatio = 1;
      final g = GameEngine(data, textLayout: FlutterSystemFontLayout())
        ..screen = 'play'
        ..intro = null
        ..players.add(GameActor.load(data, 1, 1)!);
      final model = GameViewModel()
        ..engine = g
        ..loading = false;
      try {
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(platform: TargetPlatform.iOS),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          RingBladeSettingsPage(model: model, game: g),
                    ),
                  ),
                  child: const Text('打开设置'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('打开设置'));
        await tester.pumpAndSettle();
        final field = find.byKey(const ValueKey('ring-field-maxHp'));
        await tester.ensureVisible(field);
        await tester.showKeyboard(field);
        await tester.enterText(field, '888');
        tester.view.viewInsets = FakeViewPadding(bottom: entry.$2);
        await tester.pumpAndSettle();
        final save = find.byKey(const ValueKey('save-ring-blade'));
        expect(
          tester.getRect(save).bottom,
          lessThanOrEqualTo(entry.$1.height - entry.$2),
          reason: '保存不能在键盘遮挡区',
        );
        final dismiss = find.byKey(const ValueKey('dismiss-ring-keyboard'));
        expect(dismiss, findsOneWidget);
        await tester.tap(dismiss);
        await tester.pump();
        expect(tester.testTextInput.isVisible, false);
        await tester.showKeyboard(field);
        await tester.tap(save);
        await tester.pumpAndSettle();
        expect(g.ringBlade.value('maxHp'), 888);
        expect(find.text('打开设置'), findsOneWidget);
        expect(tester.testTextInput.isVisible, false);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        model.dispose();
        tester.view.resetViewInsets();
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      }
    });
  }
  testWidgets('数字输入完成动作和拖动列表都可结束输入', (tester) async {
    final g = GameEngine(data, textLayout: FlutterSystemFontLayout());
    final model = GameViewModel()
      ..engine = g
      ..loading = false;
    try {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.iOS),
          home: RingBladeSettingsPage(model: model, game: g),
        ),
      );
      final field = find.byKey(const ValueKey('ring-field-maxHp'));
      await tester.showKeyboard(field);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(tester.testTextInput.isVisible, false);
      await tester.showKeyboard(field);
      await tester.drag(find.byType(ListView), const Offset(0, -80));
      await tester.pump();
      expect(tester.testTextInput.isVisible, false);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      model.dispose();
    }
  });
}

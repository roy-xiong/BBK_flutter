import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bbk_flutter/games/fmj/data/game_data.dart';
import 'package:bbk_flutter/games/fmj/engine/game_engine.dart';
import 'package:bbk_flutter/games/fmj/ui/game_view_model.dart';
import 'package:bbk_flutter/games/fmj/ui/modern_game_view.dart';
import 'package:bbk_flutter/games/fmj/ui/system_font_layout.dart';
import 'game_engine_test.dart' show loadData;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GameData data;
  setUpAll(() async => data = await loadData());
  GameEngine game() =>
      GameEngine(data, textLayout: FlutterSystemFontLayout())
        ..preferences['modernUi'] = true;
  testWidgets('键盘切换时标题选项有明确的选中语义和实心高亮', (tester) async {
    final g = game()..screen = 'title';
    final m = GameViewModel()
      ..engine = g
      ..loading = false;
    await tester.runAsync(() => m.prepareModernArt());
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: AnimatedBuilder(
            animation: m,
            builder: (_, _) => ModernGameView(model: m),
          ),
        ),
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey('fmj-title-selected-0')),
        findsOneWidget,
      );
      m.press(GameKey.down);
      await tester.pump();
      expect(g.titleSelection, 1);
      expect(
        find.byKey(const ValueKey('fmj-title-selected-1')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('fmj-title-selected-0')), findsNothing);
      await tester.tap(find.text('继续故事'));
      await tester.pump();
      expect(g.menus.last.kind, 'load');
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      m.dispose();
    }
  });
  test('彩色启动画面已经显示菜单时方向键与A也可选继续故事', () {
    final g = game();
    expect(g.screen, 'intro');
    g.press(GameKey.down);
    expect(g.titleSelection, 1);
    g.press(GameKey.confirm);
    expect(g.menus.last.kind, 'load');
  });
  testWidgets('320x230标题两项都能显示，切换不溢出', (tester) async {
    tester.view.physicalSize = const Size(320, 230);
    tester.view.devicePixelRatio = 1;
    final g = game()..screen = 'title', m = GameViewModel()..loading = false;
    m.engine = g;
    await tester.runAsync(() => m.prepareModernArt());
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: AnimatedBuilder(
            animation: m,
            builder: (_, _) => ModernGameView(model: m),
          ),
        ),
      );
      await tester.pump();
      for (final label in ['新的故事', '继续故事']) {
        expect(find.text(label), findsOneWidget);
        final r = tester.getRect(find.text(label));
        expect(r.top, greaterThanOrEqualTo(0));
        expect(r.bottom, lessThanOrEqualTo(174));
      }
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      m.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    }
  });
  test('片尾原动画的进度可完整推进，绘制改造不能写原剧情资源', () {
    final movie = GameMovie(data, 1, 4);
    final before = jsonEncode(movie.headers);
    var frames = 0;
    while (movie.update()) {
      frames++;
      expect(frames, lessThan(1000));
    }
    expect(frames, greaterThan(20));
    expect(jsonEncode(movie.headers), before);
  });
}

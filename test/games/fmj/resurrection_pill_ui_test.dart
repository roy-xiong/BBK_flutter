import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bbk_flutter/games/fmj/data/game_data.dart';
import 'package:bbk_flutter/games/fmj/engine/game_engine.dart';
import 'package:bbk_flutter/games/fmj/engine/game_actor.dart';
import 'package:bbk_flutter/games/fmj/ui/game_view_model.dart';
import 'package:bbk_flutter/games/fmj/ui/modern_game_view.dart';
import 'package:bbk_flutter/games/fmj/ui/system_font_layout.dart';
import 'game_engine_test.dart' show loadData;

/// 真实彩色场景/对白框在小屏与桌面上渲染，触屏使用与拒绝均经过正式选择入口。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GameData data;
  setUpAll(() async {
    data = await loadData();
    await (FontLoader('BBK CJK')
          ..addFont(rootBundle.load('assets/fonts/NotoSansCJKsc-Regular.otf')))
        .load();
  });
  testWidgets('复活询问和人物对白窄屏不溢出，拒绝不扣药、使用恢复人物且无双影', (tester) async {
    final g = GameEngine(data, textLayout: FlutterSystemFontLayout())
      ..screen = 'play'
      ..intro = null
      ..map = data.maps['1:46']
      ..screenX = 6
      ..screenY = 3
      ..sceneName = '鹤鸣山洞口'
      ..players.addAll(
        [1, 2].map(
          (i) => GameActor.load(data, 1, i)!
            ..x = 10
            ..y = 7,
        ),
      );
    final model = GameViewModel()
      ..engine = g
      ..loading = false;
    final script = data.scripts['14:8']!;
    void choice() {
      g.cursor = ScriptCursor(script)..pointer = script.addresses[9020]!;
      g.operation = null;
      g.update();
    }

    g.addGoods('11:16');
    choice();
    await tester.runAsync(() => model.prepareModernArt());
    final key = GlobalKey();
    Future<void> capture(String name) async {
      if (Platform.environment['FMJ_RESURRECTION_ART_OUTPUT'] == null) return;
      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject() as RenderRepaintBoundary;
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        if (bytes != null) {
          final dir = Directory(
            Platform.environment['FMJ_RESURRECTION_ART_OUTPUT']!,
          );
          await dir.create(recursive: true);
          await File(
            '${dir.path}/$name.png',
          ).writeAsBytes(bytes.buffer.asUint8List());
        }
        image.dispose();
      });
    }

    try {
      for (final size in [
        const Size(320, 230),
        const Size(640, 384),
        const Size(1280, 768),
      ]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(
              fontFamily: 'BBK CJK',
              brightness: Brightness.dark,
            ),
            home: RepaintBoundary(
              key: key,
              child: Scaffold(
                body: AnimatedBuilder(
                  animation: model,
                  builder: (_, _) => ModernGameView(model: model),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text(GameResurrectionPill.prompt), findsOneWidget);
        expect(find.textContaining('使用丹药'), findsOneWidget);
        expect(find.textContaining('不使用'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await capture('choice-${size.width.toInt()}');
      }
      await tester.tap(find.textContaining('不使用'));
      await tester.pump();
      expect(g.inventory['11:16'], 1);
      expect(g.players, hasLength(2));
      model.action((g) => choice());
      await tester.pump();
      await tester.tap(find.textContaining('使用丹药'));
      await tester.pump();
      model.action((g) {
        for (var i = 0; i < 200; i++) {
          g.update();
          if (g.operation?.kind == 'dialogue' && g.operation?.address == 9055) {
            break;
          }
          if (g.operation != null) g.press(GameKey.confirm);
        }
      });
      await tester.pumpAndSettle();
      expect(g.operation?.address, 9055);
      expect(g.players.where((p) => p.index == 3), hasLength(1));
      expect(g.inventory['11:16'] ?? 0, 0);
      expect(
        g.partyFollow.worldActors.where((p) => p.actor.name == '袁萍芷'),
        hasLength(1),
      );
      expect(find.text('袁萍芷'), findsWidgets);
      expect(tester.takeException(), isNull);
      await capture('revived-dialogue');
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      model.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    }
  });
}

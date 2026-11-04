import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bbk_flutter/games/fmj/data/game_data.dart';
import 'package:bbk_flutter/games/fmj/data/save_repository.dart';
import 'package:bbk_flutter/games/fmj/engine/game_engine.dart';
import 'package:bbk_flutter/games/fmj/engine/game_actor.dart';
import 'package:bbk_flutter/games/fmj/ui/game_view_model.dart';
import 'package:bbk_flutter/games/fmj/ui/modern_art.dart';
import 'package:bbk_flutter/games/fmj/ui/ring_blade_settings_page.dart';
import 'package:bbk_flutter/games/fmj/ui/system_font_layout.dart';
import 'game_engine_test.dart' show loadData;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GameData data;
  setUpAll(() async {
    data = await loadData();
    await (FontLoader('BBK CJK')
          ..addFont(rootBundle.load('assets/fonts/NotoSansCJKsc-Regular.otf')))
        .load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  GameEngine game() => GameEngine(data, textLayout: FlutterSystemFontLayout())
    ..screen = 'play'
    ..intro = null
    ..map = data.maps['1:2']
    ..cursor = (ScriptCursor(data.scripts['2:12']!)..running = false)
    ..players.add(
      GameActor.load(data, 1, 1)!
        ..x = 11
        ..y = 8,
    );
  test('偏好与已应用加成写盘重开，默认敌方异常关闭且图标真实存在', () async {
    final dir = await Directory.systemTemp.createTemp('fmj-ring-prefs-');
    final repository = SaveRepository(directory: dir),
        model = GameViewModel(repository: SaveRepository(directory: dir))
          ..engine = game()
          ..loading = false;
    final g = model.engine!;
    g.addGoods('7:33');
    g.equip(g.player!, '7:33');
    g.setPreference('ringBlade', {
      'attack': 740,
      'mpDrain': 350,
      'enemyPoison': true,
    });
    final attack = g.player!.attack;
    model.engine!.saves[0] = g.snapshot();
    await model.persist(rethrowOnFailure: true);
    final reopened = GameViewModel(repository: repository);
    try {
      await reopened.initialize();
      expect(reopened.engine!.ringBlade.value('attack'), 740);
      expect(reopened.engine!.ringBlade.enabled('enemyPoison'), true);
      expect(reopened.engine!.ringBlade.enabled('enemySleep'), false);
      reopened.engine!.restore(reopened.engine!.saves[0]!);
      expect(reopened.engine!.player!.attack, attack);
      expect(reopened.engine!.goods('7:33')!.byte(5), 33);
      expect(
        data.image(9, 7, 33)?.frames.first.pixels.any((v) => v != 0),
        true,
      );
      final art = await ModernArt.load();
      try {
        expect(art.sprites['goods:7:33/0']?.rect.width, 256);
      } finally {
        art.dispose();
      }
    } finally {
      reopened.dispose();
      model.dispose();
      await repository.flush();
    }
  });
  for (final size in [const Size(360, 780), const Size(1280, 900)]) {
    testWidgets('设置页${size.width.toInt()}宽可编辑与保存，无溢出', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final model = GameViewModel()
        ..engine = game()
        ..loading = false;
      final boundary = GlobalKey();
      await tester.runAsync(() => model.prepareModernArt());
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            useMaterial3: true,
            fontFamily: 'BBK CJK',
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xffbfa66c),
              brightness: Brightness.dark,
            ),
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => RepaintBoundary(
                      key: boundary,
                      child: RingBladeSettingsPage(
                        model: model,
                        game: model.engine!,
                      ),
                    ),
                  ),
                ),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final capture =
            boundary.currentContext!.findRenderObject()
                as RenderRepaintBoundary;
        final image = await capture.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        if (bytes != null) {
          final directory = Directory(
            Platform.environment['FMJ_RING_ART_OUTPUT'] ?? 'build/validation',
          );
          await directory.create(recursive: true);
          await File(
            '${directory.path}/settings-${size.width.toInt()}.png',
          ).writeAsBytes(bytes.buffer.asUint8List());
        }
        image.dispose();
      });
      final attack = find.byKey(const ValueKey('ring-field-attack'));
      await tester.ensureVisible(attack);
      await tester.enterText(attack, '777');
      await tester.tap(find.byKey(const ValueKey('save-ring-blade')));
      await tester.pumpAndSettle();
      expect(model.engine!.ringBlade.value('attack'), 777);
      expect(tester.takeException(), isNull);
      model.dispose();
    });
  }
}

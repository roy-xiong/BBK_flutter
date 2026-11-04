import 'dart:io';
import 'dart:convert';
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
import 'package:bbk_flutter/games/fmj/ui/modern_art.dart';
import 'package:bbk_flutter/games/fmj/ui/modern_scene.dart';
import 'package:bbk_flutter/games/fmj/ui/modern_ending_scene.dart';
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
  testWidgets('以正式绘制器导出水墨片尾，不改变原电影的帧和时序', (tester) async {
    await tester.runAsync(() async {
      final g = GameEngine(data, textLayout: FlutterSystemFontLayout())
        ..screen = 'play'
        ..intro = null
        ..map = data.maps['2:7']
        ..cursor = (ScriptCursor(data.scripts['2:18']!)..running = false);
      final movie = GameMovie(data, 1, 4);
      g.operation = GameOperation('movie', args: [1, 4, 0, 0, 0])
        ..movie = movie;
      final art = await ModernArt.load();
      try {
        var index = 0, previous = -1.0;
        final folder = Directory('build/validation/ending-review/frames');
        if (Platform.environment['FMJ_EXPORT_ENDING'] == '1') {
          await folder.create(recursive: true);
        }
        do {
          final before = jsonEncode(movie.active),
              p = ModernEndingScene.progress(movie);
          expect(p, greaterThanOrEqualTo(previous));
          previous = p;
          final rec = ui.PictureRecorder();
          ModernScenePainter(g, art).paint(Canvas(rec), const Size(1280, 768));
          final picture = rec.endRecording();
          final image = await picture.toImage(1280, 768);
          try {
            if (index == 35) {
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.rawRgba,
              );
              expect(
                bytes!.getUint8(0),
                greaterThan(190),
                reason: '片尾使用宣纸画面，不落回旧地图/像素动画',
              );
            }
            if (Platform.environment['FMJ_EXPORT_ENDING'] == '1') {
              final png = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await File(
                '${folder.path}/end-${index.toString().padLeft(3, '0')}.png',
              ).writeAsBytes(png!.buffer.asUint8List());
            }
          } finally {
            image.dispose();
            picture.dispose();
          }
          expect(jsonEncode(movie.active), before);
          index++;
        } while (movie.update());
        expect(previous, greaterThan(.97));
        expect(index, greaterThan(50));
      } finally {
        art.dispose();
      }
    });
  });
  testWidgets('标题状态与待审尾声场景使用真实游戏界面导出', (tester) async {
    final g = GameEngine(data, textLayout: FlutterSystemFontLayout())
      ..screen = 'title'
      ..intro = null;
    final m = GameViewModel()
      ..engine = g
      ..loading = false;
    await tester.runAsync(() => m.prepareModernArt());
    final key = GlobalKey();
    Future<void> show(String name) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(fontFamily: 'BBK CJK', brightness: Brightness.dark),
          home: AnimatedBuilder(
            animation: m,
            builder: (_, _) => RepaintBoundary(
              key: key,
              child: Scaffold(body: ModernGameView(model: m)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      if (Platform.environment['FMJ_EXPORT_ENDING'] == '1') {
        await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject() as RenderRepaintBoundary;
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            'build/validation/ending-review/$name.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
    }

    try {
      tester.view.physicalSize = const Size(960, 640);
      tester.view.devicePixelRatio = 1;
      await show('title-new');
      m.press(GameKey.down);
      await show('title-continue');
      tester.view.physicalSize = const Size(320, 230);
      await show('title-phone');
      tester.view.physicalSize = const Size(1280, 768);
      final path = File('build/validation/full-story-pickups-snapshot.json');
      if (path.existsSync()) {
        g.restore(GameData.decodeObject(path.readAsStringSync()));
        g.preferences['costumeHeroes'] = true;
        g.sceneName = '无机阁';
        // 仅供待审文案预览，正式剧情数据尚未加入袁萍芷的尾声分支。
        g.npcs[22] = GameActor.load(data, 2, 7)!
          ..x = 13
          ..y = 8
          ..direction = 4;
        g.player!.direction = 2;
        g.operation = GameOperation(
          'dialogue',
          args: [3],
          text: '能有今日的清闲，是好事。只是别让小梅总替你操心。',
        );
        g.operation!.scriptId = '2:18';
        g.render();
        await show('epilogue-draft');
      }
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      m.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    }
  });
}

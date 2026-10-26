import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bbk_flutter/games/fmj/engine/game_actor.dart';
import 'package:bbk_flutter/games/fmj/engine/game_engine.dart';
import 'package:bbk_flutter/games/fmj/ui/game_page.dart';
import 'package:bbk_flutter/games/fmj/ui/game_view_model.dart';
import 'package:bbk_flutter/games/fmj/ui/modern_art.dart';
import 'package:bbk_flutter/games/fmj/ui/modern_map_camera.dart';
import 'package:bbk_flutter/games/fmj/ui/modern_scene.dart';
import 'package:bbk_flutter/games/fmj/ui/system_font_layout.dart';
import 'game_engine_test.dart' show loadData;

/// 完整审核图只在指定的云端回归中导出，不在本地编译应用，也不拖慢常规打包。
void main() {
  if (Platform.environment['FMJ_EXPORT_FULL_ART_REVIEW'] != '1') return;
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    '以生产 Painter 导出全部 83 张完整地图，覆盖全部室内和洞窟',
    (tester) async {
      await tester.runAsync(() async {
        final data = await loadData();
        final art = await ModernArt.load();
        final folder = Directory('build/validation/full-maps')
          ..createSync(recursive: true);
        final index = <Map<String, Object>>[];
        try {
          final game = GameEngine(data, textLayout: FlutterSystemFontLayout())
            ..screen = 'play'
            ..intro = null;
          game.players.clear();
          game.npcs.clear();
          for (final map in data.maps.values) {
            game.map = map;
            final recorder = ui.PictureRecorder(), canvas = ui.Canvas(recorder);
            // 每格输出 48px；镜头、图集和排序复用游戏实现，按不重叠区域拼接全景。
            canvas.scale(1.5);
            for (var top = 0; top < map.height; top += 6) {
              for (var left = 0; left < map.width; left += 12) {
                final camera = ModernMapCamera(
                  mapWidth: map.width,
                  mapHeight: map.height,
                  playerX: left + 6,
                  playerY: top + 3,
                  wide: true,
                );
                canvas.save();
                canvas.clipRect(
                  ui.Rect.fromLTWH(
                    left * 32.0,
                    top * 32.0,
                    math.min(12, map.width - left) * 32.0,
                    math.min(6, map.height - top) * 32.0,
                  ),
                );
                canvas.translate(camera.left * 32.0, camera.top * 32.0);
                ModernScenePainter(
                  game,
                  art,
                  cameraOverride: camera,
                  overview: true,
                ).paint(canvas, const ui.Size(640, 384));
                canvas.restore();
              }
            }
            final picture = recorder.endRecording();
            final image = await picture.toImage(
              map.width * 48,
              map.height * 48,
            );
            final png = await image.toByteData(format: ui.ImageByteFormat.png);
            expect(png, isNotNull, reason: map.id);
            final file = 'map-${map.id.replaceAll(':', '-')}.png';
            File(
              '${folder.path}/$file',
            ).writeAsBytesSync(png!.buffer.asUint8List());
            image.dispose();
            picture.dispose();
            index.add({
              'id': map.id,
              'name': map.name,
              'tileset': map.tiles,
              'width': map.width,
              'height': map.height,
              'file': file,
              'pixelsPerTile': 48,
              'category': [3, 5, 6, 7].contains(map.tiles)
                  ? 'interior'
                  : map.tiles == 8
                  ? 'cave'
                  : 'outdoor',
            });
          }
          expect(index.length, 83);
          expect(index.where((m) => m['category'] == 'interior').length, 26);
          expect(index.where((m) => m['category'] == 'cave').length, 11);
          File(
            '${folder.path}/index.json',
          ).writeAsStringSync(jsonEncode(index));
        } finally {
          art.dispose();
        }
      });
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );

  testWidgets('导出带系统中文字体的手机与桌面完整界面审核图', (tester) async {
    final data = (await tester.runAsync(loadData))!;
    final initial =
        jsonDecode(
              File(
                'test/games/fmj/fixtures/navigation_start.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    await tester.runAsync(() async {
      final chinese = FontLoader('ArtReviewCJK');
      chinese.addFont(
        Future.value(
          ByteData.sublistView(
            File(
              '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',
            ).readAsBytesSync(),
          ),
        ),
      );
      await chinese.load();
      // 测试进程把默认字体设为 Ahem；仅此导出进程用宿主中文字体替换它。
      for (final family in ['Ahem', 'Roboto']) {
        final defaultFont = FontLoader(family);
        defaultFont.addFont(
          Future.value(
            ByteData.sublistView(
              File(
                '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',
              ).readAsBytesSync(),
            ),
          ),
        );
        await defaultFont.load();
      }
      final icons = FontLoader('MaterialIcons');
      icons.addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await icons.load();
    });
    final model = GameViewModel()
      ..engine = GameEngine(data, textLayout: FlutterSystemFontLayout())
      ..loading = false;
    await tester.runAsync(model.prepareModernArt);
    expect(model.modernArt, isNotNull, reason: '${model.modernArtError}');
    final game = model.engine!;
    final folder = Directory('build/validation/review-ui')
      ..createSync(recursive: true);
    final index = <Map<String, Object>>[];
    try {
      for (final size in [const Size(390, 844), const Size(1000, 650)]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        for (final mode in [
          'hall',
          'bedroom',
          'courtyard',
          'pavilion',
          'village',
          'alchemy',
          'disciples',
          'lihu',
          'cave',
          'cave-mouth',
          'cave-collapsed',
          'lantern-entries',
          'lantern-return',
          'battle',
          'battle-couple',
        ]) {
          game.restore(initial);
          game.setPreference('modernUi', true);
          game.screen = 'play';
          game.intro = null;
          game.menus.clear();
          final scene = switch (mode) {
            'bedroom' => ('2:1', '师傅居', 10, 9),
            'courtyard' => ('1:1', '三清宫', 23, 12),
            'pavilion' => ('1:12', '观星亭', 9, 9),
            'village' => ('1:23', '忘忧村', 12, 15),
            'alchemy' => ('2:6', '三清宫丹房', 10, 12),
            'disciples' => ('2:4', '普通弟子居', 10, 9),
            'lihu' => ('2:20', '李虎家主房', 10, 11),
            'cave' => ('3:1', '伏魔洞', 10, 10),
            'cave-mouth' || 'cave-collapsed' => ('1:6', '伏魔洞口', 10, 6),
            'lantern-entries' => ('3:1', '伏魔洞', 17, 11),
            'lantern-return' => ('3:2', '灯洞1', 12, 6),
            _ => null,
          };
          if (scene != null) {
            game.map = data.maps[scene.$1];
            game.sceneName = scene.$2;
            game.npcs.clear();
            game.player?.x = scene.$3;
            game.player?.y = scene.$4;
          }
          if (mode == 'cave-collapsed') {
            for (var id = 1; id <= 4; id++) {
              final rock = GameActor.load(data, 4, 10);
              expect(rock, isNotNull);
              game.npcs[id] = rock!
                ..x = id.isOdd ? 6 : 7
                ..y = id <= 2 ? 3 : 4;
            }
          }
          if (mode == 'battle' || mode == 'battle-couple') {
            for (final id in [2, 3]) {
              game.players.add(GameActor.load(data, 1, id)!);
            }
            game.battle = GameBattle(
              game,
              monsters: mode == 'battle-couple' ? [21, 10] : [9, 11],
              background: [2, 2, 2],
              randomFight: true,
            );
          }
          model.action((_) {});
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(
                brightness: Brightness.dark,
                fontFamily: 'ArtReviewCJK',
              ),
              home: RepaintBoundary(
                key: const Key('art-review-ui'),
                child: GamePage(viewModel: model),
              ),
            ),
          );
          await tester.pump();
          await tester.pump();
          expect(tester.takeException(), isNull, reason: '$mode $size');
          final boundary =
              tester.renderObject(find.byKey(const Key('art-review-ui')))
                  as RenderRepaintBoundary;
          await tester.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: 2);
            final png = await image.toByteData(format: ui.ImageByteFormat.png);
            final file = '$mode-${size.width.toInt()}.png';
            File(
              '${folder.path}/$file',
            ).writeAsBytesSync(png!.buffer.asUint8List());
            image.dispose();
            index.add({
              'mode': mode,
              'width': size.width.toInt(),
              'height': size.height.toInt(),
              'file': file,
            });
          });
        }
      }
      File('${folder.path}/index.json').writeAsStringSync(jsonEncode(index));
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      // GamePage 在卸载时拥有并释放传入的会话，此处不再重复释放。
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
}

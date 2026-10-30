import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bbk_flutter/games/fmj/engine/game_engine.dart';
import 'package:bbk_flutter/games/fmj/ui/modern_art.dart';
import 'package:bbk_flutter/games/fmj/ui/modern_maze_floor.dart';
import 'package:bbk_flutter/games/fmj/ui/modern_opening_scene.dart';
import 'package:bbk_flutter/games/fmj/ui/system_font_layout.dart';
import 'game_engine_test.dart' show loadData;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('迷宫内外转角有圆角，但走路判断和格心不变', () {
    final cells = <(int, int)>{(1, 0), (1, 1), (2, 1)};
    final before = Set.of(cells);
    final path = ModernMazeFloor.build(
      width: 3,
      height: 3,
      walkable: (x, y) => cells.contains((x, y)),
    );
    expect(
      path.contains(const Offset(1.005, .005)),
      false,
      reason: '原外角应有小圆角，不是完整直角方块',
    );
    expect(path.contains(const Offset(1.5, .5)), true);
    expect(path.contains(const Offset(1.5, 1.5)), true);
    expect(path.contains(const Offset(2.5, 1.5)), true);
    expect(path.contains(const Offset(.5, 1.5)), false);
    expect(cells, before, reason: '绘制轮廓不能修改逻辑地图');
  });

  test('全量重绘已经撤回，既有帧恢复基线，仅保留明确提出的睡莲与坐客修改', () {
    final hd =
        jsonDecode(
              File('assets/fmj/modern/enhanced-art.json').readAsStringSync(),
            )
            as Map;
    final sources =
        jsonDecode(
              File(
                'assets/fmj/modern/enhanced-art-sources.json',
              ).readAsStringSync(),
            )
            as Map;
    final proof =
        jsonDecode(
              File(
                'tool/art_sources/art-rollback-v16/baseline-verification.json',
              ).readAsStringSync(),
            )
            as Map;
    expect(hd.containsKey('artSweepV15'), false);
    expect(hd['targetedArtV15']['globalSweepReverted'], true);
    expect(proof['unchangedFrameCount'], 2034);
    expect(proof['decodedImageBytes'], lessThan(256 * 1024 * 1024));
    expect(
      (sources['frames'] as Map).values.where(
        (s) => s['transform'] == 'original-contour-native-material',
      ),
      isNotEmpty,
      reason: '用户已取消全量重绘，原有花草、柱子等映射必须恢复',
    );
    expect(
      (hd['frames'] as Map).keys.where(
        (key) => (key as String).startsWith('sweep-v15:'),
      ),
      isEmpty,
    );
    for (var tile = 94; tile <= 101; tile++) {
      expect(
        hd['frames']['structure:1:$tile/0'],
        hd['frames']['review-v11:lotus/0'],
      );
    }
    for (final id in ['2:21', '2:22', '2:26']) {
      final guests = (hd['decorations'][id] as List).where(
        (b) => b['key'] == 'review-v14:seated-guest-bench',
      );
      expect(guests, hasLength(2));
      for (final guest in guests) {
        expect(guest['visualHeight'], lessThan(1.6), reason: '坐客不能比当前柳清风站立还高');
      }
    }
  });

  testWidgets('正式开场画面使用彩绘，不改原SRS叠帧与剧情状态', (tester) async {
    await tester.runAsync(() async {
      final data = await loadData();
      final game = GameEngine(data, textLayout: FlutterSystemFontLayout())
        ..preferences['modernUi'] = true;
      game.startNewGame();
      for (var i = 0; i < 100 && !ModernOpeningScene.supports(game); i++) {
        game.update();
      }
      expect(ModernOpeningScene.supports(game), true);
      final art = await ModernArt.load();
      try {
        expect(art.backgrounds, contains('opening'));
        final movie = game.operation!.movie!;
        final original = movie.active.map((a) => List<int>.of(a)).toList();
        for (var sample = 0; sample < 3; sample++) {
          final index = sample * (movie.headers.length - 1) ~/ 2;
          movie.active
            ..clear()
            ..add([index, movie.headers[index][2], movie.headers[index][3]]);
          final state = jsonEncode(movie.active);
          final recorder = ui.PictureRecorder();
          expect(ModernOpeningScene.draw(Canvas(recorder), game, art), true);
          final picture = recorder.endRecording();
          final image = await picture.toImage(640, 384);
          try {
            if (Platform.environment['FMJ_EXPORT_APPROVED_ART'] == '1') {
              final folder = Directory('build/validation/art-sweep-v15')
                ..createSync(recursive: true);
              final png = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              File(
                '${folder.path}/opening-$sample.png',
              ).writeAsBytesSync(png!.buffer.asUint8List());
            }
          } finally {
            image.dispose();
            picture.dispose();
          }
          expect(jsonEncode(movie.active), state);
        }
        movie.active
          ..clear()
          ..addAll(original);
      } finally {
        art.dispose();
      }
    });
  });
}

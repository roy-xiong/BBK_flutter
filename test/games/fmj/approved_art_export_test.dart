import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bbk_flutter/games/fmj/engine/game_actor.dart';
import 'package:bbk_flutter/games/fmj/engine/game_engine.dart';
import 'package:bbk_flutter/games/fmj/ui/modern_art.dart';
import 'package:bbk_flutter/games/fmj/ui/modern_map_camera.dart';
import 'package:bbk_flutter/games/fmj/ui/modern_scene.dart';
import 'package:bbk_flutter/games/fmj/ui/modern_world_objects.dart';
import 'package:bbk_flutter/games/fmj/ui/system_font_layout.dart';
import 'game_engine_test.dart' show loadData;

/// 在云端使用真正的生产 Painter 导出验收场景，不能拿静态效果稿当运行结果。
void main() {
  if (Platform.environment['FMJ_EXPORT_APPROVED_ART'] != '1') return;
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('导出已审核美术在游戏中的完整地图、蛇妖和亮灭灯', (tester) async {
    await tester.runAsync(() async {
      final data = await loadData();
      final art = await ModernArt.load();
      final folder = Directory('build/validation/approved-art')
        ..createSync(recursive: true);
      final actors =
          jsonDecode(
                File(
                  'test/games/fmj/fixtures/approved_map_actors.json',
                ).readAsStringSync(),
              )
              as Map;
      final game = GameEngine(data, textLayout: FlutterSystemFontLayout())
        ..screen = 'play'
        ..intro = null;
      Future<void> save(
        ui.Picture picture,
        int width,
        int height,
        String name,
      ) async {
        final image = await picture.toImage(width, height);
        try {
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          expect(png, isNotNull);
          File(
            '${folder.path}/$name.png',
          ).writeAsBytesSync(png!.buffer.asUint8List());
        } finally {
          image.dispose();
          picture.dispose();
        }
      }

      try {
        for (final id in ['2:7', '2:8', '1:7', '1:32', '1:22', '1:23', '3:8']) {
          final map = data.maps[id]!;
          game.map = map;
          game.npcs.clear();
          for (final row in (actors[id] as List)) {
            final values = Map<String, dynamic>.from(row as Map);
            final actor = GameActor.load(
              data,
              values['type'] as int,
              values['index'] as int,
            );
            if (actor == null) continue;
            actor.x = values['x'] as int;
            actor.y = values['y'] as int;
            actor.direction = values['direction'] as int? ?? actor.direction;
            game.npcs[game.npcs.length + 1] = actor;
          }
          if (id == '1:23') {
            game.npcs[39] = GameActor.load(data, 4, 24)!
              ..x = 15
              ..y = 6;
            game.npcs[40] = GameActor.load(data, 4, 23)!
              ..x = 15
              ..y = 7;
          }
          final recorder = ui.PictureRecorder();
          final canvas = Canvas(recorder)..scale(1.5);
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
                Rect.fromLTWH(
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
                showActorsInOverview: true,
              ).paint(canvas, const Size(640, 384));
              canvas.restore();
            }
          }
          await save(
            recorder.endRecording(),
            map.width * 48,
            map.height * 48,
            'map-${id.replaceAll(':', '-')}',
          );
        }
        for (final lit in [true, false]) {
          final actor = GameActor.load(data, 4, 7)!
            ..state = lit ? 4 : 0
            ..step = lit ? 1 : 0;
          final recorder = ui.PictureRecorder();
          final canvas = Canvas(recorder);
          ModernWorldObjects.draw(
            canvas,
            game,
            actor,
            art,
            const Offset(20, 20),
            256,
            null,
          );
          await save(
            recorder.endRecording(),
            300,
            300,
            lit ? 'lamp-on' : 'lamp-off',
          );
        }
        expect(
          art.sprites.keys,
          containsAll([
            'mechanism:23/0',
            'mechanism:24/0',
            'mechanism:chest-open/0',
            'mechanism:chest-closed/0',
          ]),
        );
      } finally {
        art.dispose();
      }
    });
  }, timeout: const Timeout(Duration(minutes: 3)));
}

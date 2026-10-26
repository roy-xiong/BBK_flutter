import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bbk_flutter/games/fmj/engine/game_engine.dart';
import 'package:bbk_flutter/games/fmj/ui/modern_art.dart';
import 'package:bbk_flutter/games/fmj/ui/modern_map_camera.dart';
import 'package:bbk_flutter/games/fmj/ui/modern_scene.dart';
import 'package:bbk_flutter/games/fmj/ui/system_font_layout.dart';
import 'game_engine_test.dart' show loadData;

/// 本地结构复核导出：使用真实初始化脚本及 NPC，不能再以清空角色的背景图证明完整。
void main() {
  if (Platform.environment['FMJ_STRUCTURE_REVIEW'] != '1') return;
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('导出83地图的实际机关、隐藏物件位置与全景', (tester) async {
    await tester.runAsync(() async {
      final font = FontLoader('StructureReviewCJK');
      font.addFont(
        Future.value(
          ByteData.sublistView(
            File('/System/Library/Fonts/STHeiti Medium.ttc').readAsBytesSync(),
          ),
        ),
      );
      await font.load();
      final data = await loadData();
      final art = await ModernArt.load();
      final guide =
          jsonDecode(
                File('assets/fmj/game/FmjGuideData.json').readAsStringSync(),
              )
              as Map;
      final scripts = (guide['scripts'] as List).cast<Map>();
      final folder = Directory('build/structure-review')
        ..createSync(recursive: true);
      final index = <Map<String, dynamic>>[];
      try {
        for (final map in data.maps.values) {
          final owners = scripts
              .where((s) => (s['maps'] as List).contains(map.id))
              .toList();
          final named = owners.where((s) => s['name'] == map.name);
          final populated = named.where(
            (s) => (s['commands'] as List).any((c) => c['op'] == 38),
          );
          final owner = populated.isNotEmpty
              ? populated.first
              : named.isNotEmpty
              ? named.first
              : owners.isNotEmpty
              ? owners.first
              : null;
          final matchingStages = data.stages.where(
            (stage) =>
                stage['mapId'] == map.id && stage['scriptId'] == owner?['id'],
          );
          final stage = matchingStages.isNotEmpty
              ? matchingStages.first
              : <String, dynamic>{
                  'mapId': map.id,
                  'scriptId': owner?['id'] ?? '2:2',
                  'x': map.width ~/ 2,
                  'y': map.height ~/ 2,
                  'flags': <int>[],
                  'actors': [1],
                  'goods': [],
                  'equipment': [],
                  'scene': map.name,
                  'title': map.name,
                  'level': 9,
                };
          final game = GameEngine(
            data,
            textLayout: FlutterSystemFontLayout(),
            random: math.Random(24),
          )..selectStage(stage);
          for (var tick = 0; tick < 150; tick++) {
            game.update();
            if (game.map?.id != map.id || game.battle != null) break;
            if (game.operation != null &&
                !['timed', 'delay'].contains(game.operation?.kind)) {
              break;
            }
            if (game.operation == null && game.cursor?.running != true) break;
          }
          final matched = game.map?.id == map.id;
          if (!matched) {
            game.map = map;
            game.npcs.clear();
          }
          game.battle = null;
          game.setPreference('wideView', true);
          final actors = [
            for (final e in game.npcs.entries)
              {'slot': e.key, ...e.value.toJson()},
          ];
          game.players.clear();
          final before = jsonEncode(game.snapshot());
          final recorder = ui.PictureRecorder(), canvas = ui.Canvas(recorder);
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
                showActorsInOverview: true,
                textStyle: const TextStyle(fontFamily: 'StructureReviewCJK'),
              ).paint(canvas, const ui.Size(640, 384));
              canvas.restore();
            }
          }
          final picture = recorder.endRecording();
          try {
            final image = await picture.toImage(
              map.width * 48,
              map.height * 48,
            );
            try {
              final png = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              expect(png, isNotNull);
              File(
                '${folder.path}/${map.id.replaceAll(':', '-')}.png',
              ).writeAsBytesSync(png!.buffer.asUint8List());
            } finally {
              image.dispose();
            }
          } finally {
            picture.dispose();
          }
          expect(
            jsonEncode(game.snapshot()),
            before,
            reason: '${map.id} 绘制不能改动机关或剧情',
          );
          index.add({
            'id': map.id,
            'name': game.sceneName,
            'resourceName': map.name,
            'width': map.width,
            'height': map.height,
            'tiles': map.tiles,
            'script': game.cursor?.script.id,
            'initialized': matched,
            'npcs': actors,
          });
        }
        expect(index.length, 83);
        File('${folder.path}/index.json').writeAsStringSync(jsonEncode(index));
      } finally {
        art.dispose();
      }
    });
  }, timeout: const Timeout(Duration(minutes: 5)));
}

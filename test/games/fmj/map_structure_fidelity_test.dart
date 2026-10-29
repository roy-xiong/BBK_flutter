import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bbk_flutter/games/fmj/ui/modern_art.dart';
import 'package:bbk_flutter/games/fmj/ui/modern_scene.dart';
import 'package:bbk_flutter/games/fmj/engine/game_engine.dart';
import 'package:bbk_flutter/games/fmj/engine/game_actor.dart';
import 'package:bbk_flutter/games/fmj/ui/system_font_layout.dart';
import 'game_engine_test.dart' show loadData;
import 'package:bbk_flutter/games/fmj/ui/modern_terrain.dart';

/// 以原地图的可辨认物件和用户确认的材质为基准，防止新版把结构静默当作地面。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('原石梯、砖道、水池和围栏保留原类别', () {
    expect(ModernTerrain.sceneMaterial(2, 82, true), 'stone');
    expect(ModernTerrain.sceneMaterial(2, 114, true), 'stone');
    expect(ModernTerrain.sceneMaterial(1, 38, true), 'brick-road');
    expect(ModernTerrain.sceneMaterial(1, 69, false), 'grass');
    expect(ModernTerrain.sceneMaterial(1, 90, false), 'water');
    expect(ModernTerrain.tree(9, 22), isNull);
    expect(ModernTerrain.overlay(9, 22), 'fence-h');
    expect(ModernTerrain.overlay(9, 23), 'fence-v');
    expect(ModernTerrain.sceneMaterial(9, 38, true), 'stone');
    expect(ModernTerrain.role(9, 27), 'foliage');
  });

  test('村落水井包含井口与井壁，不能遗留第二截井身', () {
    final atlas =
        jsonDecode(
              File('assets/fmj/modern/enhanced-art.json').readAsStringSync(),
            )
            as Map;
    final guide =
        jsonDecode(File('assets/fmj/game/FmjGuideData.json').readAsStringSync())
            as Map;
    for (final map in guide['maps'] as List) {
      if (map['tiles'] != 9) continue;
      final objects = (atlas['buildings'][map['id']] as List? ?? const []);
      for (final well in objects.where((b) => b['key'] == 'furniture:well')) {
        expect(well['height'], 2, reason: '${map['id']} 原井壁也需要覆盖');
        expect(well['cells'], hasLength(4));
      }
    }
  });

  test('所有卧室家具只在原床图案上识别床，蔡婆家暗格处不凭空放床', () {
    final atlas =
        jsonDecode(
              File('assets/fmj/modern/enhanced-art.json').readAsStringSync(),
            )
            as Map;
    final guide =
        jsonDecode(File('assets/fmj/game/FmjGuideData.json').readAsStringSync())
            as Map;
    final maps = {
      for (final map in guide['maps'] as List) map['id']: map as Map,
    };
    for (final entry in (atlas['decorations'] as Map).entries) {
      final map = maps[entry.key]!;
      if (map['tiles'] != 3) continue;
      for (final object in entry.value as List) {
        if (!['furniture:bed', 'furniture:bed-mat'].contains(object['key'])) {
          continue;
        }
        final tile =
            (map['cells'][(object['y'] as int) * (map['width'] as int) +
                    (object['x'] as int)]
                as int) &
            127;
        expect(
          [16, 73],
          contains(tile),
          reason: '${entry.key} ${object['x']},${object['y']} 原图块 $tile 不是床头',
        );
      }
    }
  });
  test('桥头和庭院石狮数量对应原图，阶边43号不能变成石狮', () {
    final atlas =
        jsonDecode(
              File('assets/fmj/modern/enhanced-art.json').readAsStringSync(),
            )
            as Map;
    final guide =
        jsonDecode(File('assets/fmj/game/FmjGuideData.json').readAsStringSync())
            as Map;
    for (final map in guide['maps'] as List) {
      final tiles = map['tiles'];
      if (tiles != 1 && tiles != 2) continue;
      final source = (map['cells'] as List)
          .where((cell) => ((cell as int) & 127) == (tiles == 1 ? 40 : 41))
          .length;
      final rendered =
          ((atlas['buildings'] as Map)[map['id']] as List? ?? const [])
              .where(
                (object) =>
                    (object['key'] as String).startsWith('scenery:stone-lion-'),
              )
              .length;
      expect(rendered, source, reason: '${map['id']} 装饰不能凭空翻倍');
    }
    expect(ModernTerrain.sceneMaterial(9, 42, true), 'stone');
  });

  test('亭子只绘制一座，多排檐口不能变成重叠建筑', () {
    final atlas =
        jsonDecode(
              File('assets/fmj/modern/enhanced-art.json').readAsStringSync(),
            )
            as Map;
    for (final expected in [
      ('1:12', [5, 0, 7, 8]),
      ('1:35', [4, 1, 5, 5]),
    ]) {
      final pavilions = ((atlas['buildings'] as Map)[expected.$1] as List)
          .cast<Map>()
          .where((b) => (b['key'] as String).startsWith('building:pavilion'))
          .toList();
      expect(pavilions, hasLength(1), reason: expected.$1);
      final pavilion = pavilions.single;
      expect([
        pavilion['x'],
        pavilion['y'],
        pavilion['width'],
        pavilion['height'],
      ], expected.$2);
    }
  });

  test('全部非地面原图都有绘制帧，地毯的覆盖集合不吞掉椅凳', () {
    final atlas =
        jsonDecode(
              File('assets/fmj/modern/enhanced-art.json').readAsStringSync(),
            )
            as Map;
    final frames = atlas['frames'] as Map;
    final guide =
        jsonDecode(File('assets/fmj/game/FmjGuideData.json').readAsStringSync())
            as Map;
    final maps = {
      for (final map in guide['maps'] as List) map['id']: map as Map,
    };
    for (final map in maps.values) {
      for (final cell in map['cells'] as List) {
        final tile = (cell as int) & 127;
        final key = ModernTerrain.structureKey(map['tiles'] as int, tile);
        if (ModernTerrain.role(map['tiles'] as int, tile) != 'floor') {
          expect(key, isNotNull, reason: '${map['id']} 原物件 $tile 无绘制');
        }
        if (key != null) expect(frames, contains(key));
      }
    }
    for (final entry in (atlas['decorations'] as Map).entries) {
      final map = maps[entry.key]!;
      for (final object in entry.value as List) {
        expect(object['cells'], isNotNull);
        if (object['floor'] != true) continue;
        if (const {
          'interior-v12:counter-top',
          'interior-v12:counter-side',
        }.contains(object['key'])) {
          expect(map['tiles'], 7, reason: '柜台支承层仅用于店内图块');
          for (final cell in object['cells'] as List) {
            expect(
              (entry.value as List).any(
                (foreground) =>
                    foreground['floor'] != true &&
                    (foreground['cells'] as List).contains(cell),
              ),
              isTrue,
              reason: '支承层只能恢复已有器物下的木板，不能凭空覆盖地面',
            );
          }
          continue;
        }
        final allowed = object['key'] == 'furniture:lifu-two-step-platform'
            ? {98, 99}
            : map['tiles'] == 6
            ? {for (var n = 2; n <= 19; n++) n}
            : {for (var n = 35; n <= 43; n++) n};
        for (final index in object['cells'] as List) {
          expect(
            allowed,
            contains((map['cells'][index] as int) & 127),
            reason: '地毯不能覆盖原桌椅',
          );
        }
      }
    }
  });

  testWidgets('可见宝箱位于家具前，透明暗格保持隐藏且能触发原取物事件', (tester) async {
    await tester.runAsync(() async {
      final data = await loadData();
      final art = await ModernArt.load();
      try {
        final game = GameEngine(data, textLayout: FlutterSystemFontLayout())
          ..restore(
            jsonDecode(
                  File(
                    'test/games/fmj/fixtures/navigation_start.json',
                  ).readAsStringSync(),
                )
                as Map<String, dynamic>,
          );
        game.map = data.maps['2:10'];
        game.npcs.clear();
        game.player?.x = 9;
        game.player?.y = 16;
        game.setPreference('wideView', true);
        Future<Uint8List> raster() async {
          final recorder = ui.PictureRecorder();
          ModernScenePainter(
            game,
            art,
          ).paint(Canvas(recorder), const Size(640, 384));
          final picture = recorder.endRecording();
          try {
            final image = await picture.toImage(640, 384);
            try {
              final pixels = await image.toByteData(
                format: ui.ImageByteFormat.rawRgba,
              );
              return Uint8List.fromList(pixels!.buffer.asUint8List());
            } finally {
              image.dispose();
            }
          } finally {
            picture.dispose();
          }
        }

        final empty = await raster();
        game.npcs[21] = GameActor.load(data, 4, 9)!
          ..x = 4
          ..y = 14;
        final state = jsonEncode(game.snapshot());
        final chest = await raster();
        expect(jsonEncode(game.snapshot()), state);
        var visible = 0;
        for (var y = 128; y < 160; y++) {
          for (var x = 128; x < 160; x++) {
            final at = (y * 640 + x) * 4;
            if ((empty[at] - chest[at]).abs() +
                    (empty[at + 1] - chest[at + 1]).abs() +
                    (empty[at + 2] - chest[at + 2]).abs() >
                30) {
              visible++;
            }
          }
        }
        expect(visible, greaterThan(150), reason: '高家具不能盖住可见宝箱');
        game.npcs[21] = GameActor.load(data, 4, 18)!
          ..x = 4
          ..y = 14;
        expect(await raster(), empty, reason: '隐藏暗格不能被美术层擅自显示');
        game.npcs[21]?.x = 15;
        game.npcs[21]?.y = 3;
        game.player?.x = 14;
        game.player?.y = 3;
        game.player?.direction = 2;
        game.cursor = ScriptCursor(data.scripts['3:8']!)..running = false;
        game.interact();
        final address = data.scripts['3:8']!.events[20];
        expect(address, isNonZero);
        expect(game.cursor?.pointer, data.scripts['3:8']!.addresses[address]);
      } finally {
        art.dispose();
      }
    });
  });
}

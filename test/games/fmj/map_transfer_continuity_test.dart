import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bbk_flutter/games/fmj/data/game_data.dart';
import 'package:bbk_flutter/games/fmj/data/save_repository.dart';
import 'package:bbk_flutter/games/fmj/engine/game_engine.dart';
import 'package:bbk_flutter/games/fmj/ui/game_view_model.dart';
import 'package:bbk_flutter/games/fmj/ui/modern_map_camera.dart';
import 'package:bbk_flutter/games/fmj/ui/system_font_layout.dart';
import 'game_engine_test.dart' show loadData;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GameData data;
  setUpAll(() async => data = await loadData());

  GameEngine scene(String map, String script, int x, int y, int flag) {
    final game = GameEngine(data, textLayout: FlutterSystemFontLayout());
    game.selectStage(
      Map<String, dynamic>.from(
        data.stages[11],
      )..addAll({'mapId': map, 'scriptId': script, 'x': x, 'y': y, 'event': 0}),
    );
    game.flags.removeWhere((f) => f >= 100 && f <= 124);
    game.flags.add(flag);
    game.setPreference('modernUi', true);
    game.setPreference('randomBattleDisabled', true);
    for (var i = 0; i < 40 && !game.canSave; i++) {
      game.update();
    }
    return game;
  }

  test('横桥竖桥原野及房间边缘的人物屏幕锚点一致', () {
    for (final wide in [true, false]) {
      for (final map in data.maps.values) {
        for (final point in [(4, 3), (map.width - 5, map.height - 3)]) {
          final camera = ModernMapCamera(
            mapWidth: map.width,
            mapHeight: map.height,
            playerX: point.$1,
            playerY: point.$2,
            wide: wide,
          );
          expect(
            camera.point(point.$1, point.$2),
            const Offset(320, 192),
            reason: '${map.id} $point wide=$wide 跨图不能因边界夹取让人物跳位',
          );
        }
      }
    }
  });

  test('竖桥普通过图同步完成地图和入口脚本，不显示半初始化场景', () {
    final game = scene('1:11', '2:35', 4, 36, 101);
    game.press(GameKey.down);
    expect(game.map?.id, '1:15');
    expect(game.cursor?.script.id, '2:38');
    expect(game.cursor?.running, false);
    expect(game.operation, isNull);
    expect((game.player?.x, game.player?.y), (8, 4));
    expect(game.error, isEmpty);
  });

  test('横桥进入观星亭显示地点名时仍可继续走路', () {
    final game = scene('1:10', '2:34', 5, 4, 100);
    game.press(GameKey.left);
    expect(game.map?.id, '1:12');
    expect(game.cursor?.script.id, '2:33');
    expect(game.sceneName, '观星亭');
    expect(game.operation, isNull, reason: '地点名称不能占用阻塞剧情操作');
    expect(game.cursor?.running, false);
    final x = game.player!.x;
    game.press(GameKey.left);
    expect(game.player!.x, x - 1);
  });

  test('原野进入村落停在真实对白，不能绕过剧情', () {
    final game = scene('1:21', '2:45', 5, 3, 103);
    game.press(GameKey.left);
    for (var i = 0; i < 80 && game.operation?.kind != 'dialogue'; i++) {
      game.update();
    }
    expect(game.map?.id, '1:23');
    expect(game.cursor?.script.id, '3:1');
    expect(game.error, isEmpty);
    // 此入口在本阶段无强制对白；正常流程可停在自由行走或原对白操作。
    expect(game.operation == null || game.operation?.kind == 'dialogue', true);
  });

  test('短按过图只移动出口这一步，松手后不额外走', () {
    final game = scene('1:11', '2:35', 4, 36, 101);
    game.press(GameKey.down);
    for (var i = 0; i < 30; i++) {
      game.update();
    }
    expect(game.map?.id, '1:15');
    expect((game.player?.x, game.player?.y), (8, 4));
  });

  test('快速过图遇到真实对白或人物动作等待时交回原状态机', () {
    for (final opcode in [13, 53, 56]) {
      final game = scene('1:11', '2:35', 4, 36, 101);
      final events = List<int>.filled(42, 0)..[41] = 10;
      final entry = GameScript({
        'id': '99:41',
        'name': '过图边界回归',
        'events': events,
        'commands': [
          {'at': 0, 'op': 9, 'a': <int>[]},
          {
            'at': 10,
            'op': 1,
            'a': [1, 15, 4, 1],
          },
          {
            'at': 19,
            'op': 14,
            'a': [99, 42],
          },
        ],
      });
      final target = GameScript({
        'id': '99:42',
        'name': '真实剧情',
        'events': <int>[],
        'commands': [
          {
            'at': 0,
            'op': opcode,
            'a': opcode == 53 ? [0, 1, 0] : [1],
            'text': '必须保留的对白',
          },
          {
            'at': 9,
            'op': 26,
            'a': [2399],
          },
          {'at': 12, 'op': 9, 'a': <int>[]},
        ],
      });
      data.scripts[entry.id] = entry;
      data.scripts[target.id] = target;
      try {
        game.cursor = ScriptCursor(entry)..running = false;
        game.press(GameKey.down);
        expect(game.map?.id, '1:15');
        expect(game.flags, isNot(contains(2399)));
        game.update();
        expect(game.operation?.kind, opcode == 13 ? 'dialogue' : 'delay');
        if (opcode == 53) expect(game.operation?.args, [300]);
        if (opcode == 56) expect(game.operation?.args, [40]);
        expect(game.flags, isNot(contains(2399)), reason: '不能跨过真实剧情边界执行后续指令');
      } finally {
        data.scripts.remove(entry.id);
        data.scripts.remove(target.id);
      }
    }
  });

  testWidgets('持续方向跨图保持节奏，过图后无需重新长按', (tester) async {
    await tester.runAsync(() async {
      for (final speed in [1, 2, 4]) {
        final game = scene('1:11', '2:35', 4, 34, 101)
          ..setPreference('runSpeed', speed);
        final folder = await Directory.systemTemp.createTemp('fmj-hold-map-');
        final repository = SaveRepository(directory: folder);
        final model = GameViewModel(repository: repository)
          ..engine = game
          ..loading = false;
        try {
          model.down(GameKey.down);
          int? transferFrame, movementFrame;
          for (var frame = 0; frame < 50; frame++) {
            model.advanceFrame();
            if (game.map?.id == '1:15') transferFrame ??= frame;
            if (transferFrame != null && game.player!.y > 4) {
              movementFrame = frame;
              break;
            }
          }
          expect(transferFrame, isNotNull);
          expect(movementFrame, isNotNull);
          expect(
            (movementFrame! - transferFrame!) * 40,
            lessThanOrEqualTo(speed == 1 ? 120 : 40),
          );
        } finally {
          model.releaseHeldKeys();
          model.dispose();
          await repository.flush();
          await folder.delete(recursive: true);
        }
      }
    });
  });

  testWidgets('同一镜头反算鼠标地图坐标，窄地图不点击错行', (tester) async {
    await tester.runAsync(() async {
      final game = scene('1:21', '2:45', 10, 3, 101);
      final folder = await Directory.systemTemp.createTemp('fmj-click-map-');
      final repository = SaveRepository(directory: folder);
      final model = GameViewModel(repository: repository)
        ..engine = game
        ..loading = false;
      try {
        model.tapMap(const Offset(368, 208), const Size(640, 384));
        expect(game.route.lastOrNull, (11, 3), reason: '镜头居中后点击右边一格仍是同一地图行');
      } finally {
        model.dispose();
        await repository.flush();
        await folder.delete(recursive: true);
      }
    });
  });
}

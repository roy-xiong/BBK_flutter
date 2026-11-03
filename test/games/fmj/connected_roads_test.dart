import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bbk_flutter/games/fmj/data/game_data.dart';
import 'package:bbk_flutter/games/fmj/engine/game_engine.dart';
import 'package:bbk_flutter/games/fmj/ui/system_font_layout.dart';
import 'package:bbk_flutter/games/fmj/ui/modern_art.dart';
import 'package:bbk_flutter/games/fmj/ui/modern_scene.dart';
import 'package:bbk_flutter/games/fmj/ui/modern_map_camera.dart';
import 'game_engine_test.dart' show loadData;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GameData data;
  setUpAll(() async => data = await loadData());

  GameEngine scene({
    bool modern = true,
    int flag = 101,
    String map = '1:11',
    String script = '2:35',
    int x = 4,
    int y = 36,
  }) {
    final g = GameEngine(data, textLayout: FlutterSystemFontLayout());
    g.selectStage(
      Map<String, dynamic>.from(
        data.stages[11],
      )..addAll({'mapId': map, 'scriptId': script, 'x': x, 'y': y, 'event': 0}),
    );
    g.flags.removeWhere((f) => f >= 100 && f <= 124);
    g.flags.add(flag);
    g.setPreference('modernUi', modern);
    g.setPreference('randomBattleDisabled', true);
    for (var i = 0; i < 50 && !g.canSave; i++) {
      g.update();
    }
    return g;
  }

  test('连续道路真实出口同帧衔接，不留下旧脚本和新地图的等待帧', () {
    final game = scene();
    game.press(GameKey.down);
    expect(game.map?.id, '1:15');
    expect(game.cursor?.script.id, '2:38');
    expect(game.cursor?.running, false);
    expect(game.operation, isNull);
    expect((game.player?.x, game.player?.y), (8, 4));
  });

  test('复用同一竖桥的不同来路遵守各自原版出口，不按地图编号合并', () {
    final destinations = <(String?, String?)>{};
    for (var flag = 101; flag <= 114; flag++) {
      final original = scene(modern: false, flag: flag);
      final actual = scene(flag: flag);
      original.press(GameKey.down);
      actual.press(GameKey.down);
      for (var i = 0; i < 100 && !original.canSave; i++) {
        original.update();
      }
      for (var i = 0; i < 100 && !actual.canSave; i++) {
        actual.update();
      }
      destinations.add((actual.map?.id, actual.cursor?.script.id));
      expect(
        (actual.map?.id, actual.cursor?.script.id),
        (original.map?.id, original.cursor?.script.id),
        reason: 'flag=$flag',
      );
      expect(actual.map?.id, original.map?.id);
      expect(
        (actual.player?.x, actual.player?.y),
        (original.player?.x, original.player?.y),
      );
      expect(actual.flags, original.flags, reason: '$flag 连接不能改写原剧情旗标');
      expect(actual.variables, original.variables);
    }
    expect(destinations.length, greaterThanOrEqualTo(3));
  });

  test('预取真实相邻路段不写剧情或存档，同一桥梁的复用实例分别保存', () {
    final game = scene();
    final before = jsonEncode(game.snapshot());
    game.connectedWorld.synchronize();
    expect(jsonEncode(game.snapshot()), before);
    expect(game.connectedWorld.maps.any((n) => n.map.id == '1:15'), true);
    expect(game.connectedWorld.maps.length, lessThanOrEqualTo(18));
    final bridges = game.connectedWorld.maps
        .where((n) => n.map.id == '1:11')
        .toList();
    expect(bridges.length, greaterThan(1));
    expect(
      bridges.map((n) => (n.id, n.routeKey, n.x, n.y)).toSet().length,
      bridges.length,
    );
  });

  test('当前无开放连接时镜头停在边界，不强制人物居中', () {
    final game = scene(flag: 0);
    final view = game.connectedWorld.view(true)!;
    expect(game.connectedWorld.maps.length, 1);
    expect(view.left, 0);
    expect(view.top, 28);
    expect((game.player!.x - view.left) * view.tileSize, isNot(320));
  });

  test('跨接缝时世界落点仅前进一格，镜头不突然跳动，原路返回可回到原实例', () {
    final game = scene();
    final first = game.connectedWorld.current!;
    final before = game.connectedWorld.view(true)!;
    final x = first.x + game.player!.x, y = first.y + game.player!.y;
    game.press(GameKey.down);
    final next = game.connectedWorld.current!,
        after = game.connectedWorld.view(true)!;
    expect(next.x + game.player!.x, x);
    expect(next.y + game.player!.y, y + 1);
    expect((after.left - before.left).abs(), lessThanOrEqualTo(1));
    expect((after.top - before.top).abs(), lessThanOrEqualTo(1));
    game.press(GameKey.up);
    expect(game.map?.id, '1:11');
    expect(game.cursor?.script.id, '2:35');
    expect(game.connectedWorld.current!.x, first.x);
    expect(game.connectedWorld.current!.y, first.y);
    expect((game.player!.x, game.player!.y), (4, 36));
  });

  test('横桥两端各条来路与原版执行结果一致', () {
    for (var flag = 100; flag <= 109; flag++) {
      for (final direction in [GameKey.left, GameKey.right]) {
        final x = direction == GameKey.left ? 5 : 34;
        final original = scene(
          modern: false,
          flag: flag,
          map: '1:10',
          script: '2:34',
          x: x,
          y: 4,
        );
        final actual = scene(
          flag: flag,
          map: '1:10',
          script: '2:34',
          x: x,
          y: 4,
        );
        original.press(direction);
        actual.press(direction);
        for (var i = 0; i < 100 && !original.canSave; i++) {
          original.update();
        }
        for (var i = 0; i < 100 && !actual.canSave; i++) {
          actual.update();
        }
        expect(
          (actual.map?.id, actual.cursor?.script.id),
          (original.map?.id, original.cursor?.script.id),
          reason: '$flag/$direction',
        );
        expect(
          (actual.player?.x, actual.player?.y),
          (original.player?.x, original.player?.y),
        );
        expect(actual.flags, original.flags);
        expect(actual.variables, original.variables);
      }
    }
  });

  Map<(int, int), (int, int)> visibleCells(GameEngine game) {
    final result = <(int, int), (int, int)>{};
    final view = game.connectedWorld.view(true)!;
    for (var y = view.top; y < view.top + view.rows; y++) {
      for (var x = view.left; x < view.left + view.columns; x++) {
        final node = game.connectedWorld.visiblePriority
            .where((n) => n.region.contains(x, y))
            .firstOrNull;
        if (node != null) {
          result[(x, y)] = (
            node.map.tiles,
            node.map.cell(x - node.x, y - node.y) & 127,
          );
        }
      }
    }
    return result;
  }

  test('接缝两侧重叠视野的静态地形一致，不在过图时替换已经可见的道路', () {
    for (final game in [
      scene(),
      scene(map: '1:15', script: '2:38', flag: 106, x: 8, y: 4),
    ]) {
      final before = visibleCells(game);
      game.press(game.map!.id == '1:11' ? GameKey.down : GameKey.up);
      final after = visibleCells(game);
      for (final point in before.keys.toSet().intersection(
        after.keys.toSet(),
      )) {
        expect(after[point], before[point], reason: '接缝附近已出现的世界格 $point');
      }
    }
  });

  test('多格出口横移不改变邻图几何，非首通道返回仍复用原桥实例', () {
    final game = scene();
    final first = game.connectedWorld.current!;
    final before = visibleCells(game);
    game.press(GameKey.right);
    expect(game.player!.x, 5);
    final after = visibleCells(game);
    for (final point in before.keys.toSet().intersection(after.keys.toSet())) {
      expect(after[point], before[point], reason: '横移不能拖动邻图 $point');
    }
    game.press(GameKey.down);
    expect(game.map!.id, '1:15');
    expect(game.connectedWorld.actorOffset(game.player!).$1, 1);
    for (var i = 0; i < 4; i++) {
      game.update();
    }
    expect(game.connectedWorld.actorOffset(game.player!), (0, 0));
    game.press(GameKey.up);
    expect(game.map!.id, '1:11');
    expect(game.connectedWorld.current!.id, first.id);
    expect(game.connectedWorld.current!.x, first.x);
    expect((game.player!.x, game.player!.y), (4, 36));
  });

  test('邻图宝箱在接缝前可见，预览不领取物品或改写旗标', () {
    final game = scene(map: '1:15', script: '2:38', flag: 106, x: 12, y: 8);
    final before = jsonEncode(game.snapshot());
    final chest = game.connectedWorld.actors.where(
      (p) => p.actor.type == 4 && p.x == 12 && p.y == 6,
    );
    expect(chest, isNotEmpty);
    expect(game.map!.id, '1:15');
    expect(jsonEncode(game.snapshot()), before);
  });

  test('全道路脚本的可连接边界遵守原版目的地和剧情条件', () {
    final guide =
        jsonDecode(File('assets/fmj/game/FmjGuideData.json').readAsStringSync())
            as Map;
    var checked = 0;
    final scripts = <String>{};
    for (final raw in guide['scripts'] as List) {
      final script = data.scripts[raw['id']]!;
      final flags = <int>{
        0,
        for (final cmd in script.commands)
          if (cmd.opcode == 11 && cmd.arg(0) >= 100 && cmd.arg(0) < 200)
            cmd.arg(0),
      };
      for (final mapId in raw['maps'] as List) {
        final map = data.maps[mapId]!;
        final exits = <(int, int), (int, int, GameKey)>{};
        for (var y = 3; y < map.height - 2; y++) {
          for (var x = 4; x < map.width - 4; x++) {
            final event = map.event(x, y);
            if (event == 0) continue;
            for (final (condition, dx, dy, direction) in [
              (y == 3, 0, -1, GameKey.up),
              (x == map.width - 5, 1, 0, GameKey.right),
              (y == map.height - 3, 0, 1, GameKey.down),
              (x == 4, -1, 0, GameKey.left),
            ]) {
              if (condition &&
                  map.canWalk(x - dx, y - dy, player: true) &&
                  map.event(x - dx, y - dy) == 0) {
                exits.putIfAbsent((
                  event,
                  direction.index,
                ), () => (x - dx, y - dy, direction));
              }
            }
          }
        }
        for (final flag in flags) {
          for (final (x, y, direction) in exits.values) {
            final actual = scene(
              map: mapId,
              script: script.id,
              x: x,
              y: y,
              flag: flag,
            );
            if (!actual.canSave || !actual.connectedWorld.active) continue;
            final dir = switch (direction) {
              GameKey.up => 1,
              GameKey.right => 2,
              GameKey.down => 3,
              _ => 4,
            };
            final dx = dir == 2
                ? 1
                : dir == 4
                ? -1
                : 0;
            final dy = dir == 3
                ? 1
                : dir == 1
                ? -1
                : 0;
            if (actual.connectedWorld.prepareStep(x + dx, y + dy, dir) ==
                null) {
              continue;
            }
            final original = scene(
              modern: false,
              map: mapId,
              script: script.id,
              x: x,
              y: y,
              flag: flag,
            );
            original.press(direction);
            actual.press(direction);
            for (var i = 0; i < 200 && !original.canSave; i++) {
              original.update();
            }
            for (var i = 0; i < 200 && !actual.canSave; i++) {
              actual.update();
            }
            final reason = '${script.id}/$mapId/flag=$flag/$direction';
            expect(
              (
                actual.map?.id,
                actual.cursor?.script.id,
                actual.player?.x,
                actual.player?.y,
              ),
              (
                original.map?.id,
                original.cursor?.script.id,
                original.player?.x,
                original.player?.y,
              ),
              reason: reason,
            );
            expect(actual.flags, original.flags, reason: reason);
            expect(actual.variables, original.variables, reason: reason);
            expect(actual.error, isEmpty, reason: reason);
            final active = actual.connectedWorld.current;
            if (active != null) {
              final map = active.map;
              for (var cy = 3; cy < map.height - 2; cy++) {
                for (var cx = 4; cx < map.width - 4; cx++) {
                  if (map.canWalk(cx, cy, player: true) &&
                      map.event(cx, cy) == 0) {
                    expect(
                      active.region.contains(active.x + cx, active.y + cy),
                      true,
                      reason: '$reason 可行走地形不能漏绘: ($cx,$cy)',
                    );
                  }
                }
              }
            }
            checked++;
            scripts.add(script.id);
          }
        }
      }
    }
    // ignore: avoid_print
    print('CONNECTED_ROADS checked=$checked scripts=${scripts.length}');
    expect(checked, greaterThan(100));
    expect(scripts.length, greaterThan(15));
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('点击邻图通过原出口走到目标，不直接传送', () {
    final game = scene(y: 34);
    expect(game.connectedWorld.walkToWorld(4, 39), true);
    expect(game.map?.id, '1:11', reason: '点击不能立即传送');
    for (var i = 0; i < 1000; i++) {
      game.update();
      if (!game.connectedWorld.clicking && game.route.isEmpty) break;
    }
    expect(game.map?.id, '1:15');
    expect((game.player!.x, game.player!.y), (8, 6));
    expect(game.navigation.active, isNull);
    expect(game.error, isEmpty);
  });

  test('方向键取消邻图点击路线；预览校验不符时不改变真实目的地', () {
    final game = scene(y: 34);
    game.connectedWorld.walkToWorld(4, 39);
    game.key(GameKey.right);
    expect(game.connectedWorld.clicking, false);
    expect(game.route, isEmpty);
    final other = scene();
    final edge = other.connectedWorld.prepareStep(4, 37, 3)!;
    other.press(GameKey.down);
    other.flags.add(2398);
    expect(other.connectedWorld.finishStep(edge), false);
    expect(other.connectedWorld.active, false);
    expect(other.map?.id, '1:15');
    expect(other.flags, contains(2398));
  });

  test('邻图点击过程中剧情条件改变，不把旧目标替换成同位置的另一条路线', () {
    final game = scene(y: 34);
    expect(game.connectedWorld.walkToWorld(4, 39), true);
    game.flags.add(2398);
    game.render();
    for (var i = 0; i < 1000; i++) {
      game.update();
      if (!game.connectedWorld.clicking && game.route.isEmpty) break;
    }
    expect(game.map?.id, '1:11');
    expect(game.connectedWorld.clicking, false);
    expect(game.flags, contains(2398));
  });

  test('真实对白和门锁等剧情边界不被预取执行或自动跳过', () {
    final game = scene();
    final events = List<int>.filled(42, 0)..[41] = 10;
    final entry = GameScript({
      'id': '99:41',
      'name': '边界回归',
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
      'name': '真实对白',
      'events': <int>[],
      'commands': [
        {
          'at': 0,
          'op': 13,
          'a': [1],
          'text': '不能跳过的对白',
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
      game.render();
      final flags = Set<int>.of(game.flags);
      expect(game.connectedWorld.maps.any((n) => n.map.id == '1:15'), false);
      expect(game.flags, flags);
      game.press(GameKey.down);
      for (var i = 0; i < 100 && game.operation?.kind != 'dialogue'; i++) {
        game.update();
      }
      expect(game.operation?.kind, 'dialogue');
      expect(game.flags, isNot(contains(2399)));
    } finally {
      data.scripts.remove(entry.id);
      data.scripts.remove(target.id);
    }
  });

  test('边缘事件只改旗标而没有装地图时，不伪造相邻路段', () {
    final game = scene();
    final events = List<int>.filled(42, 0)..[41] = 10;
    final script = GameScript({
      'id': '99:43',
      'name': '非地图出口',
      'events': events,
      'commands': [
        {'at': 0, 'op': 9, 'a': <int>[]},
        {
          'at': 10,
          'op': 26,
          'a': [2399],
        },
        {'at': 13, 'op': 9, 'a': <int>[]},
      ],
    });
    data.scripts[script.id] = script;
    try {
      game.cursor = ScriptCursor(script)..running = false;
      game.render();
      expect(game.flags, isNot(contains(2399)));
      expect(game.connectedWorld.maps.length, 1);
      expect(game.connectedWorld.prepareStep(4, 37, 3), isNull);
    } finally {
      data.scripts.remove(script.id);
    }
  });

  testWidgets('生产Painter实际绘制不规则入口旁的合法格，不只是逻辑标记覆盖', (tester) async {
    await tester.runAsync(() async {
      final game = scene(map: '1:3', script: '2:13', flag: 0, x: 4, y: 4);
      game.press(GameKey.up);
      final active = game.connectedWorld.current!;
      expect(active.map.id, '1:4');
      expect(active.map.canWalk(4, 8, player: true), true);
      // 这个原版合法格曾被入口的矩形接缝裁掉；把镜头带到这里检测实际像素。
      game.player!
        ..x = 4
        ..y = 8;
      game.render();
      final view = game.connectedWorld.view(true)!;
      final sx = ((active.x + 4 - view.left) * view.tileSize + 2).round();
      final sy = ((active.y + 8 - view.top) * view.tileSize + 26).round();
      expect(sx, inInclusiveRange(0, 639));
      expect(sy, inInclusiveRange(0, 383));
      final art = await ModernArt.load();
      try {
        Future<List<int>> pixel(ModernScenePainter painter) async {
          final recorder = ui.PictureRecorder();
          painter.paint(Canvas(recorder), const Size(640, 384));
          final picture = recorder.endRecording();
          final image = await picture.toImage(640, 384);
          try {
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            );
            final at = (sy * 640 + sx) * 4;
            return bytes!.buffer.asUint8List().sublist(at, at + 4);
          } finally {
            image.dispose();
            picture.dispose();
          }
        }

        final expected = await pixel(
          ModernScenePainter(
            game,
            art,
            mapOverride: active.map,
            overview: true,
            cameraOverride: ModernMapCamera.window(
              mapWidth: active.map.width,
              mapHeight: active.map.height,
              left: view.left - active.x,
              top: view.top - active.y,
              wide: true,
            ),
          ),
        );
        final actual = await pixel(ModernScenePainter(game, art));
        expect(actual, expected, reason: '接缝外合法地形必须和原地图的实际像素一致');
      } finally {
        art.dispose();
      }
    });
  });
}

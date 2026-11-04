import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bbk_flutter/games/fmj/data/game_data.dart';
import 'package:bbk_flutter/games/fmj/engine/game_engine.dart';
import 'package:bbk_flutter/games/fmj/engine/game_actor.dart';
import 'package:bbk_flutter/games/fmj/ui/system_font_layout.dart';
import 'game_engine_test.dart' show loadData;

/// 使用正式经典场景像素与原NPC身份比对，覆盖领队、跟随及旧档共享图片编号。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GameData data;
  setUpAll(() async => data = await loadData());
  GameEngine game() => GameEngine(data, textLayout: FlutterSystemFontLayout())
    ..screen = 'play'
    ..intro = null
    ..map = data.maps['2:7']
    ..cursor = (ScriptCursor(data.scripts['2:2']!)..running = false)
    ..screenX = 7
    ..screenY = 5
    ..preferences['modernUi'] = false;
  GameActor actor(int type, int id, int direction, int step) =>
      GameActor.load(data, type, id)!
        ..x = 13
        ..y = 10
        ..direction = direction
        ..step = step;
  for (final entry in [(1, 0), (2, 6), (3, 7)]) {
    test('经典人物${entry.$1}四方向四帧与其原版身份一致，不改角色sprite', () {
      for (var direction = 1; direction <= 4; direction++) {
        for (var step = 0; step < 4; step++) {
          final g = game(), p = actor(1, entry.$1, direction, step);
          g.players.add(p);
          final before = p.toJson();
          g.render();
          final actual = Uint32List.fromList(g.surface.pixels);
          if (entry.$2 != 0) {
            g.players.clear();
            g.npcs[1] = actor(2, entry.$2, direction, step);
            g.render();
            expect(
              actual,
              g.surface.pixels,
              reason: '身份${entry.$1},方向$direction,帧$step',
            );
          }
          expect(p.toJson(), before);
          expect(p.sprite, 1);
        }
      }
    });
  }
  test('三人真实跟随的经典画面与各自NPC站位一致，旧存档不必改sprite', () {
    final g = game();
    g.players.addAll(
      [1, 2, 3].map(
        (id) => GameActor.load(data, 1, id)!
          ..x = 13
          ..y = 10
          ..direction = 1,
      ),
    );
    g.render();
    final poses = g.partyFollow.worldActors.toList();
    expect(poses, hasLength(3));
    if (Platform.environment['FMJ_EXPORT_CLASSIC_FOLLOW'] == '1') {
      File(
        'build/validation/classic-followers/party.rgba',
      ).writeAsBytesSync(g.surface.pixels.buffer.asUint8List());
    }
    final actual = Uint32List.fromList(g.surface.pixels),
        before = jsonEncode(g.players.map((p) => p.toJson()).toList());
    final expected = game();
    expected.players.add(GameActor.fromJson(g.player!.toJson()));
    for (final pose in poses.where((p) => p.actor.index != 1)) {
      final id = pose.actor.index == 2 ? 6 : 7;
      expected.npcs[id] = actor(2, id, pose.direction, pose.step)
        ..x = pose.x
        ..y = pose.y;
    }
    expected.render();
    expect(actual, expected.surface.pixels);
    expect(jsonEncode(g.players.map((p) => p.toJson()).toList()), before);
    final snapshot = g.snapshot();
    final restored = game();
    restored.restore(snapshot);
    restored.render();
    expect(restored.surface.pixels, actual);
  });
  test('剧情小梅NPC已出场时不再绘制跟随副本，黑白彩色切换不改变队伍', () {
    final g = game();
    g.players.addAll(
      [1, 2].map(
        (id) => GameActor.load(data, 1, id)!
          ..x = 13
          ..y = 10,
      ),
    );
    g.npcs[21] = actor(2, 6, 1, 0)
      ..x = 14
      ..y = 10;
    g.render();
    expect(
      g.partyFollow.worldActors.where((p) => p.actor.name == '慕容小梅'),
      hasLength(1),
    );
    final before = jsonEncode(g.snapshot());
    g.setPreference('modernUi', true);
    g.setPreference('modernUi', false);
    expect(jsonEncode(g.snapshot()), before);
  });
}

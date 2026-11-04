import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bbk_flutter/games/fmj/data/game_data.dart';
import 'package:bbk_flutter/games/fmj/engine/game_engine.dart';
import 'package:bbk_flutter/games/fmj/engine/game_actor.dart';
import 'package:bbk_flutter/games/fmj/ui/system_font_layout.dart';
import 'game_engine_test.dart' show loadData;

/// 从多年后的正式脚本入口执行，覆盖入场顺序、完整台词、收尾移动和原动画。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GameData data;
  final approved =
      (jsonDecode(File('tool/fmj_epilogue_dialogue_v2.json').readAsStringSync())
              as Map)['dialogue']
          as List;
  setUpAll(() async => data = await loadData());
  GameEngine game({required bool rescued, bool includeYuan = true}) {
    final g = GameEngine(data, textLayout: FlutterSystemFontLayout())
      ..screen = 'play'
      ..intro = null
      ..map = data.maps['2:7']
      ..screenX = 7
      ..screenY = 5;
    g.players.addAll(
      [1, 2, if (includeYuan) 3].map(
        (id) => GameActor.load(data, 1, id)!
          ..x = 11
          ..y = 8,
      ),
    );
    if (rescued) g.flags.add(GameResurrectionPill.revivedFlag);
    g.cursor = ScriptCursor(data.scripts['2:18']!)
      ..pointer = data.scripts['2:18']!.addresses[1133]!;
    return g;
  }

  for (final rescued in [false, true]) {
    test('${rescued ? '救回' : '未救回'}袁萍芷的尾声角色、台词与完字路径正确', () {
      final g = game(rescued: rescued);
      final lines = <Map<String, dynamic>>[];
      final old = <int>[];
      final path = <List<int>>[];
      GameOperation? previous;
      var sawMovie = false, sawEntry = false;
      for (var i = 0; i < 5000 && !g.ended; i++) {
        g.update();
        expect(g.error, isEmpty);
        final op = g.operation;
        if (g.npcs[22] case final npc?) {
          sawEntry = true;
          path.add([npc.x, npc.y]);
          expect(g.map!.canWalk(npc.x, npc.y), true);
        }
        if (!rescued) expect(g.npcs.containsKey(22), false);
        if (op?.kind == 'dialogue' && !identical(op, previous)) {
          if (op!.address < 9200) {
            old.add(op.address);
            if (op.address == 1396 || op.address == 1452) {
              expect(g.npcs.containsKey(22), false);
            }
          } else {
            lines.add({'actor': op.args.first, 'text': op.text});
            expect(g.npcs[22]?.index, 7);
            expect([g.npcs[22]?.x, g.npcs[22]?.y], [13, 8]);
            expect(
              g.partyFollow.worldActors.where((p) => p.actor.name == '袁萍芷'),
              hasLength(1),
            );
            expect(g.partyFollow.followers, isEmpty);
          }
        }
        if (op?.kind == 'movie') {
          expect(op!.movie?.id, '1:4');
          sawMovie = true;
        }
        previous = op;
        if (op != null && {'dialogue', 'message', 'timed'}.contains(op.kind)) {
          g.press(GameKey.confirm);
        }
      }
      expect(g.ended, true);
      expect(g.flags, contains(2316));
      expect(sawMovie, true);
      expect(g.sceneName, '无机阁');
      expect(old, [1285, 1349, 1367, 1396, 1452]);
      if (rescued) {
        expect(sawEntry, true);
        expect(lines, [
          for (final row in approved)
            {'actor': row['actor'], 'text': row['text']},
        ]);
        expect(
          lines.map((x) => x['text']).join(),
          allOf(
            contains('夫君'),
            contains('成亲这些年'),
            contains('女儿'),
            contains('两位夫人'),
          ),
        );
        expect(path.any((p) => p[0] == 13 && p[1] == 20), true);
        expect([g.player!.x, g.player!.y], [12, 20]);
        expect(g.npcs.containsKey(21), false);
        expect(g.npcs.containsKey(22), false);
      } else {
        expect(sawEntry, false);
        expect(lines, isEmpty);
        expect([g.player!.x, g.player!.y], [11, 8]);
      }
    });
  }
  test('已救回的旧档即使当前队伍没有该人物，尾声仍由剧情演员出场且不改战斗队伍', () {
    final g = game(rescued: true, includeYuan: false);
    var saw = false;
    for (var i = 0; i < 5000 && !g.ended; i++) {
      g.update();
      expect(g.error, isEmpty);
      if (g.npcs.containsKey(22)) saw = true;
      if (g.operation != null) g.press(GameKey.confirm);
    }
    expect(g.ended, true);
    expect(saw, true);
    expect(g.players.map((p) => p.index), [1, 2]);
  });
  test('持有丹药或队伍包含袁萍芷都不能替代救回标记触发新结局', () {
    final g = game(rescued: false)..addGoods('11:16', 2);
    for (var i = 0; i < 5000 && !g.ended; i++) {
      g.update();
      expect(g.npcs.containsKey(22), false);
      if (g.operation != null) g.press(GameKey.confirm);
    }
    expect(g.ended, true);
    expect(g.inventory['11:16'], 2);
  });
}

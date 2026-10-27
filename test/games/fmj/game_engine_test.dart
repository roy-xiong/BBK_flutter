import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bbk_flutter/games/fmj/data/game_data.dart';
import 'package:bbk_flutter/games/fmj/data/save_repository.dart';
import 'package:bbk_flutter/games/fmj/engine/game_actor.dart';
import 'package:bbk_flutter/games/fmj/engine/pixel_surface.dart';
import 'package:bbk_flutter/games/fmj/engine/game_engine.dart';
import 'package:bbk_flutter/games/fmj/ui/game_view_model.dart';
import 'package:bbk_flutter/games/fmj/ui/modern_game_view.dart';
import 'package:bbk_flutter/games/fmj/ui/system_font_layout.dart';

Future<GameData> loadData() async {
  Map<String, dynamic> object(String path) =>
      GameData.decodeObject(File(path).readAsStringSync());
  return GameData(
    bytes: await File('assets/fmj/game/DAT.LIB').readAsBytes(),
    encoding: GameEncoding(object('assets/fmj/game/gbk.json')),
    guide: object('assets/fmj/game/FmjGuideData.json'),
    stages:
        (jsonDecode(
                  File('assets/fmj/game/FmjStageData.json').readAsStringSync(),
                )
                as List)
            .map((v) => Map<String, dynamic>.from(v as Map))
            .toList(),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GameData data;
  setUpAll(() async {
    data = await loadData();
  });
  GameEngine engine() => GameEngine(
    data,
    textLayout: FlutterSystemFontLayout(),
    random: math.Random(24),
  );

  test('高清 Scale3x 与原增强版逐像素一致', () {
    final source = File(
          'test/games/fmj/fixtures/outdoor.rgba',
        ).readAsBytesSync(),
        surface = PixelSurface(320, 192);
    surface.pixels.buffer.asUint8List().setAll(0, source);
    final actual = surface.enhancedPixels().buffer.asUint8List(),
        expected = File(
          'test/games/fmj/fixtures/outdoor-hd.rgba',
        ).readAsBytesSync();
    var differences = 0;
    for (var i = 0; i < actual.length; i++) {
      if (actual[i] != expected[i]) differences++;
    }
    expect(differences, 0, reason: '高清像素通道差异 $differences');
  });
  test('资源与脚本入口完整，所有真实跳转落在指令边界', () {
    expect(data.maps.length, 83);
    expect(data.scripts.length, 185);
    expect(data.stages.length, 96);
    for (final script in data.scripts.values) {
      for (final event in script.events.where((v) => v > 0)) {
        expect(
          script.addresses.containsKey(event),
          isTrue,
          reason: '${script.id}/$event',
        );
      }
    }
  });
  for (final name in ['outdoor', 'interior']) {
    test('经典 $name 地图和人物逐像素匹配 BBK 固定提交', () {
      final fixtures =
          (jsonDecode(
                    File(
                      'test/games/fmj/fixtures/frames.json',
                    ).readAsStringSync(),
                  )
                  as List)
              .cast<Map>();
      final fixture = fixtures.firstWhere((v) => v['name'] == name),
          game = engine();
      final map = (fixture['map'] as List).cast<int>(),
          camera = (fixture['camera'] as List).cast<int>(),
          a = (fixture['actor'] as List).cast<int>(),
          n = (fixture['npc'] as List).cast<int>();
      game.screen = 'play';
      game.map = data.maps['${map[0]}:${map[1]}'];
      game.screenX = camera[0];
      game.screenY = camera[1];
      final actor = GameActor.load(data, 1, a[0]);
      expect(actor, isNotNull);
      if (actor != null) {
        actor.x = camera[0] + a[1];
        actor.y = camera[1] + a[2];
        game.players.add(actor);
      }
      final npc = GameActor.load(data, 2, n[1]);
      if (npc != null) {
        npc.x = n[2];
        npc.y = n[3];
        game.npcs[n[0]] = npc;
      }
      game.render();
      final actual = game.surface.pixels.buffer.asUint8List(),
          expected = File(
            'test/games/fmj/fixtures/$name.rgba',
          ).readAsBytesSync();
      var mismatches = 0;
      for (var i = 0; i < actual.length; i++) {
        if (actual[i] != expected[i]) mismatches++;
      }
      expect(mismatches, 0, reason: '图像通道差异 $mismatches/${actual.length}');
    });
  }
  for (final name in [
    'main_menu',
    'properties',
    'system',
    'save_empty',
    'state',
    'equipment',
  ]) {
    test('经典菜单 $name 图像层匹配原引擎', () {
      final game = engine();
      game.selectStage(data.stages.first);
      for (var i = 0; i < 500 && game.cursor?.running == true; i++) {
        game.update();
      }
      switch (name) {
        case 'main_menu':
          game.openMainMenu();
        case 'properties':
          game.openMainMenu();
          game.menus.last.onSelect?.call(0);
        case 'system':
          game.openMainMenu();
          game.menus.last.selected = 3;
          game.menus.last.onSelect?.call(3);
        case 'save_empty':
          game.openSaveMenu(force: true);
        case 'state':
          game.openState();
        case 'equipment':
          game.openEquipment(0);
      }
      game.render();
      final actual = game.surface.pixels.buffer.asUint8List(),
          expected = File(
            'test/games/fmj/fixtures/$name.rgba',
          ).readAsBytesSync();
      var mismatch = 0;
      for (var i = 0; i < actual.length; i++) {
        if (actual[i] != expected[i]) mismatch++;
      }
      if (mismatch > 0) {
        Directory('build/validation').createSync(recursive: true);
        File('build/validation/$name-actual.rgba').writeAsBytesSync(actual);
      }
      expect(mismatch, 0, reason: '界面像素通道差异 $mismatch');
    });
  }
  for (final name in ['battle_select', 'battle_win']) {
    test('经典战斗 $name 图像层匹配原引擎', () {
      final game = GameEngine(
        data,
        textLayout: FlutterSystemFontLayout(),
        random: ConstantRandom(),
      );
      game.selectStage(data.stages.first);
      for (var i = 0; i < 500 && game.cursor?.running == true; i++) {
        game.update();
      }
      final battle = GameBattle(
        game,
        monsters: [name == 'battle_win' ? 2 : 1],
        background: [2, 2, 2],
        randomFight: false,
      );
      game.battle = battle;
      if (name == 'battle_win') {
        battle.auto = true;
        for (var i = 0; i < 2000 && battle.phase != 'win'; i++) {
          battle.update();
        }
      }
      game.render();
      final actual = game.surface.pixels.buffer.asUint8List(),
          expected = File(
            'test/games/fmj/fixtures/$name.rgba',
          ).readAsBytesSync();
      var count = 0;
      for (var i = 0; i < actual.length; i++) {
        if (actual[i] != expected[i]) count++;
      }
      if (count > 0) {
        Directory('build/validation').createSync(recursive: true);
        File('build/validation/$name-actual.rgba').writeAsBytesSync(actual);
      }
      expect(count, 0, reason: '战斗像素通道差异 $count');
    });
  }
  test('长对白使用系统字体宽度分页，并能完整走完开场', () {
    final game = engine();
    game.startNewGame();
    for (var i = 0; i < 4000; i++) {
      game.update();
      final op = game.operation;
      if (op?.kind == 'dialogue' || op?.kind == 'message') {
        game.press(GameKey.confirm);
      }
      if (game.cursor?.running == false && game.operation == null) break;
    }
    expect(game.error, isEmpty);
    expect(game.flags.contains(1), isTrue);
    expect(game.cursor?.script.id, '2:12');
    expect(game.player?.name, '柳清风');
    expect(game.surface.textRuns.every((run) => run.text.isNotEmpty), isTrue);
  });
  test('连续确认不会代替玩家选择剧情分支', () {
    final game = engine();
    game.operation = GameOperation('choice', options: ['取消', '确认']);
    game.screen = 'play';
    for (var i = 0; i < 20; i++) {
      game.press(GameKey.confirm);
    }
    expect(game.operation?.kind, 'choice');
    game.choose(0);
    expect(game.operation, isNull);
  });
  test('过期触摸回应不会选中新出现的剧情分支', () {
    final game = engine(),
        old = GameOperation('choice', options: ['旧选项一', '旧选项二']),
        current = GameOperation('choice', options: ['新选项一', '新选项二']);
    game.operation = current;
    game.choose(1, expected: old);
    expect(identical(game.operation, current), isTrue);
  });
  test('脚本跳转按帧让出执行权，计时循环不会耗尽单帧预算', () {
    final game = engine();
    game.screen = 'play';
    game.cursor = ScriptCursor(
      GameScript({
        'id': 'test:loop',
        'name': '循环',
        'events': [],
        'commands': [
          {
            'at': 3,
            'op': 12,
            'a': [0, 0],
          },
          {
            'at': 8,
            'op': 22,
            'a': [0, 1],
          },
          {
            'at': 13,
            'op': 10,
            'a': [8],
          },
        ],
      }),
    );
    for (var i = 0; i < 10; i++) {
      game.update();
    }
    expect(game.error, isEmpty);
    expect(game.variables[0], 10);
  });
  test('切换整套 UI 不改变坐标、剧情、背包或当前对白', () {
    final game = engine();
    game.selectStage(data.stages.first);
    for (var i = 0; i < 100; i++) {
      game.update();
    }
    final snapshot = jsonEncode(game.snapshot()), operation = game.operation;
    for (var i = 0; i < 20; i++) {
      game.setPreference('modernUi', i.isEven);
    }
    expect(jsonEncode(game.snapshot()), snapshot);
    expect(identical(game.operation, operation), isTrue);
  });
  test('存档恢复回滚同一组剧情状态', () {
    final game = engine();
    game.selectStage(data.stages[15]);
    for (var i = 0; i < 200 && game.operation == null; i++) {
      game.update();
    }
    final saved = GameData.decodeObject(jsonEncode(game.snapshot()));
    game.money = 1;
    game.flags.add(2400);
    game.restore(saved);
    expect(game.money, saved['money']);
    expect(game.flags.contains(2400), isFalse);
    expect(game.map?.id, saved['map']);
  });
  test('串行存档写入保留最后一个完整版本', () async {
    final directory = await Directory.systemTemp.createTemp('fmj-save-test');
    try {
      final repo = SaveRepository(directory: directory);
      await Future.wait(
        List.generate(
          12,
          (i) => repo.write({
            'schema': 1,
            'revision': i,
            'payload': List.filled(1000, i),
          }),
        ),
      );
      expect((await repo.read())?['revision'], 11);
    } finally {
      await directory.delete(recursive: true);
    }
  });
  test('96 个故事节点的状态与原引擎逐项对照', () {
    final expected =
        (jsonDecode(
                  File(
                    'test/games/fmj/fixtures/stage_states.json',
                  ).readAsStringSync(),
                )
                as List)
            .cast<Map>();
    final differences = <Map<String, dynamic>>[];
    for (final stage in data.stages) {
      final game = engine();
      game.selectStage(stage);
      for (var i = 0; i < 2500; i++) {
        game.update();
        final op = game.operation;
        if (game.cursor?.running == false ||
            game.battle != null ||
            op != null &&
                ['dialogue', 'choice', 'message', 'menu'].contains(op.kind) ||
            game.menus.isNotEmpty) {
          break;
        }
      }
      final reference = expected.firstWhere((v) => v['id'] == stage['id']);
      void compare(String key, dynamic actual, dynamic expected) {
        if (!equals(expected).matches(actual, <dynamic, dynamic>{})) {
          differences.add({
            'stage': stage['id'],
            'field': key,
            'actual': actual,
            'expected': expected,
          });
        }
      }

      compare('error', game.error, '');
      compare('map', game.map?.id, reference['map']);
      compare('script', game.cursor?.script.id, reference['script']);
      compare('flags', game.flags.toList()..sort(), reference['flags']);
      compare('variables', game.variables, reference['variables']);
      compare('money', game.money, reference['money']);
      final expectedPlayers = (reference['players'] as List).cast<Map>();
      compare(
        'players',
        game.players.map((p) {
          final json = p.toJson();
          return {for (final key in expectedPlayers.first.keys) key: json[key]};
        }).toList(),
        expectedPlayers,
      );
      final ids = game.npcs.keys.toList()..sort();
      compare('npcs', [
        for (final id in ids)
          {
            'id': id,
            'index': game.npcs[id]?.index,
            'type': game.npcs[id]?.type,
            'x': game.npcs[id]?.x,
            'y': game.npcs[id]?.y,
          },
      ], reference['npcs']);
      compare('goods', game.inventory, {
        for (final item in reference['goods'] as List)
          (item as Map)['id']: item['count'],
      });
    }
    Directory('build/validation').createSync(recursive: true);
    File('build/validation/stage-differences.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(differences),
    );
    expect(
      differences,
      isEmpty,
      reason: jsonEncode(differences.take(4).toList()),
    );
  }, timeout: const Timeout(Duration(minutes: 3)));
  test('全部战斗怪物的首回合数值与原引擎一致', () {
    final references =
        (jsonDecode(
                  File(
                    'test/games/fmj/fixtures/battle_states.json',
                  ).readAsStringSync(),
                )
                as List)
            .cast<Map>();
    final differences = <Map<String, dynamic>>[];
    for (final reference in references) {
      final game = GameEngine(
        data,
        textLayout: FlutterSystemFontLayout(),
        random: ConstantRandom(),
      );
      game.selectStage(data.stages.first);
      for (var i = 0; i < 500 && game.cursor?.running == true; i++) {
        game.update();
      }
      final battle = GameBattle(
        game,
        monsters: [reference['id'] as int],
        background: [2, 2, 2],
        randomFight: false,
      )..auto = true;
      game.battle = battle;
      for (var i = 0; i < 10000; i++) {
        battle.update();
        if (battle.round >= 1 ||
            battle.phase == 'win' ||
            battle.phase == 'loss') {
          break;
        }
      }
      Map<String, dynamic> stats(GameActor p) => {
        'index': p.index,
        'hp': p.hp,
        'mp': p.mp,
        'level': p.level,
        'exp': p.exp,
        'status': p.status & 15,
      };
      final actual = {
        'id': reference['id'],
        'round': battle.round,
        'phase': switch (battle.phase) {
          'win' => 'Win',
          'loss' => 'Loss',
          'select' => 'SelectAction',
          _ => battle.phase,
        },
        'players': game.players.map(stats).toList(),
        'monsters': battle.monsters.skip(1).map(stats).toList(),
        'money': game.money,
      };
      if (!equals(reference).matches(actual, <dynamic, dynamic>{})) {
        differences.add({'actual': actual, 'expected': reference});
      }
    }
    Directory('build/validation').createSync(recursive: true);
    File('build/validation/battle-differences.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(differences),
    );
    expect(
      differences,
      isEmpty,
      reason: jsonEncode(differences.take(3).toList()),
    );
  }, timeout: const Timeout(Duration(minutes: 2)));
  test('损坏的档案不会部分替换当前会话', () {
    final game = engine();
    game.selectStage(data.stages.first);
    for (var i = 0; i < 100; i++) {
      game.update();
    }
    final before = jsonEncode(game.snapshot()),
        invalid = GameData.decodeObject(before);
    invalid['variables'] = [1];
    expect(() => game.restore(invalid), throwsFormatException);
    expect(jsonEncode(game.snapshot()), before);
  });
  testWidgets('新版 UI 在手机与桌面尺寸正常布局并输出画面', (tester) async {
    final model = GameViewModel()
      ..engine = engine()
      ..loading = false;
    final game = model.engine;
    if (game == null) fail('缺少会话');
    game.selectStage(data.stages.first);
    for (var i = 0; i < 60; i++) {
      game.update();
    }
    await tester.runAsync(() => model.prepareModernArt());
    final folder = Directory('build/validation');
    folder.createSync(recursive: true);
    for (final size in [const Size(360, 240), const Size(1000, 600)]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: RepaintBoundary(
              key: const Key('capture'),
              child: ModernGameView(model: model),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      final boundary =
          tester.renderObject(find.byKey(const Key('capture')))
              as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        if (bytes != null) {
          File(
            '${folder.path}/modern-${size.width.toInt()}.png',
          ).writeAsBytesSync(bytes.buffer.asUint8List());
        }
        image.dispose();
      });
    }
    await tester.pumpWidget(const SizedBox.shrink());
    model.dispose();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

/// 原引擎对照使用固定的 0.5 随机输入，避免随机序列掩盖计算规则差异。
final class ConstantRandom implements math.Random {
  @override
  bool nextBool() => true;
  @override
  double nextDouble() => .5;
  @override
  int nextInt(int max) => (max * .5).floor();
}

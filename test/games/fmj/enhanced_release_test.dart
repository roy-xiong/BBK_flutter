import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bbk_flutter/games/fmj/data/game_data.dart';
import 'package:bbk_flutter/games/fmj/engine/game_actor.dart';
import 'package:bbk_flutter/games/fmj/engine/game_engine.dart';
import 'package:bbk_flutter/games/fmj/ui/dialogue_presentation.dart';
import 'package:bbk_flutter/games/fmj/ui/game_page.dart';
import 'package:bbk_flutter/games/fmj/ui/game_view_model.dart';
import 'package:bbk_flutter/games/fmj/ui/modern_battle_hud.dart';
import 'package:bbk_flutter/games/fmj/ui/modern_battle_layout.dart';
import 'package:bbk_flutter/games/fmj/ui/modern_scene.dart';
import 'package:bbk_flutter/games/fmj/ui/modern_art.dart';
import 'package:bbk_flutter/games/fmj/ui/modern_terrain.dart';
import 'package:bbk_flutter/games/fmj/ui/system_font_layout.dart';
import 'game_engine_test.dart' show loadData;

/// 发布回归只读取实际资源与原引擎对象，防止局部美术试样掩盖全游戏缺帧。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GameData data;
  late Map<String, dynamic> initial;
  setUpAll(() async {
    data = await loadData();
    initial =
        jsonDecode(
              File(
                'test/games/fmj/fixtures/navigation_start.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
  });
  GameEngine engine() => GameEngine(
    data,
    textLayout: FlutterSystemFontLayout(),
    random: math.Random(24),
  )..restore(initial);
  Map<String, dynamic> read(String name) =>
      jsonDecode(File('assets/fmj/modern/$name').readAsStringSync())
          as Map<String, dynamic>;

  test('完整高清图集覆盖三主角、34 NPC、48 种怪物及全部建筑入口', () {
    final atlas = read('enhanced-art.json'),
        sources = read('enhanced-art-sources.json');
    final frames = atlas['frames'] as Map<String, dynamic>;
    expect(sources['partial'], isFalse);
    expect(sources['missing'], isEmpty);
    for (var hero = 1; hero <= 3; hero++) {
      for (var phase = 0; phase < 12; phase++) {
        expect(frames, contains('battle:hero:$hero/$phase'));
      }
      expect(frames, contains('portrait:hero:$hero/0'));
    }
    for (final kind in ['hero', 'npc']) {
      for (var index = 1; index <= (kind == 'hero' ? 3 : 34); index++) {
        for (var direction = 1; direction <= 4; direction++) {
          for (var phase = 0; phase < 3; phase++) {
            expect(frames, contains('world:$kind:$index:$direction/$phase'));
          }
        }
      }
    }
    final sprites = <int>{};
    for (var index = 1; index <= 63; index++) {
      final actor = GameActor.load(data, 3, index);
      if (actor == null) continue;
      sprites.add(actor.sprite);
      final image = data.image(8, 3, actor.sprite);
      expect(image, isNotNull);
      for (var phase = 0; phase < image!.frames.length; phase++) {
        expect(frames, contains('battle:monster:${actor.sprite}/$phase'));
      }
    }
    expect(sprites.length, 48);
    final textures = (atlas['textures'] as List).cast<String>();
    final dimensions = <(int, int)>[];
    var bytes = 0;
    for (final name in [
      ...textures,
      ...(atlas['backgrounds'] as Map).values.cast<String>(),
      ...(atlas['groundTextures'] as Map).values.cast<String>(),
      'world-atlas.png',
      'battle-landscape.png',
    ]) {
      final header = ByteData.sublistView(
        File('assets/fmj/modern/$name').readAsBytesSync(),
      );
      final width = header.getUint32(16), height = header.getUint32(20);
      bytes += width * height * 4;
      if (dimensions.length < textures.length) dimensions.add((width, height));
    }
    expect(bytes, lessThan(256 * 1024 * 1024), reason: '已解码图片预算，避免无约束图集占用');
    for (final entry in frames.entries) {
      final r = (entry.value as List).cast<int>(), size = dimensions[r[0]];
      expect(r[1], greaterThanOrEqualTo(0), reason: entry.key);
      expect(r[2], greaterThanOrEqualTo(0), reason: entry.key);
      expect(r[1] + r[3], lessThanOrEqualTo(size.$1), reason: entry.key);
      expect(r[2] + r[4], lessThanOrEqualTo(size.$2), reason: entry.key);
    }
    expect(
      (atlas['backgrounds'] as Map).keys,
      containsAll(['forest', 'cave', 'courtyard', 'village']),
    );
    final buildings = atlas['buildings'] as Map<String, dynamic>;
    expect(
      buildings.values.fold<int>(0, (sum, v) => sum + (v as List).length),
      greaterThanOrEqualTo(79),
    );
    var entrances = 0;
    for (final entry in read('scene-landmarks.json').entries) {
      final map = data.maps[entry.key];
      if (map == null || ![1, 9].contains(map.tiles)) continue;
      for (final entrance in (entry.value as List).cast<Map>()) {
        if (!(entrance['target'] as String).startsWith('2:')) continue;
        entrances++;
        final x = entrance['x'] as num, y = entrance['y'] as num;
        expect(
          (buildings[map.id] as List? ?? []).cast<Map>().any(
                (b) =>
                    x >= b['x'] &&
                    x <= b['x'] + b['width'] &&
                    y >= b['y'] &&
                    y < b['y'] + b['height'] &&
                    frames.containsKey('${b['key']}/0'),
              ) ||
              ModernTerrain.structureKey(
                    map.tiles,
                    map.cell(x.floor(), y.floor()) & 127,
                  ) !=
                  null,
          isTrue,
          reason: '${map.id} ${entrance['label']}',
        );
      }
    }
    expect(entrances, 68);
    final decorations = atlas['decorations'] as Map<String, dynamic>;
    expect(decorations.keys.where((key) => key.startsWith('2:')).length, 26);
    for (final entry in decorations.entries) {
      final map = data.maps[entry.key]!;
      for (final item in (entry.value as List).cast<Map>()) {
        expect(frames, contains('${item['key']}/0'));
        expect(
          (item['x'] as int) + (item['width'] as int),
          lessThanOrEqualTo(map.width),
        );
        expect(
          (item['y'] as int) + (item['height'] as int),
          lessThanOrEqualTo(map.height),
        );
        if (item['key'] == 'furniture:woven-rug') expect(item['floor'], isTrue);
      }
    }
  });

  test('人物身份采用独立原稿，师傅与路人不复用柳清风的行走切片', () {
    final sources = read('enhanced-art-sources.json')['frames'] as Map;
    Map origin(String key) {
      var value = sources[key] as Map;
      for (var i = 0; i < 5 && value['alias'] != null; i++) {
        value = sources[value['alias']] as Map;
      }
      return value;
    }

    final hero = origin('world:hero:1:3/0')['source'];
    final master = origin('world:npc:1:3/0')['source'];
    expect(master, 'npc-elder-taoist-front-v6.png');
    expect(master, isNot(hero));
    for (final direction in [2, 4]) {
      expect(
        origin('world:npc:1:$direction/0')['source'],
        'npc-elder-taoist-profile-v6.png',
      );
    }

    expect(
      origin('world:npc:20:3/0')['source'],
      'npc-artisan-v4.png',
      reason: '小画家是蔡婆婆的女儿',
    );
    expect(origin('world:npc:21:3/0')['source'], 'npc-maiden-cyan-v4.png');
    expect(origin('world:npc:34:3/0')['source'], 'npc-maiden-peach-v4.png');
    for (final adult in [18, 22, 32]) {
      expect(
        origin('world:npc:$adult:3/0')['source'],
        isNot('npc-young-taoist-v3.png'),
      );
    }

    for (final sprite in [8, 9, 10, 11, 19, 20, 21, 27, 32, 39, 40, 44]) {
      expect(
        origin('battle:monster:$sprite/0')['source'],
        sprite == 40
            ? 'npc-elder-taoist-profile-v6.png'
            : sprite == 10
            ? 'monster-10-clean-v3.png'
            : [11, 19, 21].contains(sprite)
            ? 'monster-$sprite-anatomy-v5.png'
            : sprite == 9
            ? 'monster-9-grip-v3.png'
            : [10, 20, 44].contains(sprite)
            ? 'monster-$sprite-clean-v3.png'
            : 'monster-$sprite-period-v2.png',
      );
    }
    for (final npc in [2, 3, 8, 9, 11, 15, 19, 20, 21, 25, 26]) {
      expect(origin('world:npc:$npc:3/0')['source'], isNot(hero));
    }
  });

  test('所有室内完整陈设、正交亭子和场景材质均有实际资源', () {
    final atlas = read('enhanced-art.json'), frames = atlas['frames'] as Map;
    final rooms = atlas['rooms'] as Map;
    expect(rooms.length, 26);
    final cave = ((atlas['buildings'] as Map)['1:6'] as List)
        .cast<Map>()
        .singleWhere((b) => b['key'] == 'building:cave-mouth');
    expect([cave['x'], cave['y'], cave['width'], cave['height']], [5, 1, 4, 4]);
    expect(
      read('scene-landmarks.json')['1:6'],
      isEmpty,
      reason: '按最新反馈移除洞口名牌，洞口模型及真实出口保留',
    );
    final blocker = GameActor.load(data, 4, 10);
    expect(blocker?.sprite, 10, reason: '坍塌石头仍采用原剧情的机关资源与碰撞');
    final caveLinks = read('scene-landmarks.json');
    for (final mapId in ['3:1', '3:2', '3:3', '3:4', '3:5']) {
      expect(caveLinks[mapId], isNull, reason: '删除人为的入口门、光效与返回标签');
    }
    for (final tile in [22, 23, 24]) {
      expect(ModernTerrain.tree(9, tile), isNull);
    }
    expect(ModernTerrain.overlay(9, 22), 'fence-h');
    expect(ModernTerrain.overlay(9, 23), 'fence-v');
    for (final map in data.maps.values) {
      for (var y = 0; y < map.height; y++) {
        for (var x = 0; x < map.width; x++) {
          final tile = map.cell(x, y) & 127;
          final material = ModernTerrain.sceneMaterial(
            map.tiles,
            tile,
            map.canWalk(x, y),
          );
          expect(
            frames,
            contains('ground:$material/0'),
            reason: '${map.id}: $x,$y',
          );
          final overlay = ModernTerrain.overlay(map.tiles, tile);
          if (overlay != null) expect(frames, contains('scenery:$overlay/0'));
        }
      }
    }
    for (final room in ['2:4', '2:6', '2:20']) {
      expect((atlas['decorations'] as Map)[room], isNotEmpty);
    }
    expect(
      ((atlas['buildings'] as Map)['1:12'] as List).any(
        (v) => v['key'] == 'building:pavilion',
      ),
      isTrue,
    );
  });

  testWidgets('坍塌洞口四块石头均可见，绘制不修改剧情与机关状态', (tester) async {
    final model = GameViewModel()
      ..engine = engine()
      ..loading = false;
    try {
      final game = model.engine!;
      game.map = data.maps['1:6'];
      game.npcs.clear();
      game.player?.x = 10;
      game.player?.y = 6;
      game.setPreference('wideView', true);
      await tester.runAsync(model.prepareModernArt);
      expect(model.modernArt, isNotNull, reason: '${model.modernArtError}');
      await tester.runAsync(() async {
        Future<Uint8List> render() async {
          final recorder = ui.PictureRecorder();
          ModernScenePainter(
            game,
            model.modernArt,
          ).paint(Canvas(recorder), const Size(640, 384));
          final picture = recorder.endRecording();
          try {
            final image = await picture.toImage(640, 384);
            try {
              final pixels = await image.toByteData(
                format: ui.ImageByteFormat.rawRgba,
              );
              expect(pixels, isNotNull);
              return Uint8List.fromList(pixels!.buffer.asUint8List());
            } finally {
              image.dispose();
            }
          } finally {
            picture.dispose();
          }
        }

        final open = await render();
        for (var id = 1; id <= 4; id++) {
          game.npcs[id] = GameActor.load(data, 4, 10)!
            ..x = id.isOdd ? 6 : 7
            ..y = id <= 2 ? 3 : 4;
        }
        final state = jsonEncode(game.snapshot());
        final collapsed = await render();
        expect(jsonEncode(game.snapshot()), state);
        for (final rock in game.npcs.values) {
          var changed = 0;
          for (var y = rock.y * 32 + 5; y < rock.y * 32 + 27; y++) {
            for (var x = rock.x * 32 + 5; x < rock.x * 32 + 27; x++) {
              final at = (y * 640 + x) * 4;
              final difference = List.generate(
                3,
                (channel) =>
                    (open[at + channel] - collapsed[at + channel]).abs(),
              ).fold<int>(0, (a, b) => a + b);
              if (difference > 30) changed++;
            }
          }
          expect(
            changed,
            greaterThan(100),
            reason: '挡路石 ${rock.x},${rock.y} 被洞门遮住',
          );
        }
        var seamCovered = 0;
        for (var y = 129; y < 132; y++) {
          for (var x = 202; x < 246; x++) {
            final at = (y * 640 + x) * 4;
            if ((open[at] - collapsed[at]).abs() +
                    (open[at + 1] - collapsed[at + 1]).abs() +
                    (open[at + 2] - collapsed[at + 2]).abs() >
                30) {
              seamCovered++;
            }
          }
        }
        expect(seamCovered, greaterThan(40), reason: '两排石头之间不能留下悬空黑缝');
      });
    } finally {
      model.dispose();
    }
  });

  test('家具和厢房保持原图比例，底部入口固定在原占地中点', () {
    for (final source in [
      const Rect.fromLTWH(0, 0, 500, 300),
      const Rect.fromLTWH(0, 0, 200, 400),
    ]) {
      const footprint = Rect.fromLTWH(40, 60, 64, 96);
      final target = ModernArt.fitObject(source, footprint);
      expect(
        target.width / target.height,
        closeTo(source.width / source.height, .00001),
      );
      expect(target.bottom, footprint.bottom);
      expect(target.center.dx, footprint.center.dx);
      expect(target.width, lessThanOrEqualTo(footprint.width));
      expect(target.height, lessThanOrEqualTo(footprint.height));
    }
  });

  test('连续地表跨格取相邻像素，桥板和岩面保留正确材质', () {
    const atlas = Rect.fromLTWH(30, 50, 512, 512);
    for (var y = 0; y < 8; y++) {
      for (var x = 0; x < 7; x++) {
        final a = ModernTerrain.source(atlas, x, y);
        final b = ModernTerrain.source(atlas, x + 1, y);
        expect(a.right, b.left);
        expect(a.height, 64);
        expect(a.width, 64);
        expect(atlas.contains(a.topLeft), isTrue);
      }
    }
    expect(
      ModernTerrain.source(atlas, 8, 0),
      ModernTerrain.source(atlas, 7, 0),
    );
    expect(ModernTerrain.material(2, 82), 'stone');
    expect(ModernTerrain.material(8, 64), 'cave');
    expect(ModernTerrain.material(3, 39), 'wood-cross');
    expect(
      ModernTerrain.structureKey(1, 20),
      isNotNull,
      reason: '建筑门墙必须有原形状细节',
    );
  });

  test('蔡大妈真实无头像事件保留 NPC 身份，主角回复不污染下句署名', () {
    final game = engine();
    game.cursor = ScriptCursor(data.scripts['3:8']!);
    game.npcs[1] = GameActor.load(data, 2, 8)!;
    expect(game.triggerEvent(1), isTrue);
    final seen = <String>{};
    for (var i = 0; i < 300; i++) {
      game.update();
      final op = game.operation;
      if (op?.kind == 'dialogue') {
        final name = DialoguePresentation.from(game, op!).speaker;
        if (name != null) seen.add(name);
        expect(name, (op.args.firstOrNull ?? 0) == 1 ? '柳清风' : '蔡大妈');
        game.press(GameKey.confirm);
      }
      if (game.cursor?.running == false && game.operation == null) break;
    }
    expect(seen, containsAll(['蔡大妈', '柳清风']));
    expect(game.error, isEmpty);
  });

  test('敌人死亡后其余站位不跳变，合击伤害使用真实目标身份定位', () {
    final game = engine();
    final battle = GameBattle(
      game,
      monsters: [1, 2, 47],
      background: [2, 2, 2],
      randomFight: true,
    );
    final layout = ModernBattleLayout(battle), victim = battle.monsters[1];
    final before = layout.point(victim);
    battle.monsters.removeAt(0);
    expect(layout.point(victim), before);
    final raised = BattleRaise(
      data,
      game.player!.combatX,
      game.player!.combatY,
      -10,
      0,
      actor: victim,
    );
    expect(layout.raisePoint(raised), before + const Offset(0, -86));
  });

  testWidgets('单人合击禁用，不会误执行原攻击入口', (tester) async {
    final game = engine();
    final battle = GameBattle(
      game,
      monsters: [1],
      background: [2, 2, 2],
      randomFight: true,
    );
    game.battle = battle;
    final model = GameViewModel()
      ..engine = game
      ..loading = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ModernBattleHud(model: model, battle: battle, art: null),
        ),
      ),
    );
    await tester.tap(find.text('合击'));
    expect(battle.targetKind, isEmpty);
    expect(game.menus, isEmpty);
    expect(battle.phase, 'select');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    model.dispose();
  });

  testWidgets('完整新版游戏页在手机和桌面展示三人战斗及全部菜单，无布局溢出', (tester) async {
    final model = GameViewModel()
      ..engine = engine()
      ..loading = false;
    final game = model.engine!;
    game.players.addAll([
      GameActor.load(data, 1, 2)!,
      GameActor.load(data, 1, 3)!,
    ]);
    game.setPreference('modernUi', true);
    await tester.runAsync(model.prepareModernArt);
    expect(model.modernArt, isNotNull, reason: '${model.modernArtError}');
    await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      // 用同一个生产 Painter 扫描全部地图，而非另写一份模拟绘制逻辑。
      final contact = Canvas(recorder);
      contact.drawColor(const Color(0xff152522), BlendMode.src);
      var index = 0;
      game.npcs.clear();
      for (final map in data.maps.values) {
        game.map = map;
        game.player?.x = map.width ~/ 2;
        game.player?.y = map.height ~/ 2;
        contact.save();
        contact.translate((index % 8) * 160.0, (index ~/ 8) * 112.0);
        ModernScenePainter(
          game,
          model.modernArt,
        ).paint(contact, const Size(160, 96));
        final label = TextPainter(
          text: TextSpan(
            text: map.id,
            style: const TextStyle(color: Colors.white, fontSize: 10),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        label.paint(contact, const Offset(4, 98));
        label.dispose();
        contact.restore();
        index++;
      }
      expect(index, 83);
      final picture = recorder.endRecording(),
          image = await picture.toImage(1280, 1232);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      Directory('build/validation').createSync(recursive: true);
      File(
        'build/validation/all-83-modern-maps.png',
      ).writeAsBytesSync(png!.buffer.asUint8List());
      image.dispose();
      picture.dispose();
    });
    game.restore(initial);
    game.players.addAll([
      GameActor.load(data, 1, 2)!,
      GameActor.load(data, 1, 3)!,
    ]);

    for (final size in [
      const Size(390, 844),
      const Size(870, 392),
      const Size(1000, 600),
    ]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      game.battle = GameBattle(
        game,
        monsters: [1, 2, 47],
        background: [2, 2, 2],
        randomFight: true,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: RepaintBoundary(
            key: const Key('full-release'),
            child: GamePage(viewModel: model),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      final scene = tester.getRect(
        find.byKey(const ValueKey('modern-scene-region')),
      );
      final information = tester.getRect(
        find.byKey(const ValueKey('world-information-band')),
      );
      expect(scene.overlaps(information), isFalse, reason: '地点与等级不能覆盖场景');
      expect(scene.bottom, closeTo(information.top, .01));
      expect(scene.width / scene.height, closeTo(5 / 3, .01));
      if (size.width > size.height) {
        final viewport = tester.getRect(
          find.byKey(const ValueKey('game-surface-layout')),
        );
        for (final label in [
          '投掷\n弯月刀',
          '技能',
          '合击',
          '选择关卡',
          '奔跑 1×',
          '自动战斗 关',
          '远视野 2×',
          'A',
          'B',
        ]) {
          expect(
            viewport.overlaps(
              tester.getRect(
                label == '合击'
                    ? find.byKey(const ValueKey('fmj-battle-coop'))
                    : find.text(label),
              ),
            ),
            isFalse,
            reason: '新版画面不能被原版 $label 遮住',
          );
        }
      }
      final boundary =
          tester.renderObject(find.byKey(const Key('full-release')))
              as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        Directory('build/validation').createSync(recursive: true);
        File(
          'build/validation/release-battle-${size.width.toInt()}.png',
        ).writeAsBytesSync(png!.buffer.asUint8List());
        image.dispose();
      });
      game.battle = null;
      for (final open in <void Function()>[
        game.openState,
        () => game.openEquipment(0),
        () => game.openInventory(mode: 'use'),
        () => game.openMagic(game.player!),
      ]) {
        game.menus.clear();
        open();
        model.action((_) {});
        await tester.pump();
        await tester.pump();
        expect(tester.takeException(), isNull);
        for (var i = 0; i < 12; i++) {
          model.press(GameKey.down);
          await tester.pump();
        }
        expect(tester.takeException(), isNull);
      }
      game.menus.clear();
    }
    await tester.pumpWidget(const SizedBox.shrink());
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  }, timeout: const Timeout(Duration(minutes: 2)));
}

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bbk_flutter/games/fmj/data/game_data.dart';
import 'package:bbk_flutter/games/fmj/engine/game_engine.dart';
import 'package:bbk_flutter/games/fmj/engine/game_actor.dart';
import 'package:bbk_flutter/games/fmj/ui/game_view_model.dart';
import 'package:bbk_flutter/games/fmj/ui/modern_art.dart';
import 'package:bbk_flutter/games/fmj/ui/modern_game_view.dart';
import 'package:bbk_flutter/games/fmj/ui/goods_icon.dart';
import 'package:bbk_flutter/games/fmj/ui/system_font_layout.dart';
import 'game_engine_test.dart' show loadData;

/// 六项用户反馈的真实资源、脚本、导航和窄屏表现回归，不改变原地图或奖励。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GameData data;
  setUpAll(() async => data = await loadData());
  GameEngine engine() => GameEngine(
    data,
    textLayout: FlutterSystemFontLayout(),
    random: math.Random(24),
  )..preferences['modernUi'] = true;

  test('全部216件原物品都有可用彩色图标，且不是同一个通用占位图', () async {
    final art = await ModernArt.load();
    try {
      final positions = <String>{};
      final ids = data.offsets.keys.where((id) => id.startsWith('6:'));
      expect(ids, hasLength(216));
      for (final key in ids) {
        final id = key.substring(2), sprite = art.sprites['goods:$id/0'];
        expect(sprite, isNotNull, reason: '${engine().goodsName(id)} $id');
        if (sprite == null) continue;
        expect(sprite.rect.width, greaterThanOrEqualTo(64));
        positions.add('${sprite.texture}/${sprite.rect}');
      }
      expect(positions, hasLength(216));
    } finally {
      art.dispose();
    }
  });

  test('使用四象或钥匙默认选使用，放走杀死及交换分支保持原选择', () {
    for (final script in data.scripts.values) {
      for (var i = 0; i < script.commands.length; i++) {
        final command = script.commands[i];
        if (command.opcode != 31) continue;
        final game = engine()
          ..screen = 'play'
          ..intro = null
          ..cursor = (ScriptCursor(script)..pointer = i);
        game.update();
        final op = game.operation;
        expect(op?.kind, 'choice');
        final use = op!.options.indexWhere((s) => s.startsWith('使用'));
        expect(
          op.selected,
          use < 0 ? 0 : use,
          reason: '${script.id}@${command.address}',
        );
      }
    }
  });

  test('鹤鸣山洞取得玄武前就推荐不点卡片，并经真实宝箱消耗钥匙取卡', () async {
    final game = engine();
    final stage = data.stages.firstWhere((s) => s['scriptId'] == '14:9');
    game.selectStage(stage);
    game.flags
      ..add(252)
      ..removeAll([253, 264, 1099, 2010, 2333]);
    game.inventory
      ..remove('14:7')
      ..['14:2'] = 1;
    game.preferences['randomBattleDisabled'] = true;
    for (var i = 0; i < 100 && !game.canSave; i++) {
      game.update();
      if (game.operation != null) game.press(GameKey.confirm);
    }
    expect(game.cursor?.script.id, '14:9');
    expect(game.flags.contains(253), isFalse);
    final goal = game.navigation.sideGoals.singleWhere(
      (g) => g.label.contains('取得不点卡片'),
    );
    expect(goal.ready, isTrue, reason: '当前持有钥匙即可开箱，不依赖送信标记或先取玄武');
    expect(game.navigation.nextGoal.label, goal.label);
    try {
      await game.navigation.startGoal();
      for (var i = 0; i < 4000 && !game.flags.contains(1099); i++) {
        if (game.navigation.planning) {
          await Future<void>.delayed(const Duration(milliseconds: 1));
        }
        game.update();
        final op = game.operation;
        if (op?.kind == 'choice') {
          expect(op?.selected, 1);
          game.choose(op!.selected, expected: op);
        } else if (op != null) {
          game.press(GameKey.confirm);
        }
        if (i % 10 == 0) await Future<void>.delayed(Duration.zero);
        expect(game.error, isEmpty);
      }
      expect(game.inventory['14:7'], 1);
      expect(game.inventory['14:2'] ?? 0, 0);
      expect(game.flags.containsAll([1099, 2010]), isTrue);
      expect(
        game.navigation.sideGoals
            .singleWhere((g) => g.label == goal.label)
            .ready,
        isFalse,
      );
    } finally {
      game.navigation.cancel();
    }
  });

  test('只有经验改变时也刷新状态栏，不要求人物移动或再次打开菜单', () {
    final game = engine();
    final model = GameViewModel()
      ..engine = game
      ..loading = false;
    var notifications = 0;
    model.addListener(() => notifications++);
    model.advanceFrame();
    final before = notifications, sceneRevision = model.sceneRevision;
    game.players.first.exp++;
    model.advanceFrame();
    expect(notifications, before + 1);
    expect(model.sceneRevision, sceneRevision, reason: '经验变化不应重新绘制整张地图');
    model.dispose();
  });

  testWidgets('三人队伍窄屏及桌面完整显示地点、等级、气血、魔法和经验', (tester) async {
    final game = engine()
      ..screen = 'play'
      ..intro = null
      ..sceneName = '三清宫药房';
    for (final id in [1, 2, 3]) {
      game.players.add(
        GameActor.load(data, 1, id)!
          ..level = 50
          ..maxHp = 999
          ..hp = 888,
      );
    }
    final model = GameViewModel()
      ..engine = game
      ..loading = false;
    await tester.runAsync(() => model.prepareModernArt());
    try {
      for (final size in [
        const Size(320, 230),
        const Size(640, 384),
        const Size(1280, 768),
      ]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: ModernGameView(model: model)),
          ),
        );
        await tester.pump();
        expect(find.text('三清宫药房'), findsOneWidget);
        final band = tester.getRect(
          find.byKey(const ValueKey('world-information-band')),
        );
        for (final p in game.players) {
          final label = find.text('${p.name}  Lv.50');
          expect(label, findsOneWidget);
          final rect = tester.getRect(label);
          expect(band.inflate(.5).contains(rect.topLeft), isTrue);
          expect(band.inflate(.5).contains(rect.bottomRight), isTrue);
        }
        expect(find.textContaining('魔法 '), findsNWidgets(3));
        expect(find.textContaining('经验 '), findsNWidgets(3));
        expect(tester.takeException(), isNull);
      }
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      model.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    }
  });

  test('洞口不挂入口名牌，建筑商店名牌保留', () {
    final marks = GameData.decodeObject(
      File('assets/fmj/modern/scene-landmarks.json').readAsStringSync(),
    );
    expect(marks['1:35'], isEmpty, reason: '霸王迷宫入口不挂名牌');
    expect(marks['1:6'], isEmpty, reason: '伏魔洞入口不挂名牌');
    expect((marks['1:1'] as List).any((v) => v['label'] == '三清宫药房'), isTrue);
  });

  testWidgets('购物、出售、背包、战斗使用和穿戴的每件物品都有图标', (tester) async {
    final game = engine()
      ..screen = 'play'
      ..intro = null;
    game.players.add(GameActor.load(data, 1, 1)!);
    for (var slot = 0; slot < 8; slot++) {
      game.unequip(game.players.first, slot);
    }
    final model = GameViewModel()
      ..engine = game
      ..loading = false;
    await tester.runAsync(() => model.prepareModernArt());
    try {
      for (final mode in [
        'buy',
        'sell',
        'equip',
        'use',
        'throw',
        'equipment',
      ]) {
        game.menus.clear();
        game.inventory.clear();
        game.addGoods('7:2');
        game.addGoods('9:1');
        if (mode == 'equipment') {
          game.equip(game.players.first, '7:2');
          game.openEquipment(0);
        } else {
          game.openInventory(mode: mode, items: ['7:2', '9:1']);
        }
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: ModernGameView(model: model)),
          ),
        );
        await tester.pump();
        final expected = mode == 'equipment'
            ? game.players.first.equipment.whereType<String>().toList()
            : game.menus.last.ids;
        for (final id in expected) {
          final icon = find.byKey(ValueKey('menu-goods-$id'));
          await tester.ensureVisible(icon);
          expect(icon, findsOneWidget, reason: '$mode/$id');
          expect(
            tester.widget<GoodsIcon>(icon).art?.sprites,
            contains('goods:$id/0'),
          );
        }
        expect(tester.takeException(), isNull);
      }
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      model.dispose();
    }
  });

  if (Platform.environment['FMJ_EXPORT_APPROVED_ART'] == '1') {
    testWidgets('导出实际图标菜单及完整队伍信息栏', (tester) async {
      final font = FontLoader('BBKGameCJK')
        ..addFont(rootBundle.load('assets/fonts/NotoSansCJKsc-Regular.otf'));
      await font.load();
      final game = engine()
        ..screen = 'play'
        ..intro = null
        ..map = data.maps['2:9']
        ..sceneName = '三清宫药房';
      for (final id in [1, 2, 3]) {
        game.players.add(
          GameActor.load(data, 1, id)!
            ..x = 5
            ..y = 11
            ..level = 50
            ..hp = 888
            ..maxHp = 999,
        );
      }
      final model = GameViewModel()
        ..engine = game
        ..loading = false;
      await tester.runAsync(() => model.prepareModernArt());
      final folder = Directory('build/validation/item-party-ui')
        ..createSync(recursive: true);
      tester.view.devicePixelRatio = 1;
      try {
        for (final width in [360, 800]) {
          tester.view.physicalSize = Size(width.toDouble(), width * .6 + 48);
          for (final mode in ['party', 'buy', 'equip', 'equipment']) {
            game.menus.clear();
            game.inventory.clear();
            game.addGoods('7:2');
            game.addGoods('9:1');
            game.addGoods('14:7');
            if (mode == 'equipment') {
              game.equip(game.players.first, '7:2');
              game.openEquipment(0);
            } else if (mode != 'party') {
              game.openInventory(mode: mode, items: ['7:2', '9:1', '14:7']);
            }
            await tester.pumpWidget(
              MaterialApp(
                theme: ThemeData.dark().copyWith(
                  textTheme: ThemeData.dark().textTheme.apply(
                    fontFamily: 'BBKGameCJK',
                  ),
                ),
                home: Scaffold(
                  body: RepaintBoundary(
                    key: const ValueKey('item-ui-capture'),
                    child: ModernGameView(model: model),
                  ),
                ),
              ),
            );
            await tester.pump();
            final boundary =
                tester.renderObject(
                      find.byKey(const ValueKey('item-ui-capture')),
                    )
                    as RenderRepaintBoundary;
            await tester.runAsync(() async {
              final image = await boundary.toImage(pixelRatio: 2);
              try {
                final bytes = await image.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                File(
                  '${folder.path}/$mode-$width.png',
                ).writeAsBytesSync(bytes!.buffer.asUint8List());
              } finally {
                image.dispose();
              }
            });
          }
        }
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        model.dispose();
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      }
    });
  }
}

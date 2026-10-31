import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bbk_flutter/games/fmj/engine/game_engine.dart';
import 'package:bbk_flutter/games/fmj/ui/game_page.dart';
import 'package:bbk_flutter/games/fmj/ui/game_view_model.dart';
import 'package:bbk_flutter/games/fmj/ui/game_cheat_panel.dart';
import 'package:bbk_flutter/games/fmj/ui/modern_art.dart';
import 'package:bbk_flutter/games/fmj/ui/modern_scene.dart';
import 'package:bbk_flutter/games/fmj/ui/system_font_layout.dart';
import 'package:bbk_flutter/games/fmj/data/game_data.dart';
import 'game_engine_test.dart' show loadData;
import 'package:bbk_flutter/games/fmj/ui/modern_map_camera.dart';

/// 固定菜单、作弊收拢、原落石及状态免疫不能只依赖静态资源存在。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GameData data;
  setUpAll(() async => data = await loadData());
  GameEngine create() => GameEngine(data, textLayout: FlutterSystemFontLayout())
    ..restore(
      GameData.decodeObject(
        File(
          'test/games/fmj/fixtures/navigation_start.json',
        ).readAsStringSync(),
      ),
    )
    ..preferences['modernUi'] = true;

  test('开启无敌清理已有异常，毒乱眠封不能残留或再次生效', () {
    final g = create(), p = create().player!;
    g.players
      ..clear()
      ..add(p);
    p.status = 15;
    p.permanentStatus = 15;
    p.statusRounds.addAll({1: 3, 2: 3, 4: 3, 8: 3});
    g.setPreference('invincible', true);
    expect(p.status, 0);
    expect(p.statusRounds, isEmpty);
    final before = p.hp;
    final b = GameBattle(
      g,
      monsters: [17],
      background: [2, 2, 2],
      randomFight: true,
    );
    g.battle = b;
    b.phase = 'perform';
    b.queue.add(BattleAction(b.monsters.first, [p], 'attack'));
    for (var i = 0; i < 80; i++) {
      g.update();
    }
    expect(p.hp, before);
    expect(p.status, 0);
    g.setPreference('invincible', false);
    expect(p.immunity, 0, reason: '关闭无敌不得修改原角色免疫属性');
  });

  testWidgets('菜单固定在独立顶栏，地图不被遮挡，刷钱仅在作弊面板', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final g = create(),
        model = GameViewModel()
          ..engine = create()
          ..loading = false;
    g.preferences['manualLayout'] = true;
    g.preferences['portraitControls'] = true;
    model.engine = g;
    await tester.runAsync(model.prepareModernArt);
    try {
      await tester.pumpWidget(MaterialApp(home: GamePage(viewModel: model)));
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.text('一键刷钱'), findsNothing);
      final settings = find.byTooltip('控制设置');
      final before = tester.getCenter(settings);
      await tester.drag(settings, const Offset(80, 60));
      await tester.pump();
      expect(tester.getCenter(settings), before);
      final bar = tester.getRect(find.byType(AppBar));
      final surface = tester.getRect(
        find.byKey(const ValueKey('game-surface-layout')),
      );
      expect(surface.top, greaterThanOrEqualTo(bar.bottom));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: GameCheatPanel(model: model)),
        ),
      );
      expect(find.text('一键刷钱'), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      model.dispose();
    }
  });

  test('恢复逐格人物和镜头，新旧存档的平滑选项均不再启用', () {
    final g = create(), player = create().player!;
    expect(g.preferences.containsKey('smoothWalking'), false);
    g.setPreference('smoothWalking', true);
    expect(g.preferences.containsKey('smoothWalking'), false);
    player.x = 20;
    player.y = 12;
    ModernMapCamera camera() => ModernMapCamera(
      mapWidth: 60,
      mapHeight: 40,
      playerX: player.x,
      playerY: player.y,
      wide: true,
    );
    expect(camera().left, 10);
    player.x++;
    expect(camera().left, 11);
    expect(camera().columns, 20);
    expect(camera().point(player.x, player.y), const Offset(320, 192));
  });

  testWidgets('取伏魔剑后的落石SRS叠帧出现在正式彩色场景', (tester) async {
    await tester.runAsync(() async {
      final g = create(), art = await ModernArt.load();
      g.map = data.maps['3:1'];
      g.npcs.clear();
      g.player!
        ..x = 16
        ..y = 12;
      final movie = GameMovie(data, 1, 1)..iterations = 1;
      g.operation = GameOperation('movie', args: [1, 1, 0, 0, 2])
        ..movie = movie;
      Future<List<int>> pixels() async {
        final recorder = ui.PictureRecorder();
        ModernScenePainter(
          g,
          art,
        ).paint(Canvas(recorder), const Size(640, 384));
        final picture = recorder.endRecording();
        final image = await picture.toImage(640, 384);
        try {
          if (Platform.environment['FMJ_EXPORT_APPROVED_ART'] == '1') {
            final out = Directory('build/validation/review-v23')
              ..createSync(recursive: true);
            final png = await image.toByteData(format: ui.ImageByteFormat.png);
            File(
              '${out.path}/fall-${movie.active.firstOrNull?.first ?? 49}.png',
            ).writeAsBytesSync(png!.buffer.asUint8List());
          }
          return (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!.buffer.asUint8List().toList();
        } finally {
          image.dispose();
          picture.dispose();
        }
      }

      try {
        final a = await pixels();
        for (var i = 0; i < 10; i++) {
          movie.update();
        }
        final b = await pixels();
        expect(a, isNot(equals(b)), reason: '仅推进原动画，不推进地图和人物，也必须看见落石变化');
      } finally {
        art.dispose();
      }
    });
  });
}

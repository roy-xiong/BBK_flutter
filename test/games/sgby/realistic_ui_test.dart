import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bbk_flutter/games/sgby/data/repositories/game_save_repository.dart';
import 'package:bbk_flutter/games/sgby/domain/models/game_battle.dart';
import 'package:bbk_flutter/games/sgby/domain/use_cases/battle_engine.dart';
import 'package:bbk_flutter/games/sgby/engine/core/native_game_session.dart';
import 'package:bbk_flutter/games/sgby/engine/rendering/battle_scene_renderer.dart';
import 'package:bbk_flutter/games/sgby/engine/rendering/game_art.dart';
import 'package:bbk_flutter/games/sgby/ui/features/game/view_models/game_view_model.dart';
import 'package:bbk_flutter/games/sgby/ui/features/game/views/game_controls_overlay.dart';
import 'package:bbk_flutter/games/sgby/ui/features/game/views/game_page.dart';

import 'support/game_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('sgby_flutter/controller'),
          (_) async => null,
        );
  });
  for (final size in [const Size(390, 844), const Size(1280, 800)]) {
    testWidgets('彩色模式 $size 保留原手柄，形势卡收起不把点击传给战场', (tester) async {
      late GameViewModel vm;
      late Directory directory;
      await tester.runAsync(() async {
        directory = await Directory.systemTemp.createTemp('sgby-realistic-ui-');
        vm = GameViewModel(
          saves: GameSaveRepository(directoryProvider: () async => directory),
        );
        await vm.initialize();
        vm.toggleCartoon();
        await vm.cartoonArtReady;
        try {
          await (FontLoader('MaterialIcons')
                ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
              .load();
        } catch (_) {
          /* 非导出测试环境不依赖图标字体是否预载。 */
        }
        final font = File('/System/Library/Fonts/Hiragino Sans GB.ttc');
        if (font.existsSync()) {
          await (FontLoader('SgbyRealisticStudy')..addFont(
                Future.value(ByteData.sublistView(font.readAsBytesSync())),
              ))
              .load();
          GameArt.previewFontFamily = 'SgbyRealisticStudy';
        }
        final db = loadGameDatabase(), world = db.loadPeriod(1, seed: 1);
        db.beginGame(world, 5);
        vm.session!.replaceWorld(world);
      });
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final key = GlobalKey();
      Future<void> screenshot(String scene) async {
        final output = Platform.environment['SGBY_ART_OUTPUT'];
        if (output == null) return;
        await tester.runAsync(() async {
          final boundary =
              key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
          if (boundary == null) return;
          final image = await boundary.toImage();
          try {
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            if (bytes != null) {
              final file = File(
                '$output/runtime_${size.width.toInt()}_$scene.png',
              );
              // 并行导出不依赖其他测试先创建目录，避免首次写截图偶发失败。
              file.parent.createSync(recursive: true);
              file.writeAsBytesSync(bytes.buffer.asUint8List());
            }
          } finally {
            image.dispose();
          }
        });
      }

      try {
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(fontFamily: 'SgbyRealisticStudy'),
            home: RepaintBoundary(
              key: key,
              child: GamePage(viewModel: vm),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        final originalPanel = size.width > size.height
            ? find.byType(GameControlsOverlay)
            : find.byType(PortraitGameControlsPanel);
        expect(originalPanel, findsOneWidget);
        expect(find.text('将领列表'), findsOneWidget);
        expect(find.text('自动战斗'), findsOneWidget);
        if (size.width < size.height) {
          expect(find.text('SELECT'), findsOneWidget);
          expect(find.text('START'), findsOneWidget);
          expect(find.text('A'), findsOneWidget);
          expect(find.text('B'), findsOneWidget);
        }
        await screenshot('strategy');
        final session = vm.session!, world = session.world!;
        final ids = List<int?>.filled(20, null)
          ..[0] = 5
          ..[10] = 0;
        final battle =
            GameBattle(
                mode: 1,
                city: 8,
                sourceCity: 3,
                way: 0,
                mapId: 1,
                playerFood: 5000,
                enemyFood: 4000,
                people: ids,
              )
              ..width = 20
              ..height = 14
              ..map = Uint8List(20 * 14)
              ..day = 3
              ..focusX = 4
              ..focusY = 5;
        battle.map.fillRange(0, battle.map.length, 1);
        for (final index in [0, 10]) {
          battle.units[index]
            ..state = 0
            ..x = (index == 0 ? 4 : 12)
            ..y = 5
            ..hp = 90
            ..mp = 40;
        }
        session.activeBattle = battle;
        var forwardedTaps = 0;
        session.onBattleTap = (_, _) {
          forwardedTaps++;
        };
        BattleSceneRenderer(
          session.canvas,
          BattleEngine(session.resources),
        ).draw(world, battle);
        session.submitScene(NativeScene.battle);
        vm.tick(const Duration(milliseconds: 20));
        vm.tick(const Duration(milliseconds: 40));
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(originalPanel, findsOneWidget);
        expect(find.text('一键出征'), findsOneWidget);
        await screenshot('battle');
        expect(find.text('敌军示意'), findsOneWidget);
        final focus = (battle.focusX, battle.focusY);
        await tester.tap(find.text('敌军示意'));
        await tester.pump();
        expect((battle.focusX, battle.focusY), focus);
        expect(forwardedTaps, 0);
        expect(tester.takeException(), isNull);
        vm.setControls(false);
        await tester.pump();
        expect(find.text('敌军示意'), findsNothing);
        expect(originalPanel, findsNothing);
        expect(find.byTooltip('显示界面控件'), findsOneWidget);
        vm.setControls(true);
        await tester.pump();
        expect(originalPanel, findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        vm.dispose();
        await tester.runAsync(() async {
          await vm.flushPersistence();
          await directory.delete(recursive: true);
        });
        GameArt.previewFontFamily = null;
      }
    });
  }
}

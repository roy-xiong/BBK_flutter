import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bbk_flutter/games/sgby/data/repositories/game_save_repository.dart';
import 'package:bbk_flutter/games/sgby/ui/features/game/view_models/game_view_model.dart';
import 'package:bbk_flutter/games/sgby/ui/features/game/views/game_general_roster_sheet.dart';
import 'package:bbk_flutter/games/sgby/ui/features/game/views/sgby_general_portrait.dart';

import 'support/game_database.dart';

void main() {
  for (final color in [false, true]) {
    testWidgets('将领列表${color ? '彩色' : '黑白'}头像随人物、分组和搜索正确绑定', (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('sgby_flutter/controller'),
            (_) async => null,
          );
      late GameViewModel vm;
      late Directory directory;
      await tester.runAsync(() async {
        directory = await Directory.systemTemp.createTemp(
          'sgby-roster-portraits-',
        );
        vm = GameViewModel(
          saves: GameSaveRepository(directoryProvider: () async => directory),
        );
        await vm.initialize();
        final db = loadGameDatabase(), world = db.loadPeriod(1, seed: 1);
        db.beginGame(world, 5);
        vm.session!.replaceWorld(world);
        if (color) {
          vm.toggleCartoon();
          await vm.cartoonArtReady;
        }
        final font = File('/System/Library/Fonts/Hiragino Sans GB.ttc');
        if (font.existsSync()) {
          await (FontLoader('RosterReview')..addFont(
                Future.value(ByteData.sublistView(font.readAsBytesSync())),
              ))
              .load();
        }
        await (FontLoader(
          'MaterialIcons',
        )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      });
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final boundaryKey = GlobalKey();
      try {
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundaryKey,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: ThemeData(fontFamily: 'RosterReview'),
              home: Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () =>
                        showSgbyGeneralRosterSheet(context, viewModel: vm),
                    child: const Text('打开将领列表'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('打开将领列表'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final output = Platform.environment['SGBY_ART_OUTPUT'];
        if (output != null) {
          await tester.runAsync(() async {
            final boundary =
                boundaryKey.currentContext?.findRenderObject()
                    as RenderRepaintBoundary?;
            if (boundary != null) {
              final ui.Image image = await boundary.toImage();
              try {
                final file = File(
                  '$output/roster_${color ? 'color' : 'bw'}.png',
                );
                file.parent.createSync(recursive: true);
                file.writeAsBytesSync(
                  (await image.toByteData(
                    format: ui.ImageByteFormat.png,
                  ))!.buffer.asUint8List(),
                );
              } finally {
                image.dispose();
              }
            }
          });
        }
        expect(find.byType(SgbyGeneralPortrait), findsWidgets);
        final portraits = tester.widgetList<SgbyGeneralPortrait>(
          find.byType(SgbyGeneralPortrait),
        );
        expect(
          portraits.every((p) => p.period == 1 && p.person != null),
          isTrue,
        );
        expect(
          portraits.every(
            (p) => color
                ? identical(p.assets, vm.cartoonAssets)
                : p.assets == null,
          ),
          isTrue,
        );
        await tester.tap(
          find.byWidgetPredicate(
            (widget) =>
                widget is Text && (widget.data?.startsWith('敌方将领') ?? false),
          ),
        );
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), '刘备');
        await tester.pumpAndSettle();
        final data = await vm.getSgbyCheatData();
        final liu = data.generals.firstWhere((g) => g.name == '刘备');
        final portrait = tester.widget<SgbyGeneralPortrait>(
          find.byType(SgbyGeneralPortrait).first,
        );
        expect(portrait.person, liu.index);
        expect(portrait.label, '刘备头像');
        expect(tester.takeException(), isNull);
        tester.state<NavigatorState>(find.byType(Navigator)).pop();
        await tester.pumpAndSettle();
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        vm.dispose();
        await tester.runAsync(() => directory.delete(recursive: true));
      }
    });
  }
}

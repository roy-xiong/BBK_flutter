import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bbk_flutter/data/repositories/launcher_repository.dart';
import 'package:bbk_flutter/domain/models/library_game.dart';
import 'package:bbk_flutter/games/fmj/data/save_repository.dart' as fmj_data;
import 'package:bbk_flutter/games/fmj/ui/game_page.dart' as fmj;
import 'package:bbk_flutter/games/sgby/data/repositories/game_save_repository.dart'
    as sgby_data;
import 'package:bbk_flutter/games/sgby/ui/features/game/views/game_page.dart'
    as sgby;
import 'package:bbk_flutter/ui/features/launcher/view_models/launcher_view_model.dart';
import 'package:bbk_flutter/ui/features/launcher/views/launcher_page.dart';
import 'package:bbk_flutter/ui/features/game/views/native_game_page.dart';

/// 验证合集接入带来的行为边界；游戏规则仍由导入的原有回归覆盖。
void main() {
  test('最近选择可恢复，快速连点不能重复创建游戏路由', () async {
    final directory = await Directory.systemTemp.createTemp('bbk-launcher-');
    final repository = LauncherRepository(
      directoryProvider: () async => directory,
    );
    final model = LauncherViewModel(repository);
    try {
      await repository.saveSelection(LibraryGame.sgby);
      await model.load();
      expect(model.selected, LibraryGame.sgby);
      expect(model.beginOpening(LibraryGame.fmj), isTrue);
      expect(model.beginOpening(LibraryGame.sgby), isFalse);
      await model.rememberSelection();
      expect(await repository.readSelection(), LibraryGame.fmj);
      model.finishOpening();
      expect(model.beginOpening(LibraryGame.sgby), isTrue);
    } finally {
      model.dispose();
      await directory.delete(recursive: true);
    }
  });

  for (final game in LibraryGame.values) {
    testWidgets('${game.title}：从封面进入原生页，取消退出及返回首页', (tester) async {
      tester.view.physicalSize = const Size(1080, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final directory = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('bbk-navigation-'),
      ))!;
      final repository = LauncherRepository(
        directoryProvider: () async => directory,
      );
      final fmjSaves = fmj_data.SaveRepository(directory: directory);
      final sgbySaves = sgby_data.GameSaveRepository(
        directoryProvider: () async => directory,
      );
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: LauncherPage(
              repository: repository,
              fmjSaves: fmjSaves,
              sgbySaves: sgbySaves,
            ),
          ),
        );
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 80)),
        );
        await tester.pumpAndSettle();
        expect(find.text('2 款'), findsOneWidget);
        expect(find.text('伏魔记'), findsOneWidget);
        expect(find.text('三国霸业'), findsOneWidget);
        final ink = find
            .descendant(
              of: find.byType(AspectRatio),
              matching: find.byType(InkWell),
            )
            .at(game.index);
        await tester.tap(ink);
        // 先启动路由动画，再推进其时间；首帧仍可能处于 Hero 的离屏布局阶段。
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        expect(find.byType(NativeGamePage), findsOneWidget);
        expect(
          game == LibraryGame.fmj
              ? find.byType(fmj.GamePage)
              : find.byType(sgby.GamePage),
          findsOneWidget,
        );
        await tester.binding.handlePopRoute();
        await tester.pump(const Duration(milliseconds: 250));
        expect(find.text('返回游戏库？'), findsOneWidget);
        await tester.tap(find.text('继续游戏'));
        await tester.pump(const Duration(milliseconds: 250));
        expect(find.byType(NativeGamePage), findsOneWidget);
        await tester.binding.handlePopRoute();
        await tester.pump(const Duration(milliseconds: 250));
        await tester.tap(find.widgetWithText(FilledButton, '返回游戏库'));
        // 同时推进真实存档 I/O 和虚拟路由动画，避免用固定两帧猜测保存完成时机。
        for (
          var attempt = 0;
          attempt < 200 && find.byType(NativeGamePage).evaluate().isNotEmpty;
          attempt++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 25)),
          );
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(find.byType(NativeGamePage), findsNothing);
        expect(find.text('选择游戏'), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        var writesFinished = false;
        Future.wait([
          repository.flush(),
          fmjSaves.flush(),
          sgbySaves.flush(),
        ]).then((_) => writesFinished = true);
        // 存档由页面销毁时提交。交替推进真实 I/O 和测试帧，等待队列完成信号。
        for (var attempt = 0; attempt < 500 && !writesFinished; attempt++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump(const Duration(milliseconds: 20));
        }
        expect(writesFinished, isTrue, reason: '清理临时目录前必须等待全部存档写入');
        await tester.runAsync(() => directory.delete(recursive: true));
      }
    });
  }
}

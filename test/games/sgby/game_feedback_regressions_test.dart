import 'dart:io';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bbk_flutter/games/sgby/data/repositories/game_save_repository.dart';
import 'package:bbk_flutter/games/sgby/domain/models/sgby_battle_statistics.dart';
import 'package:bbk_flutter/games/sgby/domain/models/game_definition.dart';
import 'package:bbk_flutter/games/sgby/ui/core/background_game_clock.dart';
import 'package:bbk_flutter/games/sgby/ui/features/game/view_models/game_view_model.dart';
import 'package:bbk_flutter/games/sgby/ui/features/game/views/game_controls_overlay.dart';
import 'package:bbk_flutter/games/sgby/ui/features/game/views/sgby_battle_statistics_text.dart';

/// 覆盖用户反馈的真实显示文本、控制入口和失焦暂停条件，不启动应用编译。
void main() {
  testWidgets('战绩按亿、万、个位完整显示，不四舍五入', (tester) async {
    final source = ValueNotifier<SgbyBattleStatistics?>(
      const SgbyBattleStatistics(
        lostSoldiers: 10001,
        lostGenerals: 0,
        killedSoldiers: 123456789,
        killedGenerals: 20001,
        hasFullHistory: true,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SgbyBattleStatisticsText(isDarkTheme: true, statistics: source),
        ),
      ),
    );
    expect(find.text('士兵 1亿2345万6789  ·  将领 2万1'), findsOneWidget);
    expect(find.text('士兵 1万1  ·  将领 0'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    source.dispose();
  });

  testWidgets('横竖屏均保留显示兵种按钮且通过统一输入派发', (tester) async {
    final inputs = <String>[];
    for (final portrait in [true, false]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 560,
              child: portrait
                  ? PortraitGameControlsPanel(
                      isDarkTheme: true,
                      hapticsEnabled: false,
                      showSgbyUtilityButtons: true,
                      onInput: (value) => inputs.add(value.name),
                    )
                  : GameControlsOverlay(
                      hapticsEnabled: false,
                      showSgbyUtilityButtons: true,
                      onInput: (value) => inputs.add(value.name),
                    ),
            ),
          ),
        ),
      );
      expect(find.text('显示兵种'), findsOneWidget);
      await tester.tap(find.text('显示兵种'));
      await tester.pump();
      expect(inputs.last, 'toggleTroopIcons');
    }
  });

  test('macOS失焦继续游戏，移动端失焦仍暂停', () async {
    final directory = await Directory.systemTemp.createTemp('sgby-focus-');
    try {
      for (final platform in [TargetPlatform.macOS, TargetPlatform.android]) {
        debugDefaultTargetPlatformOverride = platform;
        final vm = GameViewModel(
          saves: GameSaveRepository(directoryProvider: () async => directory),
        );
        try {
          vm.setForeground(false);
          expect(vm.paused, platform != TargetPlatform.macOS);
        } finally {
          vm.dispose();
        }
      }
    } finally {
      debugDefaultTargetPlatformOverride = null;
      await directory.delete(recursive: true);
    }
  });

  test('战绩边界分组保留全部有效数字', () {
    for (final entry in <int, String>{
      0: '0',
      9999: '9999',
      10000: '1万',
      10001: '1万1',
      99999999: '9999万9999',
      100000000: '1亿',
      100000001: '1亿1',
      100010001: '1亿1万1',
      9007199254740991: '90071992亿5474万991',
    }.entries) {
      expect(SgbyBattleStatisticsText.formatCount(entry.key), entry.value);
    }
  });

  test('显示兵种开关通过真实ViewModel持久化并在重开后恢复', () async {
    final directory = await Directory.systemTemp.createTemp('sgby-troop-pref-');
    final saves = GameSaveRepository(directoryProvider: () async => directory);
    final vm = GameViewModel(saves: saves);
    GameViewModel? reopened;
    try {
      await vm.initialize();
      expect(vm.isReady, isTrue);
      expect(vm.sgbyShowTroopIconsEnabled, isFalse);
      vm.send(GameInput.toggleTroopIcons);
      expect(vm.sgbyShowTroopIconsEnabled, isTrue);
      Map<String, Object?> settings = {};
      for (var i = 0; i < 100; i++) {
        settings = await saves.loadSettings();
        if ((settings['gameOptions'] as Map?)?['showTroopIcons'] == true) break;
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect((settings['gameOptions'] as Map?)?['showTroopIcons'], isTrue);
      reopened = GameViewModel(saves: saves);
      await reopened.initialize();
      expect(reopened.sgbyShowTroopIconsEnabled, isTrue);
    } finally {
      vm.dispose();
      reopened?.dispose();
      await directory.delete(recursive: true);
    }
  });

  testWidgets('macOS无窗口供帧时继续计时，弹窗和detached仍暂停，释放后无迟到回调', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final initialized = await tester.runAsync(() async {
      final directory = await Directory.systemTemp.createTemp('sgby-clock-');
      final vm = GameViewModel(
        saves: GameSaveRepository(directoryProvider: () async => directory),
      );
      await vm.initialize();
      for (var i = 0; i < 100 && vm.frames?.image == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      return (vm: vm, directory: directory);
    });
    final vm = initialized!.vm, directory = initialized.directory;
    var calls = 0, advanced = 0;
    final clock = BackgroundGameClock((elapsed) {
      calls++;
      vm.tick(elapsed);
    });
    try {
      expect(vm.isReady, isTrue);
      expect(vm.usesBackgroundClock, isTrue);
      vm.session!.onAdvance = (us) => advanced += us;
      final displayedImage = vm.frames?.image;
      expect(displayedImage, isNotNull);
      clock.start();
      vm.setLifecycleState(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      expect(tester.binding.framesEnabled, isFalse);
      await tester.pump(const Duration(milliseconds: 160));
      expect(advanced, greaterThan(0));
      expect(vm.frames?.image, same(displayedImage));
      final before = advanced;
      final gate = Completer<void>();
      final pausedOperation = vm.withSgbyAutomationPaused(() => gate.future);
      await tester.pump(const Duration(milliseconds: 160));
      expect(advanced, before);
      gate.complete();
      await tester.pump();
      await pausedOperation;
      await tester.pump(const Duration(milliseconds: 32));
      expect(advanced, greaterThan(before));
      vm.setLifecycleState(AppLifecycleState.detached);
      final detachedAt = advanced;
      await tester.pump(const Duration(milliseconds: 80));
      expect(advanced, detachedAt);
      clock.dispose();
      final stoppedAt = calls;
      await tester.pump(const Duration(milliseconds: 80));
      expect(calls, stoppedAt);
    } finally {
      clock.dispose();
      vm.dispose();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      debugDefaultTargetPlatformOverride = null;
      await tester.runAsync(() async => directory.delete(recursive: true));
    }
  });
}

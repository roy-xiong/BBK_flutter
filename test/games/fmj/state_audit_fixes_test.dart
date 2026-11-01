import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bbk_flutter/games/fmj/data/game_data.dart';
import 'package:bbk_flutter/games/fmj/data/save_repository.dart';
import 'package:bbk_flutter/games/fmj/engine/game_engine.dart';
import 'package:bbk_flutter/games/fmj/ui/game_controls.dart';
import 'package:bbk_flutter/games/fmj/ui/game_keyboard_bindings.dart';
import 'package:bbk_flutter/games/fmj/ui/game_page.dart';
import 'package:bbk_flutter/games/fmj/ui/game_view_model.dart';
import 'package:bbk_flutter/games/fmj/ui/system_font_layout.dart';
import 'game_engine_test.dart' show loadData;

/// 仅阻断最后一步文件替换，临时文件写盘仍使用真实文件系统。
final class _InstallFailureFile extends Fake implements File {
  _InstallFailureFile(this.file);
  final File file;
  @override
  String get path => file.path;
  @override
  Future<File> writeAsString(
    String contents, {
    FileMode mode = FileMode.write,
    Encoding encoding = utf8,
    bool flush = false,
  }) => file.writeAsString(
    contents,
    mode: mode,
    encoding: encoding,
    flush: flush,
  );
  @override
  Future<File> rename(String newPath) async =>
      throw FileSystemException('测试：替换主文件失败', newPath);
}

/// 覆盖真实存档、脚本与按键入口；测试的临时文件不写入玩家目录。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GameData data;
  late Map<String, dynamic> initial;
  setUpAll(() async {
    data = await loadData();
    initial = GameData.decodeObject(
      File('test/games/fmj/fixtures/navigation_start.json').readAsStringSync(),
    );
  });
  Map<String, dynamic> copy(Map<String, dynamic> value) =>
      GameData.decodeObject(jsonEncode(value));
  GameEngine engine() => GameEngine(data, textLayout: FlutterSystemFontLayout())
    ..restore(initial)
    ..setPreference('modernUi', true);
  void settle(GameEngine game) {
    for (var i = 0; i < 5000; i++) {
      game.update();
      expect(game.error, isEmpty);
      if ({'dialogue', 'message', 'timed'}.contains(game.operation?.kind)) {
        game.press(GameKey.confirm);
      }
      if (game.canSave) return;
    }
    fail('剧情未回到可保存节点');
  }

  test('F01 正式招募后导航跨图的每个安全快照都能恢复', () async {
    final game = engine();
    game.setPreference('randomBattleDisabled', true);
    game.selectStage(data.stages.singleWhere((s) => s['id'] == 'stage-036'));
    settle(game);
    expect(game.players.length, 1);
    expect(game.triggerEvent(1), isTrue);
    settle(game);
    expect(game.players.length, 2);
    await game.navigation.startGoal(const GameGoal('走到建业', '7:1', 21));
    var changedMap = false;
    try {
      for (var frame = 0; frame < 10000; frame++) {
        if (game.navigation.planning) {
          await Future<void>.delayed(const Duration(milliseconds: 1));
        }
        game.update();
        expect(game.error, isEmpty);
        if (game.canSave) {
          final snapshot = copy(game.snapshot());
          engine().restore(snapshot);
          if (game.map?.id == '1:21') {
            changedMap = true;
            final directory = await Directory.systemTemp.createTemp(
              'fmj-state-party-',
            );
            final repository = SaveRepository(directory: directory);
            final model = GameViewModel(repository: repository)
              ..engine = game
              ..loading = false;
            GameViewModel? reopened;
            try {
              game.openSaveMenu();
              game.selectMenu(game.menus.last, 0);
              expect(game.saves[0], isNotNull);
              await model.persist();
              reopened = GameViewModel(repository: repository);
              await reopened.initialize();
              reopened.setPaused(true);
              expect(reopened.engine?.map?.id, '1:21');
              expect(reopened.engine?.players.length, 2);
              reopened.engine!.openSaveMenu(load: true);
              reopened.engine!.selectMenu(reopened.engine!.menus.last, 1);
              expect(reopened.engine?.map?.id, '1:21');
              expect(reopened.engine?.players.length, 2);
            } finally {
              model.dispose();
              reopened?.dispose();
              await repository.flush();
              await directory.delete(recursive: true);
            }
            break;
          }
        }
        if ({'dialogue', 'message', 'timed'}.contains(game.operation?.kind)) {
          game.press(GameKey.confirm);
        }
        if (frame % 10 == 0) await Future<void>.delayed(Duration.zero);
      }
      expect(changedMap, isTrue);
    } finally {
      game.navigation.cancel();
    }
  });

  test('F01 兼容已写出的队员旧图坐标，但拒绝队长越界', () {
    final game = engine();
    game.selectStage(data.stages.singleWhere((s) => s['id'] == 'stage-060'));
    settle(game);
    expect(game.triggerEvent(49), isTrue);
    settle(game);
    final legacy = copy(game.snapshot());
    final party = legacy['players'] as List;
    (party[1] as Map)['x'] = 20;
    (party[1] as Map)['y'] = 23;
    final restored = engine()..restore(legacy);
    expect(restored.players[1].x, restored.player!.x);
    expect(restored.players[1].y, restored.player!.y);
    final invalidLeader = copy(legacy);
    ((invalidLeader['players'] as List).first as Map)['x'] = 9999;
    expect(() => restored.restore(invalidLeader), throwsFormatException);
  });

  test('F11 恢复旧档清除通关与上次会话提示、路径状态', () {
    final game = engine()
      ..ended = true
      ..notice = '上一局的提示'
      ..routeMap = 'stale'
      ..stageStoneProgress = 7;
    game.restore(initial);
    expect(game.ended, isFalse);
    expect(game.notice, isEmpty);
    expect(game.routeMap, isEmpty);
    expect(game.stageStoneProgress, isNull);
  });

  test('背包大于999仍保留累加值并允许存档往返', () {
    final game = engine();
    game.addGoods('14:2', 1500);
    expect(game.inventory['14:2'], 1500);
    final restored = engine()..restore(copy(game.snapshot()));
    expect(restored.inventory['14:2'], 1500);
    final invalid = copy(game.snapshot());
    (invalid['inventory'] as Map)['14:2'] = 1.5;
    expect(() => restored.restore(invalid), throwsFormatException);
  });

  test('F12 业务快照损坏的主文件回退完整备份，保留原损坏文件', () async {
    final directory = await Directory.systemTemp.createTemp(
      'fmj-state-backup-',
    );
    final repository = SaveRepository(directory: directory);
    GameViewModel? model;
    try {
      await repository.write({
        'schema': 1,
        'autosave': copy(initial)..['money'] = 54321,
      });
      await repository.write({
        'schema': 1,
        'autosave': copy(initial)..['map'] = 'missing',
      });
      model = GameViewModel(repository: repository);
      await model.initialize();
      expect(model.engine?.money, 54321);
      expect(model.engine?.screen, 'play');
      expect(model.failure, isNull);
      final primary = GameData.decodeObject(
        File('${directory.path}/fmj-session.json').readAsStringSync(),
      );
      expect((primary['autosave'] as Map)['map'], 'missing');
    } finally {
      model?.dispose();
      await repository.flush();
      await directory.delete(recursive: true);
    }
  });

  test('F14 目标已有八键时拒绝迁移并保留原动作归属', () {
    final full = GameKeyboardBindings.fromJson({
      'up': ['KeyA', 'KeyB', 'KeyC', 'KeyD', 'KeyE', 'KeyF', 'KeyG', 'KeyH'],
      'down': ['KeyI'],
    });
    final changed = full.bind(GameControl.up, 'KeyI');
    expect(changed.actionFor('KeyI'), GameControl.down);
    expect(changed.toJson(), full.toJson());
    expect(full.bind(GameControl.up, 'KeyA').actionFor('KeyA'), GameControl.up);
  });

  test('F12 从备份恢复后保存保留好备份，新主再次损坏仍能恢复', () async {
    final directory = await Directory.systemTemp.createTemp(
      'fmj-state-backup-rotation-',
    );
    final repository = SaveRepository(directory: directory);
    final target = File('${directory.path}/fmj-session.json');
    final backup = File('${target.path}.bak');
    GameViewModel? model;
    GameViewModel? reopened;
    try {
      await repository.write({
        'schema': 1,
        'autosave': copy(initial)..['money'] = 54321,
      });
      await repository.write({
        'schema': 1,
        'autosave': copy(initial)..['map'] = 'missing',
      });
      final goodBackup = await backup.readAsString();
      model = GameViewModel(repository: repository);
      await model.initialize();
      expect(model.engine?.money, 54321);
      model.engine!.money = 22222;
      await model.persist(rethrowOnFailure: true);
      expect(
        await backup.readAsString(),
        goodBackup,
        reason: '坏主不能轮转覆盖已验证的好备份',
      );
      final quarantined = await directory
          .list()
          .where((file) => file.path.contains('.corrupt-'))
          .toList();
      expect(quarantined, hasLength(1));
      expect(
        (GameData.decodeObject(
              await File(quarantined.single.path).readAsString(),
            )['autosave']
            as Map)['map'],
        'missing',
      );
      model.dispose();
      model = null;
      await target.writeAsString(
        jsonEncode({
          'schema': 1,
          'autosave': copy(initial)..['map'] = 'missing-again',
        }),
      );
      reopened = GameViewModel(
        repository: SaveRepository(directory: directory),
      );
      await reopened.initialize();
      expect(reopened.engine?.money, 54321);
      expect(reopened.engine?.screen, 'play');
    } finally {
      model?.dispose();
      reopened?.dispose();
      await repository.flush();
      await directory.delete(recursive: true);
    }
  });

  test('F12 备份恢复后的主文件替换失败时保留好备份并恢复可读主文件', () async {
    final directory = await Directory.systemTemp.createTemp(
      'fmj-state-backup-failure-',
    );
    final repository = SaveRepository(directory: directory);
    final target = File('${directory.path}/fmj-session.json');
    final backup = File('${target.path}.bak');
    final temporary = File('${target.path}.tmp');
    final files = {
      for (final file in [target, backup, temporary]) file.path: file,
    };
    GameViewModel? model;
    try {
      await repository.write({
        'schema': 1,
        'autosave': copy(initial)..['money'] = 54321,
      });
      await repository.write({
        'schema': 1,
        'autosave': copy(initial)..['map'] = 'missing',
      });
      final goodBackup = await backup.readAsString();
      model = GameViewModel(repository: repository);
      await model.initialize();
      model.engine!.money = 22222;
      await expectLater(
        IOOverrides.runZoned(
          () => model!.persist(rethrowOnFailure: true),
          createFile: (path) => path == temporary.path
              ? _InstallFailureFile(temporary)
              : files[path] ?? Zone.root.run(() => File(path)),
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(await backup.readAsString(), goodBackup);
      final recovered = GameData.decodeObject(await target.readAsString());
      expect((recovered['autosave'] as Map)['money'], 54321);
      expect((recovered['autosave'] as Map)['map'], initial['map']);
      // 错误不阻塞后续保存队列，重试后主档推进到新进度。
      await model.persist(rethrowOnFailure: true);
      expect(
        (GameData.decodeObject(await target.readAsString())['autosave']
            as Map)['money'],
        22222,
      );
    } finally {
      model?.dispose();
      await repository.flush();
      await directory.delete(recursive: true);
    }
  });

  test('F15 取消开箱仍能显式重选，自动完整流程暂缓推荐', () async {
    final game = engine();
    game.selectStage(data.stages.singleWhere((s) => s['id'] == 'stage-094'));
    settle(game);
    GameGoal task() => game.navigation.sideGoals.singleWhere(
      (g) => g.scriptId == '14:9' && g.event == 21,
    );
    expect(task().ready, isTrue);
    final keys = game.inventory['14:2'];
    game.interact();
    for (
      var frame = 0;
      frame < 100 && game.operation?.kind != 'choice';
      frame++
    ) {
      game.update();
    }
    final choice = game.operation!;
    expect(choice.scriptId, '14:9');
    expect(choice.address, 526);
    game.choose(0, expected: choice);
    settle(game);
    expect(game.inventory['14:2'], keys);
    expect(task().ready, isTrue);
    expect(task().done, isFalse);
    expect(game.navigation.nextGoal.label, isNot(task().label));
    try {
      await game.navigation.startGoal(task());
      expect(game.flags.contains(2333), isFalse);
    } finally {
      game.navigation.cancel();
    }
  });

  Future<void> flush(WidgetTester tester, SaveRepository repository) async {
    var done = false;
    unawaited(repository.flush().then((_) => done = true));
    for (var i = 0; i < 500 && !done; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(done, isTrue);
  }

  testWidgets('F13 暂停期间屏幕旧长按不能移动菜单，恢复不能续发', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    final directory = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('fmj-state-touch-'),
    ))!;
    final repository = SaveRepository(directory: directory);
    final game = engine()..openMainMenu();
    final model = GameViewModel(repository: repository)
      ..engine = game
      ..loading = false;
    try {
      await tester.pumpWidget(MaterialApp(home: GamePage(viewModel: model)));
      final touch = await tester.startGesture(
        tester.getCenter(find.byIcon(Icons.arrow_drop_down)),
      );
      await tester.pump(const Duration(milliseconds: 150));
      model.setPaused(true);
      await tester.pump();
      final before = game.menus.last.selected;
      model.press(GameKey.down);
      expect(
        game.menus.last.selected,
        before,
        reason: 'ViewModel入口也必须独立拦截暂停输入',
      );
      await tester.pump(const Duration(milliseconds: 600));
      expect(game.menus.last.selected, before);
      model.setPaused(false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(game.menus.last.selected, before);
      await touch.up();
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      model.dispose();
      await flush(tester, repository);
      await tester.runAsync(() => directory.delete(recursive: true));
    }
  });

  testWidgets('R01 同时按住W与上箭头，释放一个仍继续另一键的长按', (tester) async {
    final directory = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('fmj-state-keyboard-'),
    ))!;
    final repository = SaveRepository(directory: directory);
    final game = engine()..openMainMenu();
    final model = GameViewModel(repository: repository)
      ..engine = game
      ..loading = false;
    try {
      await tester.pumpWidget(MaterialApp(home: GamePage(viewModel: model)));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyW);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowUp);
      final before = game.menus.last.selected;
      for (var frame = 0; frame < 11; frame++) {
        model.advanceFrame();
      }
      expect(game.menus.last.selected, isNot(before));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyW);
      final after = game.menus.last.selected;
      for (var frame = 0; frame < 20; frame++) {
        model.advanceFrame();
      }
      expect(game.menus.last.selected, after);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      model.dispose();
      await flush(tester, repository);
      await tester.runAsync(() => directory.delete(recursive: true));
    }
  });
}

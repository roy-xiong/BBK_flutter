import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bbk_flutter/games/sgby/data/repositories/game_save_repository.dart';
import 'package:bbk_flutter/games/sgby/ui/features/game/view_models/game_view_model.dart';
import '../support/game_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('真实ViewModel自动写入第一档，保存20万兵力和当前隐藏备份', () async {
    final directory = await Directory.systemTemp.createTemp(
      'sgby-cheat-autosave-',
    );
    final saves = GameSaveRepository(directoryProvider: () async => directory),
        vm = GameViewModel(
          saves: GameSaveRepository(directoryProvider: () async => directory),
        );
    try {
      await vm.initialize();
      expect(vm.isReady, isTrue);
      final database = loadGameDatabase(),
          world = database.loadPeriod(1, seed: 1);
      database.beginGame(world, 5);
      vm.session!.replaceWorld(world);
      await vm.applyCheat('sgby_hide_special_generals');
      world.setPerson(64, world.person(64)!.copyWith(arms: 200000));
      vm.session!.completeStrategyTurn();
      vm.swipe(0);
      for (
        var i = 0;
        i < 200 &&
            (!await File('${directory.path}/games/sgby/slot_0.json').exists() ||
                vm.isBusy);
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      final loaded = await saves.load(0);
      expect(loaded, isNotNull);
      expect(loaded!.person(64)!.arms, 200000);
      expect(loaded.hiddenGenerals.length, 2);
      expect(await saves.load(1), isNull);
    } finally {
      vm.dispose();
      await vm.flushPersistence();
      await directory.delete(recursive: true);
    }
  });
  test('自动存档目录失效会提示失败，重试不阻塞后续存档', () async {
    final directory = await Directory.systemTemp.createTemp(
      'sgby-cheat-retry-',
    );
    final vm = GameViewModel(
      saves: GameSaveRepository(
        directoryProvider: () async {
          return directory;
        },
      ),
    );
    try {
      await vm.initialize();
      final d = loadGameDatabase(), w = d.loadPeriod(1, seed: 1);
      d.beginGame(w, 5);
      vm.session!.replaceWorld(w);
      // 初始化已经缓存目录；删除目录并改为文件，可靠模拟本次写入失败。
      final root = Directory('${directory.path}/games/sgby');
      await root.delete(recursive: true);
      await File(root.path).writeAsString('blocked');
      vm.session!.completeStrategyTurn();
      vm.swipe(0);
      for (var i = 0; i < 200 && vm.isBusy; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(vm.takeNotice(), contains('自动存档失败'));
      await File(root.path).delete();
      await root.create();
      vm.session!.completeStrategyTurn();
      vm.swipe(0);
      for (var i = 0; i < 200 && vm.isBusy; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(await File('${root.path}/slot_0.json').exists(), isTrue);
    } finally {
      vm.dispose();
      await directory.delete(recursive: true);
    }
  });
}

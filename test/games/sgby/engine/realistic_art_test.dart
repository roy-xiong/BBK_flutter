import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:bbk_flutter/games/sgby/data/repositories/game_save_repository.dart';
import 'package:bbk_flutter/games/sgby/domain/models/game_definition.dart';
import 'package:bbk_flutter/games/sgby/engine/rendering/cartoon_assets.dart';
import 'package:bbk_flutter/games/sgby/engine/rendering/baye_draw_command.dart';
import 'package:bbk_flutter/games/sgby/engine/rendering/cartoon_map_layout.dart';
import 'package:bbk_flutter/games/sgby/ui/features/game/view_models/game_view_model.dart';

import '../support/game_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('六兵种大面积红甲和青甲、全部头像绑定与图集释放', () async {
    final art = await CartoonAssets.load();
    try {
      final bytes = (await art.atlas.toByteData())!.buffer.asUint8List();
      for (final side in ['friendly', 'enemy']) {
        for (var type = 0; type < 6; type++) {
          final rect = art.spriteRect('unit/$side/$type')!;
          var opaque = 0, colored = 0;
          for (var y = rect.top.toInt(); y < rect.bottom.toInt(); y++) {
            for (var x = rect.left.toInt(); x < rect.right.toInt(); x++) {
              final p = (y * art.atlas.width + x) * 4;
              if (bytes[p + 3] < 100) continue;
              opaque++;
              final r = bytes[p], g = bytes[p + 1], b = bytes[p + 2];
              if (side == 'friendly'
                  ? r > g * 1.22 && r > b * 1.22
                  : g > r * 1.17 && b > r * 1.17) {
                colored++;
              }
            }
          }
          expect(
            colored / opaque,
            greaterThan(.35),
            reason: '$side 第$type兵种分色面积过小',
          );
        }
      }
      final db = loadGameDatabase(),
          bindings = art.manifest['portraitIds'] as Map;
      for (var period = 1; period <= 4; period++) {
        final world = db.loadPeriod(period, seed: 1);
        for (var id = 0; id < world.persons.length; id++) {
          expect(
            bindings['portrait/$period/$id'],
            isNotNull,
            reason: '时期$period 人物$id头像缺失',
          );
        }
      }
      expect((art.manifest['portraitNames'] as Map).length, greaterThan(200));
      expect(
        (art.manifest['cities'] as List)
            .where((c) => c['on_land'] == true)
            .length,
        38,
      );
    } finally {
      art.dispose();
    }
    expect(art.spriteRect('unit/friendly/0'), isNull);
    art.dispose();
  });

  test('38城矩阵、视口和点击与黑白完全一致，城名不再按等级省略', () async {
    final directory = await Directory.systemTemp.createTemp('sgby-matrix-hit-');
    final vm = GameViewModel(
      saves: GameSaveRepository(directoryProvider: () async => directory),
    );
    try {
      await vm.initialize();
      vm.toggleCartoon();
      await vm.cartoonArtReady;
      final db = loadGameDatabase(), world = db.loadPeriod(1, seed: 1);
      db.beginGame(world, 5);
      world
        ..viewX = 0
        ..viewY = 0;
      vm.session!.replaceWorld(world);
      final layout = CartoonMapLayout(db);
      final nativeCities = vm.session!.canvas.commands
          .where((op) => op.kind == BayeDrawKind.picture && op.resource == 55)
          .toList();
      expect(nativeCities, hasLength(38));
      expect(layout.visibleCities(world.cities.length), hasLength(38));
      // 直接与黑白绘制器产出的图标位置比较，而不是与另一份经纬度表比较。
      for (final op in nativeCities) {
        final x = op.x ~/ 16, y = op.y ~/ 16;
        final id = db.constant(14)[y * db.mapWidth + x] - 1;
        expect(
          layout.cell(id),
          ui.Rect.fromLTWH(op.x - 4.0, op.y - 4.0, 16, 16),
        );
        expect(db.cityName(id), isNotEmpty);
      }
      for (var id = 0; id < 38; id++) {
        world
          ..cursorX = db.mapWidth - 1
          ..cursorY = db.mapHeight - 1;
        vm.session!.showStrategy();
        final at = layout.city(id)!;
        vm.tap(at.dx, at.dy);
        expect(vm.session!.renderer.selectedCity(world), id);
      }
      // 空格仍走原版点击和方向键；不再吸附到附近城池。
      world
        ..cursorX = 8
        ..cursorY = 8;
      vm.session!.showStrategy();
      vm.tap(1, 1);
      expect((world.cursorX, world.cursorY), (0, 0));
      vm.send(GameInput.right);
      expect((world.cursorX, world.cursorY), (1, 0));
      int? target;
      vm.session!.chooseCity((id) => target = id);
      final at = layout.city(22)!;
      vm.tap(at.dx, at.dy);
      vm.tap(at.dx, at.dy);
      expect(target, 22);
      vm.session!.showStrategy();
      world
        ..viewX = 2
        ..viewY = 1
        ..cursorX = 0
        ..cursorY = 0;
      final shifted = CartoonMapLayout(db, viewX: 2, viewY: 1).city(22)!;
      expect(shifted, at - const ui.Offset(32, 16));
      vm.tap(shifted.dx, shifted.dy);
      expect(vm.session!.renderer.selectedCity(world), 22);
      vm.session!.showStrategy();
      vm.toggleCartoon();
      world
        ..cursorX = 0
        ..cursorY = 0;
      vm.tap(shifted.dx, shifted.dy);
      expect(vm.session!.renderer.selectedCity(world), 22);
    } finally {
      vm.dispose();
      await vm.flushPersistence();
      await directory.delete(recursive: true);
    }
  });
}

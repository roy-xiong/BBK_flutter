import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:bbk_flutter/games/sgby/domain/models/game_battle.dart';
import 'package:bbk_flutter/games/sgby/domain/use_cases/battle_engine.dart';
import 'package:bbk_flutter/games/sgby/engine/rendering/battle_scene_renderer.dart';
import 'package:bbk_flutter/games/sgby/engine/rendering/baye_canvas.dart';
import '../support/game_database.dart';

/// 原 BBK battleUnitPicture 只替换核心船图 12/13/28/29，状态图仍优先。
void main() {
  test('河流显示红蓝六兵种、保留帧相位与已行动状态，开关不改变战场数据', () {
    final database = loadGameDatabase(),
        world = database.loadPeriod(1, seed: 1);
    final engine = BattleEngine(database), canvas = BayeCanvas(database);
    final renderer = BattleSceneRenderer(canvas, engine);
    final battle =
        GameBattle(
            mode: 0,
            city: 0,
            sourceCity: 1,
            way: 0,
            mapId: 113,
            playerFood: 1000,
            enemyFood: 1000,
            people: [
              5,
              ...List<int?>.filled(9, null),
              64,
              ...List<int?>.filled(9, null),
            ],
          )
          ..width = 12
          ..height = 9
          ..weather = 1
          ..map = (Uint8List(108)..fillRange(0, 108, 16));
    for (final side in [0, 10]) {
      for (final type in [0, 1, 2, 3, 4, 5]) {
        for (final active in [0, 1]) {
          for (final frame in [0, 1]) {
            final id = battle.people[side]!;
            world.setPerson(
              id,
              world.person(id)!.copyWith(armsType: type, equip0: 0, equip1: 0),
            );
            battle.units[0].state = battle.units[10].state = 8;
            final unit = battle.units[side]
              ..state = 0
              ..x = 2
              ..y = 2
              ..active = active;
            renderer.draw(
              world,
              battle,
              cursor: false,
              frame: frame,
              showTroopIcons: true,
            );
            final actual = canvas.snapshot();
            final expected = BayeCanvas(database)..restore(actual);
            expected.picture(4, 16, 32, 32, color: 200);
            expected.picture(
              5,
              type * 2 + (side == 0 ? 0 : 16) + (active == 0 ? frame : 0),
              32,
              32,
              color: side == 0 ? 128 : 255,
            );
            expect(
              canvas.snapshot(),
              expected.snapshot(),
              reason: '$side/$type/$active/$frame',
            );
            expect(
              (unit.x, unit.y, unit.active, unit.state),
              (2, 2, active, 0),
            );
            renderer.draw(world, battle, cursor: false, frame: frame);
            final disabled = canvas.snapshot();
            expected.restore(disabled);
            expected.picture(4, 16, 32, 32, color: 200);
            expected.picture(
              5,
              12 + (side == 0 ? 0 : 16) + (active == 0 ? frame : 0),
              32,
              32,
              color: side == 0 ? 128 : 255,
            );
            expect(canvas.snapshot(), expected.snapshot());
          }
        }
      }
    }
  });

  test('石阵/混乱专用图不被兵种开关覆盖，装备覆盖后的兵种参与显示', () {
    final database = loadGameDatabase(),
        world = database.loadPeriod(1, seed: 1);
    final engine = BattleEngine(database), canvas = BayeCanvas(database);
    final renderer = BattleSceneRenderer(canvas, engine);
    final battle =
        GameBattle(
            mode: 0,
            city: 0,
            sourceCity: 1,
            way: 0,
            mapId: 113,
            playerFood: 1000,
            enemyFood: 1000,
            people: [5, ...List<int?>.filled(19, null)],
          )
          ..width = 12
          ..height = 9
          ..weather = 1
          ..map = (Uint8List(108)..fillRange(0, 108, 16));
    final equipment = world.tools.indexWhere((tool) => tool.arm > 1);
    expect(equipment, greaterThanOrEqualTo(0));
    world.setPerson(
      5,
      world.person(5)!.copyWith(armsType: 0, equip0: equipment + 1, equip1: 0),
    );
    final type = engine.armType(world, 5);
    expect(type, isNot(0));
    battle.units[0]
      ..x = 2
      ..y = 2
      ..state = 0;
    renderer.draw(world, battle, cursor: false, showTroopIcons: true);
    final expected = BayeCanvas(database)..restore(canvas.snapshot());
    expected.picture(4, 16, 32, 32, color: 200);
    expected.picture(5, type * 2, 32, 32, color: 128);
    expect(canvas.snapshot(), expected.snapshot());
    for (final state in [1, 6]) {
      battle.units[0].state = state;
      renderer.draw(world, battle, cursor: false);
      final original = canvas.snapshot();
      renderer.draw(world, battle, cursor: false, showTroopIcons: true);
      expect(canvas.snapshot(), original);
    }
  });
}

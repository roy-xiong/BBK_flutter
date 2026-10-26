import '../../domain/models/game_battle.dart';
import '../../domain/models/game_world.dart';
import '../../domain/use_cases/battle_engine.dart';
import 'dart:typed_data';
import 'baye_canvas.dart';

/// 战场地图、兵种、异常状态、范围与底栏的原始资源绘制。
final class BattleSceneRenderer {
  BattleSceneRenderer(this.canvas, this.engine);
  final BayeCanvas canvas;
  final BattleEngine engine;

  /// FgtShowHlp：模板逐个替换百分号，四块文字绕过右上方人物头像。
  void information(GameWorld world, GameBattle battle) {
    final right = canvas.width - 6, bottom = canvas.height - 6;
    canvas.fill(5, 5, right - 1, bottom - 1);
    canvas.rectangle(4, 4, right, bottom);
    final index = battle.unitAt(battle.focusX, battle.focusY);
    if (index == null) {
      canvas.text(
        8,
        8,
        engine.resources.text(
          1,
          14 + battle.terrain(battle.focusX, battle.focusY).clamp(0, 7),
        ),
        left: 8,
        top: 8,
        right: right - 4,
        bottom: bottom - 4,
      );
      return;
    }
    final id = battle.people[index]!,
        p = world.person(battle.people[index]!)!,
        unit = battle.units[index],
        attributes = engine.attributes(world, battle, index);
    final x = right - 52, y = 8;
    canvas.rectangle(x, y, x + 50, y + 40);
    canvas.picture(47 + world.period, id, x + 13, y + 2);
    final name = engine.resources.personName(world.period, id);
    canvas.text(
      x + 26 - engine.resources.codec.encode(name).length * 3,
      y + 28,
      name,
    );
    final bytes = Uint8List.fromList(engine.resources.requiredItem(1, 13));
    void format(int value) {
      final offset = bytes.indexOf(37);
      if (offset < 0) return;
      final encoded = '$value'.codeUnits;
      for (var i = 0; i < encoded.length && offset + i < bytes.length; i++) {
        bytes[offset + i] = encoded[i];
      }
    }

    if (p.level < engine.resources.rule('maxLevel', 20)) {
      format(p.level);
    } else {
      bytes[5] = 77;
      bytes[6] = 88;
    }
    final types = engine.resources.requiredItem(1, 12),
        offset = attributes.type * 4;
    bytes.setRange(13, 17, types.sublist(offset, offset + 4));
    for (final value in [
      p.force,
      p.iq,
      p.experience,
      unit.hp,
      unit.mp,
      attributes.attack,
      attributes.defence,
      p.arms,
    ]) {
      format(value);
    }
    final text =
        engine.resources.codec.decode(bytes) +
        engine.resources.text(1, 28 + unit.state.clamp(0, 7));
    canvas.textAround(
      text,
      (8, 6, right - 2, bottom - 2),
      (x - 2, y, x + 50, y + 42),
    );
  }

  /// FgtShowView/FgtViewForce：左右切换双方，名单按战场槽位分页，位置点独立闪烁。
  void situation(
    GameWorld world,
    GameBattle battle,
    int side,
    int top, {
    bool blink = false,
  }) {
    canvas.clear();
    final half = canvas.width ~/ 2,
        sx = (canvas.width ~/ 2 - battle.width) ~/ 2,
        sy = (canvas.height - battle.height) ~/ 2 + 20;
    canvas.text(5, 3, engine.resources.text(1, 49));
    final day = Uint8List.fromList(engine.resources.requiredItem(1, 48));
    final digits = '${battle.day}'.codeUnits;
    for (var i = 0; i < digits.length; i++) {
      day[3 + i] = digits[i];
    }
    day[3 + digits.length] = 32;
    canvas.textBytes(5, 17, day);
    canvas.text((half - 48) ~/ 2, sy - 15, engine.resources.text(1, 54));
    canvas.rectangle(sx - 1, sy - 1, sx + battle.width, sy + battle.height);
    for (final unit in battle.units) {
      if (unit.state != 8) {
        canvas.dot(sx + unit.x, sy + unit.y, blink ? 0 : 255);
      }
    }
    canvas.fill(half, 0, canvas.width - 1, canvas.height - 1);
    canvas.rectangle(half, 0, canvas.width - 1, canvas.height - 1);
    // 当前旧内核的SysLine为空实现，这两条FgtViewForce分隔线实际不显示。
    final leader = battle.people[side * 10];
    if (leader != null) {
      final name = engine.resources.personName(
        world.period,
        world.person(leader)!.belong - 1,
      );
      canvas.text(
        half +
            canvas.width ~/ 4 -
            (engine.resources.codec.encode(name).length + 2) * 3,
        2,
        '$name${engine.resources.text(1, 50)}',
      );
    }
    final food = side == 0
        ? '${battle.playerFood}'
        : battle.enemyFoodKnown == 0
        ? engine.resources.text(1, 53)
        : '${battle.enemyFoodKnown}';
    final prefix = engine.resources.requiredItem(1, 52).take(5).toList();
    canvas.textBytes(half + 3, 16, [
      ...prefix,
      ...engine.resources.codec.encode(food),
      0,
    ]);
    final count = (canvas.height - 1 - 30) ~/ 12;
    for (var i = 0; i < count; i++) {
      final slot = side * 10 + top + i;
      if (slot >= side * 10 + 10) break;
      final id = battle.people[slot];
      if (id == null) break;
      final bytes = Uint8List(24)..fillRange(0, 24, 32),
          name = engine.resources.codec.encode(
            engine.resources.personName(world.period, id),
          ),
          arms = '${world.person(id)!.arms}'.codeUnits;
      bytes.setRange(0, name.length, name);
      bytes.setRange(8, 8 + arms.length, arms);
      bytes[8 + arms.length] = 0;
      canvas.textBytes(half + 3, 30 + i * 12, bytes);
    }
  }

  void draw(
    GameWorld world,
    GameBattle battle, {
    BattlePath? path,
    int? rangeSource,
    int? skill,
    int frame = 0,
    bool cursor = true,
    bool showTroopIcons = false,
    int? selected,
  }) {
    canvas.clear();
    final rows = canvas.height ~/ 16 - 1, columns = canvas.width ~/ 16;
    for (var row = 0; row < rows; row++) {
      for (var column = 0; column < columns; column++) {
        final x = battle.viewX + column, y = battle.viewY + row;
        if (x >= battle.width || y >= battle.height) continue;
        canvas.picture(
          4,
          battle.map[y * battle.width + x],
          column * 16,
          row * 16,
          color: 200,
        );
      }
    }
    for (var i = 0; i < 20; i++) {
      final unit = battle.units[i], person = battle.people[i];
      if (person == null || unit.state == 8) continue;
      final x = (unit.x - battle.viewX) * 16, y = (unit.y - battle.viewY) * 16;
      if (x < 0 || y < 0 || x >= columns * 16 || y >= rows * 16) continue;
      var picture = unit.state == 6 || unit.state == 1
          ? 14
          : battle.terrain(unit.x, unit.y) == 7 && !showTroopIcons
          ? 12
          : engine.armType(world, person) * 2;
      if (i >= 10) picture += 16;
      if (unit.active == 0) picture += frame;
      canvas.picture(5, picture, x, y, color: i < 10 ? 128 : 255);
      if (unit.state == 2 || unit.state == 3) {
        canvas.picture(34, (unit.state == 2 ? 2 : 4) + frame, x, y);
      }
    }
    for (var row = 0; row < rows; row++) {
      for (var column = 0; column < columns; column++) {
        final mx = battle.viewX + column, my = battle.viewY + row;
        if (path != null && path.valueAt(mx, my) > 0 && path.contains(mx, my)) {
          canvas.picture(7, 0, column * 16, row * 16);
        }
        if (rangeSource != null) {
          final mask = engine.range(world, battle, rangeSource, skill: skill),
              unit = battle.units[rangeSource];
          final x = mx - unit.x + (mask.size >> 1),
              y = my - unit.y + (mask.size >> 1);
          if (x >= 0 &&
              y >= 0 &&
              x < mask.size &&
              y < mask.size &&
              mask.values[y * mask.size + x] == 1) {
            canvas.picture(7, 1, column * 16, row * 16);
          }
        }
      }
    }
    final barY = canvas.height - 16;
    canvas.fill(0, barY, canvas.width - 1, canvas.height - 1);
    canvas.picture(8, 0, 0, barY);
    canvas.text(
      14,
      barY + 3,
      battle.playerFood < 1000
          ? '${battle.playerFood}'
          : (battle.playerFood % 1000).toString().padLeft(3, '0'),
    );
    canvas.picture(9, battle.weather - 1, 47, barY + 2);
    final focused = battle.unitAt(battle.focusX, battle.focusY);
    if (focused != null) {
      canvas.text(
        74,
        barY + 2,
        engine.resources.personName(world.period, battle.people[focused]!),
      );
    } else {
      final bytes = engine.resources.requiredItem(1, 7),
          type = battle.terrain(battle.focusX, battle.focusY);
      if (type < 8) {
        canvas.textBytes(74, barY + 2, bytes.sublist(type * 4, type * 4 + 4));
      }
    }
    if (cursor &&
        battle.focusX >= battle.viewX &&
        battle.focusY >= battle.viewY &&
        battle.focusX < battle.viewX + columns &&
        battle.focusY < battle.viewY + rows) {
      canvas.picture(
        7,
        4,
        (battle.focusX - battle.viewX) * 16,
        (battle.focusY - battle.viewY) * 16,
      );
    }
    // 只记录表现元数据，不写入原版像素或改变战场单位状态。
    canvas.markBase('battle', index: selected ?? -1);
  }
}

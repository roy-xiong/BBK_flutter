import 'dart:math' as math;

import '../../engine/core/original_random.dart';
import '../models/game_battle.dart';
import '../models/game_world.dart';
import 'battle_engine.dart';

/// FgtPkAi的敌方行动选择，包含原版移动评分、主将优先与计谋随机分支。
///
/// 玩家自动战斗复用其范围和伤害计算，但使用仓库增强脚本的独立选点策略。
/// 决策只在会话的行动边界调用，避免后台定时器与手动输入同时修改坐标。
final class BattleAi {
  BattleAi(this.engine);
  final BattleEngine engine;
  (int, int) _aim(GameBattle battle) =>
      battle.mode == 1 && engine.resources.rule('aiDefenceMode') == 0
      ? (battle.units[battle.mainGeneral].x, battle.units[battle.mainGeneral].y)
      : (battle.cityX, battle.cityY);
  int _distance(int x, int y, int tx, int ty) =>
      u8((x - tx).abs() + (y - ty).abs());

  BattleCommand? nextEnemy(GameWorld world, GameBattle battle) {
    final selected = selectEnemy(battle);
    if (selected == null) return null;
    moveEnemy(world, battle, selected, engine.path(world, battle, selected));
    return enemyCommand(world, battle, selected);
  }

  /// 只选择本次行动武将，供表现层在移动之前展示原版范围；此步不消费随机数。
  int? selectEnemy(GameBattle battle) {
    final aim = _aim(battle);
    int? selected;
    var distance = 255;
    for (var i = 10; i < 20; i++) {
      final unit = battle.units[i];
      if ([1, 6, 8].contains(unit.state) || unit.active != 0) continue;
      final value = _distance(unit.x, unit.y, aim.$1, aim.$2);
      if (value < distance) {
        selected = i;
        distance = value;
      }
    }
    return selected;
  }

  /// 移动和攻击决策保持C内核的调用顺序，中间可以插入等待而不改变随机流。
  void moveEnemy(
    GameWorld world,
    GameBattle battle,
    int source,
    BattlePath path,
  ) => _move(world, battle, source, path);

  BattleCommand enemyCommand(GameWorld world, GameBattle battle, int selected) {
    if (engine.resources.rule('aiAttackMethod') == 1) {
      final attack = _attack(world, battle, selected);
      if (attack != null) {
        return _skill(world, battle, selected, false) ?? attack;
      }
      return _skill(world, battle, selected, true) ??
          BattleCommand(selected, 3);
    }
    return _skill(world, battle, selected, false) ??
        _attack(world, battle, selected) ??
        BattleCommand(selected, 3);
  }

  ({int hurt, int? target}) _bestTarget(
    GameWorld world,
    GameBattle battle,
    int source,
  ) {
    var maximum = 0;
    int? target;
    for (var i = 0; i < 10; i++) {
      if (battle.units[i].state == 8 ||
          !engine.inRange(world, battle, source, i)) {
        continue;
      }
      if (i == battle.mainGeneral) return (hurt: 65535, target: i);
      final hurt = engine.attackHurt(world, battle, source, i);
      if (hurt > maximum) {
        maximum = hurt;
        target = i;
      }
    }
    return (hurt: maximum, target: target);
  }

  BattleCommand? _attack(GameWorld world, GameBattle battle, int source) {
    final result = _bestTarget(world, battle, source);
    return result.target == null
        ? null
        : BattleCommand(source, 0, target: result.target);
  }

  void _move(GameWorld world, GameBattle battle, int source, BattlePath path) {
    final unit = battle.units[source];
    if (battle.terrain(unit.x, unit.y) == 5) return;
    final originX = unit.x, originY = unit.y, aim = _aim(battle);
    var minDistance = 255,
        maximumHurt = 0,
        selectedX = originX,
        selectedY = originY;
    for (var x = path.useX; x < 15; x++) {
      for (var y = path.useY; y < 15; y++) {
        if (path.values[y * 15 + x] >= 128) continue;
        final bx = x - path.useX + path.left, by = y - path.useY + path.top;
        final terrain = battle.terrain(bx, by);
        if (terrain == 5 &&
            (battle.mode == 0 || engine.resources.rule('aiDefenceMode') == 1)) {
          unit.x = bx;
          unit.y = by;
          return;
        }
        final distance = _distance(bx, by, aim.$1, aim.$2);
        unit.x = bx;
        unit.y = by;
        final hurt = _bestTarget(world, battle, source).hurt;
        unit.x = originX;
        unit.y = originY;
        bool update;
        if (maximumHurt == 0) {
          maximumHurt = hurt;
          update = maximumHurt != 0 || minDistance > distance
              ? true
              : minDistance == distance
              ? world.random.next() % 10 != 0
              : false;
        } else if (hurt < maximumHurt) {
          update = false;
        } else if (hurt > maximumHurt) {
          update = true;
        } else if ([2, 3, 4, 5, 6].contains(terrain)) {
          update = true;
        } else if (engine.resources.rule('aiDefenceMode') == 1) {
          update =
              _distance(bx, by, battle.cityX, battle.cityY) <
              _distance(selectedX, selectedY, battle.cityX, battle.cityY);
        } else {
          update =
              _distance(bx, by, originX, originY) >
              _distance(selectedX, selectedY, originX, originY);
        }
        if (update) {
          minDistance = distance;
          maximumHurt = hurt;
          selectedX = bx;
          selectedY = by;
        }
      }
    }
    if (minDistance != 255) {
      unit.x = selectedX;
      unit.y = selectedY;
    }
  }

  BattleCommand? _skill(
    GameWorld world,
    GameBattle battle,
    int source,
    bool force,
  ) {
    if (battle.units[source].state == 2) return null;
    final person = world.person(battle.people[source]!)!;
    final random = u16(world.random.next());
    if (!force) {
      if (random % 150 > person.iq) return null;
      if (engine.armType(world, battle.people[source]!) != 5) {
        final maximum = engine.commands.maximumArms(person, world: world);
        final sum = maximum + (maximum >> 1);
        final bound = maximum > 65535 || world.hasLargeArmies ? sum : u16(sum);
        if (bound == 0 || world.random.next() % bound < person.arms) {
          return null;
        }
      }
    }
    final skills = engine.skills(world, battle, source);
    if (skills.isEmpty) return null;
    // 原FgtJiNeng把U16 SkillID缓冲交给gam_strlen，内置ID高字节为0，长度为1。
    final candidates = skills.take(1).toList();
    if (!force && engine.resources.rule('aiAttackMethod') == 0) {
      return _skillAim(
        world,
        battle,
        source,
        candidates[random % candidates.length],
      );
    }
    while (candidates.isNotEmpty) {
      final index =
          math
              .sqrt(
                world.random.next() % (candidates.length * candidates.length),
              )
              .floor() %
          candidates.length;
      final id = candidates.removeAt(index);
      if (id == 30) continue;
      final command = _skillAim(world, battle, source, id);
      if (command != null) return command;
    }
    return null;
  }

  BattleCommand? _skillAim(
    GameWorld world,
    GameBattle battle,
    int source,
    int skill,
  ) {
    if (engine.skillError(world, battle, source, skill) != 0) return null;
    for (var i = 0; i < 20; i++) {
      if (battle.units[i].state == 8 ||
          !engine.inRange(world, battle, source, i, skill: skill) ||
          !engine.skillTarget(world, battle, source, i, skill)) {
        continue;
      }
      // 旧版援兵/援军分支只检查阈值，不生成指令；保持相同控制流。
      if (skill == 17 || skill == 29) continue;
      return BattleCommand(source, 1, target: i, skill: skill);
    }
    return null;
  }

  /// 仓库chooseAutoBattleMove/Target：先比较7×7覆盖数，再比较敌距与移动距离。
  /// 普通攻击目标始终取战场顺序中的首名合法敌将，保持自动操作的原有选择。
  BattleCommand? nextPlayer(GameWorld world, GameBattle battle) {
    final plan = planPlayer(world, battle);
    if (plan == null) return null;
    battle.units[plan.command.source]
      ..x = plan.x
      ..y = plan.y;
    return plan.command;
  }

  /// 计算自动行动但不提交落点，供表现层复用原版的选将、范围、逐格光标和确认流程。
  ///
  /// 选将顺序与原增强脚本一致，优先行动离存活敌军最近的可操作将领。仅在计算攻击
  /// 范围时临时试放坐标，并在 finally 中归还；不会消耗随机数或留下半次移动。
  ({BattleCommand command, int x, int y, BattlePath path})? planPlayer(
    GameWorld world,
    GameBattle battle,
  ) {
    final enemies = <int>[
      for (var i = 10; i < 20; i++)
        if (battle.people[i] != null && battle.units[i].state != 8) i,
    ];
    int? selected;
    var nearest = 9007199254740991;
    for (var i = 0; i < 10; i++) {
      final unit = battle.units[i];
      if (battle.people[i] == null ||
          [1, 6, 8].contains(unit.state) ||
          unit.active != 0) {
        continue;
      }
      selected ??= i;
      for (final enemy in enemies) {
        final other = battle.units[enemy];
        final distance = _distance(unit.x, unit.y, other.x, other.y);
        if (distance < nearest) {
          nearest = distance;
          selected = i;
        }
      }
    }
    if (selected == null) return null;
    final unit = battle.units[selected],
        path = engine.path(world, battle, selected);
    if (enemies.isEmpty) {
      return (
        command: BattleCommand(selected, 3),
        x: unit.x,
        y: unit.y,
        path: path,
      );
    }
    final oldX = unit.x, oldY = unit.y;
    var bestX = oldX,
        bestY = oldY,
        bestCoverage = -1,
        bestDistance = 9007199254740991,
        bestTravel = -1;
    for (var row = path.useY; row < 15; row++) {
      for (var column = path.useX; column < 15; column++) {
        if (path.values[row * 15 + column] >= 128) continue;
        final x = column - path.useX + path.left,
            y = row - path.useY + path.top;
        if (x < 0 || y < 0 || x >= battle.width || y >= battle.height) continue;
        final distance = enemies
            .map(
              (id) => _distance(x, y, battle.units[id].x, battle.units[id].y),
            )
            .reduce(math.min);
        final coverage = engine.wideGroupAttack
            ? enemies
                  .where(
                    (id) =>
                        (battle.units[id].x - x).abs() <= 3 &&
                        (battle.units[id].y - y).abs() <= 3,
                  )
                  .length
            : 0;
        final travel = _distance(oldX, oldY, x, y);
        if (coverage > bestCoverage ||
            coverage == bestCoverage &&
                (distance < bestDistance ||
                    distance == bestDistance && travel > bestTravel)) {
          bestX = x;
          bestY = y;
          bestCoverage = coverage;
          bestDistance = distance;
          bestTravel = travel;
        }
      }
    }
    try {
      unit.x = bestX;
      unit.y = bestY;
      for (final enemy in enemies) {
        if (engine.inRange(world, battle, selected, enemy)) {
          return (
            command: BattleCommand(selected, 0, target: enemy),
            x: bestX,
            y: bestY,
            path: path,
          );
        }
      }
      return (
        command: BattleCommand(selected, 3),
        x: bestX,
        y: bestY,
        path: path,
      );
    } finally {
      unit.x = oldX;
      unit.y = oldY;
    }
  }
}

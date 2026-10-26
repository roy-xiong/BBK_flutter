import 'dart:math' as math;
import 'dart:typed_data';

import '../../engine/core/original_random.dart';
import '../../engine/resources/baye_database.dart';
import '../models/game_battle.dart';
import '../models/game_report.dart';
import '../models/game_world.dart';
import '../models/game_options.dart';
import 'strategy_commands.dart';

/// FgtCount/Fight/FightSub的数值与回合规则，不依赖Flutter、定时器或平台代码。
///
/// 每次操作返回需要显示的报告；动画由会话消费，不在计算过程中等待。
/// 8/16/32位截断与原版随机调用点均显式保留，浮点运算在C的float边界舍入。
final class BattleEngine {
  BattleEngine(this.resources, {GameOptions? options})
    : commands = StrategyCommands(resources, options: options);
  final BayeDatabase resources;
  final StrategyCommands commands;
  final ByteData _float = ByteData(4);
  bool invincible = false,
      oneHitKill = false,
      wideGroupAttack = false,
      freeMovement = false,
      foodProtection = false;
  void Function(int sourceBelong, int victimBelong, int loss)? onArmsLost;
  ({GameWorld world, GameBattle battle, BattleCommand command, int experience})?
  _pendingCommand;
  bool get hasPendingCommand => _pendingCommand != null;
  bool? lastSkillSucceeded;
  final Map<int, int> _statusSources = <int, int>{};
  double _f(double value) {
    _float.setFloat32(0, value, Endian.little);
    return _float.getFloat32(0, Endian.little);
  }

  int _sqrt(int value) => math.sqrt(math.max(0, value)).floor();
  bool _largeArmies(GameWorld world) =>
      world.hasLargeArmies ||
      commands.options?.enabled('enemyArmsLimitEnabled') == true;
  int armType(GameWorld world, int id) =>
      commands.armType(world, world.person(id)!);

  List<GameReport> initialize(GameWorld world, GameBattle battle) {
    _statusSources.clear();
    _pendingCommand = null;
    for (var i = 0; i < 20; i++) {
      final id = battle.people[i];
      if (id == null || world.person(id) == null) continue;
      final person = world.person(id)!;
      final unit = battle.units[i];
      if (person.arms <= 0) {
        unit
          ..state = 8
          ..hp = 0
          ..mp = 0
          ..move = 0
          ..active = 1;
        continue;
      }
      unit.state = 0;
      unit.hp = u16(
        (person.force * 80 ~/ 100 + person.iq * 30 ~/ 100 + person.level) *
            person.thew ~/
            100,
      );
      unit.mp = u16(
        (person.iq * 80 ~/ 100 + (_sqrt(person.force) >> 1) + person.level) *
            person.thew ~/
            100,
      );
      _movePower(world, battle, i);
    }
    if (battle.units.take(10).every((unit) => unit.state == 8)) {
      battle.result = 2;
      return [];
    }
    if (battle.units.skip(10).every((unit) => unit.state == 8)) {
      battle.result = 1;
      return [];
    }
    if (battle.mode == 2) {
      _countWinner(world, battle);
      return [];
    }
    final data = resources.requiredItem(battle.mapId);
    if (data.length < 16) throw const FormatException('战场地图头无效');
    battle.width = data[0];
    battle.height = data[2];
    if (battle.width < 5 ||
        battle.height < 5 ||
        16 + battle.width * battle.height > data.length) {
      throw const FormatException('战场地图尺寸无效');
    }
    battle.map = Uint8List.sublistView(
      data,
      16,
      16 + battle.width * battle.height,
    );
    final city = battle.map.indexOf(3);
    if (city < 0) throw const FormatException('战场地图缺少城池');
    battle.cityX = city % battle.width;
    battle.cityY = city ~/ battle.width;
    var attackX = battle.width - 5, attackY = battle.height - 5;
    switch (battle.way) {
      case 0:
        attackX = (battle.width >> 1) - 2;
        attackY = 0;
      case 1:
        attackY = 2;
      case 2:
        attackY = (battle.height >> 1) - 2;
      case 4:
        attackX = (battle.width >> 1) - 2;
      case 5:
        attackX = 2;
      case 6:
        attackX = 2;
        attackY = (battle.height >> 1) - 2;
      case 7:
        attackX = 0;
        attackY = 0;
    }
    final start = resources.constant(5);
    for (var i = 0; i < 20; i++) {
      final attacking = battle.mode == 1 ? i < 10 : i >= 10;
      final offset = (attacking ? battle.way : 8) * 20 + (i % 10) * 2;
      battle.units[i].x = u8(
        (attacking ? attackX : battle.cityX - 2) + start[offset],
      );
      battle.units[i].y = u8(
        (attacking ? attackY : battle.cityY - 2) + start[offset + 1],
      );
    }
    final reports = checkUnits(world, battle);
    checkEnd(battle, false);
    checkEnd(battle, true);
    // 原精修脚本在初始化移动力及死亡检查后才执行enterBattle。
    if (battle.result == 0) {
      battle.entered = true;
      for (final id in battle.people.whereType<int>()) {
        final person = world.person(id)!;
        if (person.arms <= 0) continue;
        battle.originalArmTypes[id] = person.armsType;
        final names = [
          person.equip0,
          person.equip1,
        ].map((tool) => tool == 0 ? '' : resources.toolName(tool - 1)).toList();
        var type = person.armsType;
        for (final name in names) {
          if (name == '赤兔') type = 4;
          if (name == '鬼谷子') type = 5;
        }
        if (names.every((name) => name == '赤兔' || name == '鬼谷子')) {
          type = person.force > person.iq
              ? 4
              : person.force < person.iq
              ? 5
              : (world.random.next() % 65536 < 32768 ? 4 : 5);
        }
        world.setPerson(id, person.copyWith(armsType: type));
      }
    }
    focus(battle, 0);
    return reports;
  }

  void finish(GameWorld world, GameBattle battle) {
    _pendingCommand = null;
    for (final entry in battle.originalArmTypes.entries) {
      final person = world.person(entry.key);
      if (person != null) {
        world.setPerson(entry.key, person.copyWith(armsType: entry.value));
      }
    }
    battle.originalArmTypes.clear();
  }

  void focus(GameBattle battle, int index) {
    final unit = battle.units[index];
    battle.focusX = unit.x;
    battle.focusY = unit.y;
    battle.viewX = (unit.x - 7).clamp(0, math.max(0, battle.width - 15));
    battle.viewY = (unit.y - 4).clamp(0, math.max(0, battle.height - 8));
  }

  void _countWinner(GameWorld world, GameBattle battle) {
    final random = world.random.next() % 101;
    final first = allArms(world, battle, 0), second = allArms(world, battle, 1);
    final bool loses;
    if (first > second) {
      loses = (first >> 1) > second
          ? random < 30
          : battle.playerFood > battle.enemyFood
          ? random < 40
          : random < 60;
    } else {
      loses = first < (second >> 1)
          ? random > 2
          : battle.playerFood > battle.enemyFood
          ? random > 30
          : random > 10;
    }
    battle.result = loses ? 2 : 1;
  }

  int allArms(GameWorld world, GameBattle battle, int side) {
    var sum = 0;
    for (var i = side * 10; i < side * 10 + 10; i++) {
      if (battle.units[i].state != 8) {
        sum += world.person(battle.people[i] ?? -1)?.arms ?? 0;
        if (!_largeArmies(world)) sum = u16(sum);
      }
    }
    return sum;
  }

  void _movePower(GameWorld world, GameBattle battle, int index) {
    final unit = battle.units[index];
    if (freeMovement && index < 10) {
      unit.move = 8;
      return;
    }
    if (unit.state == 3) {
      unit.move = 1;
      return;
    }
    final id = battle.people[index];
    if (id == null) return;
    final person = world.person(id)!;
    final moves = resources.constant(17);
    var value = moves[armType(world, id)];
    for (final equipment in [person.equip0, person.equip1]) {
      if (equipment > 0) {
        value = u8(value + (world.tool(equipment - 1)?.move ?? 0));
      }
    }
    unit.move = math.min(8, value);
  }

  BattlePath path(GameWorld world, GameBattle battle, int index) {
    _movePower(world, battle, index);
    final unit = battle.units[index],
        move = math.max(1, battle.units[index].move);
    final x = u8(unit.x + 1), y = u8(unit.y + 1);
    final left = x >= move ? x - move : 0, top = y >= move ? y - move : 0;
    final useX = x >= move ? 0 : move - x, useY = y >= move ? 0 : move - y;
    final width = move - useX + math.min(move - 1, battle.width - x);
    final height = move - useY + math.min(move - 1, battle.height - y);
    final values = Uint8List(225)..fillRange(0, 225, 255);
    final resistance = resources.constant(3),
        type = armType(world, battle.people[index]!);
    for (var row = 0; row < height; row++) {
      for (var column = 0; column < width; column++) {
        final tile = battle.map[(top + row) * battle.width + left + column];
        values[(useY + row) * 15 + useX + column] = freeMovement && index < 10
            ? 129
            : resistance[type * 46 + tile];
      }
    }
    void blockers(bool same) {
      for (var i = 0; i < 20; i++) {
        final other = battle.units[i];
        if (i == index ||
            other.state == 8 ||
            ((i < 10) == (index < 10)) != same) {
          continue;
        }
        final bx = u8(other.x - left + useX), by = u8(other.y - top + useY);
        if (bx > 15 || by > 15) continue;
        final offset = u8(by * 15 + bx);
        if (offset > 224) continue;
        values[offset] = 254;
        if (same || unit.state == 4) continue;
        if (bx > 0 && offset > 1) values[offset - 1] |= 160;
        if (bx < 14 && offset < 224) values[offset + 1] |= 160;
        if (by > 0 && offset > 14) values[offset - 15] |= 160;
        if (by < 14 && offset < 209) values[offset + 15] |= 160;
      }
    }

    blockers(false);
    final origin = (move - 1) * 16;
    values[origin] = move;
    var queue = <int>[origin];
    while (queue.isNotEmpty) {
      final next = <int>[];
      for (final point in queue) {
        final power = values[point];
        if (power < 2) continue;
        for (final direction in [-15, 15, -1, 1]) {
          final target = u8(point + direction);
          if (target > 224) continue;
          final cost = values[target];
          if (cost < 128 || cost == 254 || cost == 255) continue;
          var remaining = cost > 160 && power > cost - 160 ? 1 : 0;
          if (remaining == 0) {
            final total = u8(power + 128);
            remaining = total > cost ? total - cost : 0;
          }
          if (remaining > 0) {
            values[target] = remaining;
            next.add(target);
          }
        }
      }
      queue = next;
    }
    values[origin] = 0;
    blockers(true);
    if (unit.state == 4) blockers(false);
    return BattlePath(left, top, useX, useY, values);
  }

  /// 返回范围掩码；装备范围是按位OR，启用装备范围后替换兵种默认范围。
  ({int size, List<int> values}) range(
    GameWorld world,
    GameBattle battle,
    int index, {
    int? skill,
  }) {
    if (skill != null) {
      final data = resources.requiredItem(13), start = (skill - 1) * 81;
      return (size: 9, values: data.sublist(start, start + 81));
    }
    if (wideGroupAttack && index < 10) {
      return (size: 7, values: List<int>.filled(49, 1));
    }
    final person = world.person(battle.people[index]!)!;
    final tools = resources.requiredItem(66),
        extended = List<int>.filled(225, 0);
    var hasExtended = false;
    if (resources.rule('enableToolAttackRange') != 0) {
      for (final equipment in [person.equip0, person.equip1]) {
        if (equipment == 0) continue;
        final offset = (equipment - 1) * 66;
        if (offset + 66 > tools.length || tools[offset + 32] == 0) continue;
        hasExtended = true;
        for (var y = 0; y < 15; y++) {
          for (var x = 0; x < 15; x++) {
            if ((tools[offset + 2 + y * 2 + x ~/ 8] & (128 >> (x % 8))) != 0) {
              extended[y * 15 + x] = 1;
            }
          }
        }
      }
    }
    if (hasExtended) return (size: 15, values: extended);
    final data = resources.constant(1),
        start = armType(world, battle.people[index]!) * 25;
    return (size: 5, values: data.sublist(start, start + 25));
  }

  bool inRange(
    GameWorld world,
    GameBattle battle,
    int source,
    int target, {
    int? skill,
  }) {
    final mask = range(world, battle, source, skill: skill),
        from = battle.units[source],
        to = battle.units[target];
    final x = to.x - from.x + (mask.size >> 1),
        y = to.y - from.y + (mask.size >> 1);
    return x >= 0 &&
        y >= 0 &&
        x < mask.size &&
        y < mask.size &&
        mask.values[y * mask.size + x] == 1;
  }

  ({int attack, int defence, int type, int terrain, int canny}) attributes(
    GameWorld world,
    GameBattle battle,
    int index,
  ) {
    final person = world.person(battle.people[index]!)!,
        unit = battle.units[index];
    final type = armType(world, battle.people[index]!),
        terrain = battle.terrain(unit.x, unit.y).clamp(0, 7);
    double factor(int resource, int index) {
      final bytes = resources.constant(resource);
      return ByteData.sublistView(bytes).getFloat32(index * 4, Endian.little);
    }

    var atRatio = person.force, dfRatio = person.iq;
    if (resources.rule('enableCustomRatio') != 0) {
      atRatio = u16(
        person.iq * resources.rule('ratioOfAttToIQ') ~/ 10 +
            person.force * resources.rule('ratioOfAttToForce') ~/ 10 +
            person.age * resources.rule('ratioOfAttToAge') ~/ 10,
      );
      dfRatio = u16(
        person.iq * resources.rule('ratioOfDefenceToIQ') ~/ 10 +
            person.force * resources.rule('ratioOfDefenceToForce') ~/ 10 +
            person.age * resources.rule('ratioOfDefenceToAge') ~/ 10,
      );
    }
    final terrainData = resources.constant(4),
        raw = terrainData[type * 8 + terrain],
        modifier = raw >= 128 ? raw - 256 : raw;
    int adjust(int value) => modifier >= 0 && modifier <= 3
        ? value >> modifier
        : u16(value - u32(value * u32(modifier.clamp(-99, 99))) ~/ 100);
    final attack = adjust(
      u16(_f(atRatio * (person.level + 10) * factor(19, type)).truncate()),
    );
    var defence = adjust(
      u16(_f(dfRatio * (person.level + 10) * factor(20, type)).truncate()),
    );
    defence = u16(_f(defence * factor(21, terrain)).truncate());
    return (
      attack: attack,
      defence: defence,
      type: type,
      terrain: terrain,
      canny: u8(person.iq + person.level + 5),
    );
  }

  int attackHurt(GameWorld world, GameBattle battle, int source, int target) {
    if (invincible && source >= 10 && target < 10) return 0;
    if (oneHitKill && source < 10 && target >= 10) {
      return GameOptions.maximumPersonArms;
    }
    final from = attributes(world, battle, source),
        to = attributes(world, battle, target);
    if (to.defence == 0 && !_largeArmies(world)) return 10;
    if (wideGroupAttack && source < 10 && target >= 10) {
      const modifiers = [
        [1.0, 1.2, .8, 1.0, .7, 1.3],
        [.8, 1.0, 1.2, 1.0, .6, 1.2],
        [1.2, .8, 1.0, 1.0, 1.1, 1.2],
        [1.0, 1.0, 1.0, 1.0, 1.0, 1.0],
        [1.1, 1.3, .9, 1.0, 1.0, 1.5],
        [.6, .6, .6, .6, .6, .6],
      ];
      final base =
          (from.attack /
                  math.max(1, to.defence) *
                  (world.person(battle.people[source]!)!.arms >> 3))
              .floor();
      return ((base * modifiers[from.type][to.type]).floor() + 10).clamp(
        0,
        GameOptions.maximumPersonArms,
      );
    }
    if (_largeArmies(world)) {
      final bytes = resources.constant(18);
      final multiplier = ByteData.sublistView(
        bytes,
      ).getFloat32((from.type * 6 + to.type) * 4, Endian.little);
      final base = _f(
        _f(from.attack / math.max(1, to.defence)) *
            (world.person(battle.people[source]!)!.arms >> 3),
      );
      return (_f(base * multiplier).truncate() + 10).clamp(
        0,
        GameOptions.maximumPersonArms,
      );
    }
    var hurt = u16(
      _f(
        _f(from.attack / to.defence) *
            (world.person(battle.people[source]!)!.arms >> 3),
      ).truncate(),
    );
    final bytes = resources.constant(18),
        multiplier = ByteData.sublistView(
          bytes,
        ).getFloat32((from.type * 6 + to.type) * 4, Endian.little);
    hurt = u16(_f(hurt * multiplier).truncate());
    return u16(hurt + 10);
  }

  List<int> skills(GameWorld world, GameBattle battle, int index) {
    final id = battle.people[index]!, person = world.person(id)!;
    final result = <int>[];
    final unique = resources.requiredItem(14, world.period);
    // SkillID已扩展为U16；资源中同样为小端双字节。
    final special = id * 2 + 2 <= unique.length
        ? ByteData.sublistView(unique).getUint16(id * 2, Endian.little)
        : 0;
    if (special > 0 && special <= skillCount) result.add(special);
    if (person.belong == id + 1) result.add(30);
    final data = resources.constant(2), type = armType(world, id);
    var available = 0;
    while (available < 10 && data[type * 10 + available] != 0) {
      available++;
    }
    final count =
        (_f(available.toDouble() * person.level) /
                    (resources.rule('maxLevel', 20) + 1) +
                1)
            .truncate();
    for (var i = 0; i < count && i < 10 && result.length < 10; i++) {
      final skill = data[type * 10 + i];
      if (skill == 0) break;
      result.add(skill);
    }
    return result;
  }

  int get skillCount => resources.requiredItem(10).length ~/ 34;

  _BattleSkill _skill(int id) => _BattleSkill(resources.requiredItem(10), id);

  /// 提前取得本次计谋的目标顺序，表现层逐个播放时不重新选择或消费随机源。
  List<int> skillTargets(
    GameWorld world,
    GameBattle battle,
    int source,
    int target,
    int skill,
  ) {
    final result = <int>[target], data = _skill(skill);
    if ((data.aim & 2) != 0 && !const [22, 27, 30].contains(skill)) {
      for (var i = 0; i < 20; i++) {
        if (i == target || battle.people[i] == null) continue;
        if ((data.aim & 4) == 0 &&
            (battle.units[i].state == 8 ||
                !inRange(world, battle, source, i, skill: skill) ||
                !skillTarget(world, battle, source, i, skill))) {
          continue;
        }
        result.add(i);
      }
    }
    return result;
  }

  /// 粮草提示保留原版显示计算伤害的行为，实际扣除量仍由领域结算限制。
  int skillFoodDamage(
    GameWorld world,
    GameBattle battle,
    int source,
    int target,
    int skill,
  ) => _skillHurt(world, battle, source, target, skill).food;

  int skillError(GameWorld world, GameBattle battle, int source, int skill) {
    final data = _skill(skill), unit = battle.units[source];
    if (data.mp > unit.mp) return 6;
    final terrain = battle.terrain(unit.x, unit.y);
    if (terrain > 7 || data.ownLand[terrain] == 0) return 5;
    if (data.weather[battle.weather - 1] == 0) return 4;
    return 0;
  }

  bool skillTarget(
    GameWorld world,
    GameBattle battle,
    int source,
    int target,
    int skill,
  ) {
    final data = _skill(skill),
        unit = battle.units[target],
        same = (source < 10) == (target < 10);
    final terrain = battle.terrain(unit.x, unit.y);
    return terrain < 8 &&
        data.enemyType[armType(world, battle.people[target]!)] != 0 &&
        data.enemyLand[terrain] != 0 &&
        ((data.aim & 1) != 0) == same;
  }

  List<GameReport> beginDay(GameWorld world, GameBattle battle) {
    final reports = <GameReport>[];
    battle.day = u8(battle.day + 1);
    battle.enemyFoodKnown = 0;
    if (battle.day > battle.maxDays) {
      battle.result = battle.mode == 1 ? 2 : 1;
      return reports;
    }
    for (final unit in battle.units) {
      unit.active = 0;
    }
    if (resources.rule('batlleDisableWeatherChange') == 0) {
      battle.weather = world.random.next() % 5 + 1;
    }
    if (battle.enemyFood == 0) {
      battle.result = 1;
      reports.add(GameReport(resources.text(1, 38)));
    }
    if (battle.playerFood == 0) {
      battle.result = 2;
      reports
        ..clear()
        ..add(GameReport(resources.text(1, 37)));
    }
    if (battle.result != 0) return reports;
    for (var i = 0; i < 20; i++) {
      final unit = battle.units[i], id = battle.people[i];
      if (unit.state == 8 || id == null) continue;
      final person = world.person(id)!,
          recover = world.random.next() % 60 < (world.person(id)!.iq >> 1);
      if (unit.state == 6) {
        _loseArms(
          world,
          battle,
          null,
          i,
          person.arms >> 3,
          sourceBelong: _statusSources[id],
        );
      }
      if ([1, 2, 3, 6].contains(unit.state) && recover ||
          [4, 7].contains(unit.state) && !recover) {
        unit.state = 0;
        _statusSources.remove(id);
      }
    }
    return reports;
  }

  void consumeFood(GameWorld world, GameBattle battle) {
    final divisor = resources.rule('ratioOfFoodToArmsPerDay', 3);
    final first =
            _sqrt(allArms(world, battle, 0)) ~/ (divisor == 0 ? 3 : divisor),
        second =
            _sqrt(allArms(world, battle, 1)) ~/ (divisor == 0 ? 3 : divisor);
    if (!foodProtection) {
      battle.playerFood = math.max(0, battle.playerFood - first);
    }
    battle.enemyFood = math.max(0, battle.enemyFood - second);
  }

  /// 无界面调用可一次完成；原生会话按beginCommand/completeCommand逐步播放。
  List<GameReport> execute(
    GameWorld world,
    GameBattle battle,
    BattleCommand command,
  ) {
    beginCommand(world, battle, command);
    return completeCommand(world, battle).toList(growable: false);
  }

  /// 先结算命中、兵力与策略点，保留原版在伤害动画结束后才处理升级/死亡的顺序。
  void beginCommand(GameWorld world, GameBattle battle, BattleCommand command) {
    if (_pendingCommand != null) throw StateError('上一条战斗指令尚未结算');
    lastSkillSucceeded = null;
    final source = command.source, target = command.target;
    // 指令只在合法槽位和实际资源范围内执行；无效外部参数不改变激活状态。
    if (source < 0 ||
        source >= battle.people.length ||
        !const [0, 1, 3].contains(command.type)) {
      return;
    }
    if (command.type != 3 &&
        (target == null ||
            target < 0 ||
            target >= battle.people.length ||
            battle.people[target] == null)) {
      return;
    }
    if (command.type == 1 &&
        (command.skill == null ||
            command.skill! < 1 ||
            command.skill! > skillCount)) {
      return;
    }
    final id = battle.people[source];
    if (id == null || battle.units[source].state == 8 || battle.result != 0) {
      return;
    }
    battle.units[source].active = 1;
    var experience = 0;
    if (command.type == 0 && target != null) {
      experience = _attack(world, battle, source, target);
    } else if (command.type == 1 && target != null && command.skill != null) {
      experience = _executeSkill(world, battle, source, target, command.skill!);
    } else if (command.type == 3) {
      final person = world.person(id)!;
      final maximum = u8(
        (person.iq * 80 ~/ 100 + (_sqrt(person.force) >> 1) + person.level) *
            person.thew ~/
            100,
      );
      if (battle.units[source].mp < maximum) battle.units[source].mp++;
    }
    _pendingCommand = (
      world: world,
      battle: battle,
      command: command,
      experience: experience,
    );
  }

  /// 惰性事件流每次只处理一位武将，报告期间可暂停，不预先标记后续武将死亡。
  Iterable<GameReport> completeCommand(
    GameWorld world,
    GameBattle battle,
  ) sync* {
    final pending = _pendingCommand;
    if (pending == null) return;
    if (!identical(pending.world, world) ||
        !identical(pending.battle, battle)) {
      throw StateError('战斗会话已被替换');
    }
    try {
      final source = pending.command.source,
          id = battle.people[source]!,
          experience = pending.experience;
      if (experience != 0) {
        if (resources.rule('disableExpGrowing') == 0) {
          final person = world.person(id)!;
          world.setPerson(
            id,
            person.copyWith(experience: u8(person.experience + experience)),
          );
          if (source < 10) {
            yield GameReport(
              '${resources.text(1, 22)}$experience',
              kind: GameReportKind.graphic,
            );
          }
        }
        yield* _checkUnitSteps(world, battle);
      }
      final unit = battle.units[source];
      if (battle.mode == 1 &&
          source < 10 &&
          battle.terrain(unit.x, unit.y) == 5) {
        battle.result = 1;
      }
      if (battle.mode == 0 &&
          source >= 10 &&
          battle.terrain(unit.x, unit.y) == 5) {
        battle.result = 2;
      }
      checkEnd(battle, source >= 10);
    } finally {
      _pendingCommand = null;
    }
  }

  int _experience(
    GameWorld world,
    GameBattle battle,
    int source,
    int target,
    int hurt,
  ) {
    final difference = u32(
      world.person(battle.people[source]!)!.level -
          world.person(battle.people[target]!)!.level,
    );
    var value = _sqrt(hurt) >> 2;
    value = difference > 128
        ? u32(value - difference)
        : math.max(0, value - difference);
    return u32(value + 2);
  }

  int _loseArms(
    GameWorld world,
    GameBattle battle,
    int? source,
    int target,
    int hurt, {
    int? sourceBelong,
  }) {
    final person = world.person(battle.people[target]!)!,
        lost = math.min(world.person(battle.people[target]!)!.arms, hurt);
    world.setPerson(
      battle.people[target]!,
      person.copyWith(arms: person.arms - lost),
    );
    if (source != null) {
      sourceBelong = world.person(battle.people[source]!)?.belong;
    }
    if (lost > 0 && sourceBelong != null) {
      onArmsLost?.call(sourceBelong, person.belong, lost);
    }
    return lost;
  }

  int _attack(GameWorld world, GameBattle battle, int source, int target) {
    final hurt = attackHurt(world, battle, source, target);
    if (wideGroupAttack && source < 10 && target >= 10) {
      for (var i = 10; i < 20; i++) {
        if (i == target ||
            battle.people[i] == null ||
            battle.units[i].state == 8) {
          continue;
        }
        final from = battle.units[source], to = battle.units[i];
        if ((from.x - to.x).abs() <= 3 && (from.y - to.y).abs() <= 3) {
          _loseArms(world, battle, source, i, hurt);
        }
      }
    }
    final lost = _loseArms(world, battle, source, target, hurt);
    final difference = u8(
      world.person(battle.people[source]!)!.level -
          world.person(battle.people[target]!)!.level,
    );
    final bonus = difference > 224
        ? 24
        : difference == 0
        ? 16
        : 8;
    return u8(
      _experience(world, battle, source, target, lost) +
          (hurt != lost ? bonus : 0),
    );
  }

  ({int arms, int food}) _skillHurt(
    GameWorld world,
    GameBattle battle,
    int source,
    int target,
    int skill,
  ) {
    if (invincible && source >= 10 && target < 10) return (arms: 0, food: 0);
    if (oneHitKill && source < 10 && target >= 10) {
      return (arms: GameOptions.maximumPersonArms, food: 0);
    }
    final data = _skill(skill),
        from = attributes(world, battle, source),
        to = attributes(world, battle, target);
    int calculate(int value) {
      if (_largeArmies(world)) {
        var result = value.toDouble();
        for (final ratio in [
          data.weather[battle.weather - 1],
          data.enemyType[to.type],
          data.enemyLand[to.terrain],
          data.ownLand[from.terrain],
        ]) {
          result = _f(result * _f(ratio / 100));
        }
        return result.truncate().clamp(0, GameOptions.maximumPersonArms);
      }
      for (final ratio in [
        data.weather[battle.weather - 1],
        data.enemyType[to.type],
        data.enemyLand[to.terrain],
        data.ownLand[from.terrain],
      ]) {
        value = u16(_f(_f(ratio / 100) * value).truncate());
      }
      return value;
    }

    return (
      arms: oneHitKill && source < 10 && target >= 10
          ? GameOptions.maximumPersonArms
          : calculate(data.power),
      food: calculate(data.destroy).clamp(0, 65535),
    );
  }

  int _executeSkill(
    GameWorld world,
    GameBattle battle,
    int source,
    int target,
    int skill,
  ) {
    final data = _skill(skill),
        from = attributes(world, battle, source),
        to = attributes(world, battle, target);
    battle.units[source].mp = u16(battle.units[source].mp - data.mp);
    if (world.random.next() % (to.canny + 20) > (from.canny >> 1)) {
      lastSkillSucceeded = false;
      return 0;
    }
    lastSkillSucceeded = true;
    if (skill == 22) {
      battle.weather = world.random.next() % 5 + 1;
      return 8;
    }
    if (skill == 30) {
      battle.enemyFoodKnown = battle.enemyFood;
      return 8;
    }
    if (skill == 27) {
      var experience = 0;
      for (final delta in [(-1, 0), (0, -1), (1, 0), (0, 1)]) {
        final unit = battle.units[target],
            index = battle.unitAt(
              battle.units[target].x + delta.$1,
              battle.units[target].y + delta.$2,
            );
        if (index != null &&
            !((target < 10 && index < 10) || (target > 10 && index > 10)) &&
            unit.state != 8) {
          experience = u32(experience + _attack(world, battle, index, target));
        }
      }
      return u8(experience >> 1);
    }
    final hurt = _skillHurt(world, battle, source, target, skill);
    if (source < 10) {
      battle.enemyFood = math.max(0, battle.enemyFood - hurt.food);
    } else if (!foodProtection) {
      battle.playerFood = math.max(0, battle.playerFood - hurt.food);
    }
    int common(int index) {
      final unit = battle.units[index], id = battle.people[index]!;
      final calculated = _skillHurt(world, battle, source, index, skill);
      unit.state = unit.state == 8
          ? 8
          : invincible && source >= 10 && index < 10
          ? 0
          : data.state;
      if (unit.state == 6) {
        _statusSources[id] = world.person(battle.people[source]!)!.belong;
      } else {
        _statusSources.remove(id);
      }
      if (unit.state == 3) unit.move = 1;
      var changed = 0;
      if (calculated.arms == 0) {
        return u8(_experience(world, battle, source, index, 0));
      } else if ((data.aim & 1) != 0) {
        final person = world.person(id)!,
            maximum = commands.maximumArms(world.person(id)!, world: world);
        final next = _largeArmies(world) && person.arms >= maximum
            ? person.arms
            : math.min(maximum, person.arms + calculated.arms);
        changed = _largeArmies(world)
            ? next - person.arms
            : u16(next - person.arms);
        world.setPerson(id, person.copyWith(arms: next));
      } else {
        changed = _loseArms(world, battle, source, index, calculated.arms);
      }
      return u8(_experience(world, battle, source, index, changed));
    }

    var experienceSum = common(target), lastTarget = target;
    if ((data.aim & 2) != 0) {
      for (var i = 0; i < 20; i++) {
        if (i == target || battle.people[i] == null) continue;
        if ((data.aim & 4) == 0 &&
            (battle.units[i].state == 8 ||
                !inRange(world, battle, source, i, skill: skill) ||
                !skillTarget(world, battle, source, i, skill))) {
          continue;
        }
        experienceSum = (experienceSum + common(i)).clamp(0, 65535);
        lastTarget = i;
      }
    }
    return u8(_experience(world, battle, source, lastTarget, experienceSum));
  }

  List<GameReport> checkUnits(GameWorld world, GameBattle battle) =>
      _checkUnitSteps(world, battle).toList(growable: false);
  Iterable<GameReport> _checkUnitSteps(
    GameWorld world,
    GameBattle battle,
  ) sync* {
    for (var i = 0; i < 20; i++) {
      final unit = battle.units[i], id = battle.people[i];
      if (unit.state == 8 || id == null) continue;
      var person = world.person(id)!;
      final random = world.random.next() % 3;
      if (person.experience > 99) {
        person = person.copyWith(
          experience: person.experience - 100,
          level: math.min(resources.rule('maxLevel', 20), u8(person.level + 1)),
        );
        world.setPerson(id, person);
        focus(battle, i);
        yield GameReport(
          resources.text(1, 39 + random),
          person: id,
          changeFrame: 0,
          previousState: unit.state,
        );
      }
      person = world.person(id)!;
      if (unit.hp == 0 || person.arms == 0) {
        final previous = unit.state;
        focus(battle, i);
        unit.state = 8;
        yield GameReport(
          resources.text(1, 42 + random),
          person: id,
          changeFrame: 6,
          previousState: previous,
        );
      }
    }
  }

  void checkEnd(GameBattle battle, bool enemyTurn) {
    if (battle.result != 0) return;
    if (battle.units[battle.mainGeneral].state == 8) {
      battle.result = battle.mainGeneral == 10 ? 1 : 2;
      return;
    }
    // 旧版flag=true从0遍历至20，并非只遍历前10，保留原边界。
    final start = enemyTurn ? 0 : 10;
    if (battle.units.skip(start).every((unit) => unit.state == 8)) {
      battle.result = enemyTurn ? 2 : 1;
    }
  }
}

/// 精修资源的技能属性使用原版packed结构，共34字节，不依赖平台对齐。
final class _BattleSkill {
  _BattleSkill(Uint8List data, int id)
    : bytes = Uint8List.sublistView(data, (id - 1) * 34, id * 34);
  final Uint8List bytes;
  int get aim => bytes[0];
  int get state => bytes[1];
  int get power => ByteData.sublistView(bytes).getUint16(2, Endian.little);
  int get destroy => ByteData.sublistView(bytes).getUint16(4, Endian.little);
  int get mp => bytes[6];
  List<int> get weather => bytes.sublist(7, 12);
  List<int> get enemyLand => bytes.sublist(12, 20);
  List<int> get ownLand => bytes.sublist(20, 28);
  List<int> get enemyType => bytes.sublist(28, 34);
}

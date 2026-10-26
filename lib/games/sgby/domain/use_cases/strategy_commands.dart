import 'dart:math' as math;
import 'dart:typed_data';

import '../../engine/core/original_random.dart';
import '../../engine/resources/baye_database.dart';
import '../models/game_order.dart';
import '../models/game_person.dart';
import '../models/game_world.dart';
import '../models/game_options.dart';

/// 原版城市指令参数。未用到的目标和数量仍显式可空，避免0被误当成已选择目标。
final class StrategyAction {
  const StrategyAction({
    required this.command,
    required this.city,
    required this.person,
    this.target,
    this.amount,
    this.food,
    this.money,
    this.arms,
    this.slot,
  });
  final int command;
  final int city;
  final int person;
  final int? target;
  final int? amount;
  final int? food;
  final int? money;
  final int? arms;
  final int? slot;
}

/// 指令执行结果与原版报告队列，失败不推进任何状态或随机源。
final class StrategyResult {
  const StrategyResult(this.success, this.message, {this.reports = const []});
  final bool success;
  final String message;
  final List<String> reports;
}

/// citycmdb/c/d/e中城市命令的Dart领域实现。
///
/// 先验证目标、资源与订单容量，再提交一次状态变更。开垦/招商/治理/出巡等在
/// 下令时生效，订单仅负责月末归队；搜寻、外交、输送与移动在执行阶段结算。
final class StrategyCommands {
  StrategyCommands(this.resources, {this.options});
  final BayeDatabase resources;
  final GameOptions? options;
  int _word(int value) =>
      resources.rule('fixOverFlow16') != 0 ? value.clamp(0, 65535) : u16(value);
  String _str(int id) => resources.text(64, id);

  int moneyCost(int command) {
    final bytes = resources.constant(11);
    if (resources.rule('enable16bitConsumeMoney') != 0) {
      return command * 2 + 2 <= bytes.length
          ? ByteData.sublistView(bytes).getUint16(command * 2, Endian.little)
          : 0;
    }
    return command >= 0 && command < bytes.length ? bytes[command] : 0;
  }

  int thewCost(int command) {
    final bytes = resources.constant(10);
    return command >= 0 && command < bytes.length ? bytes[command] : 0;
  }

  /// 邻城次序来自原版CITY_LINKR，各记录前8字节为1基城池编号。
  List<int> neighbours(int city) {
    final output = <int>[];
    {
      final data = resources.requiredItem(59);
      final offset = city * 16;
      if (offset < 0 || offset + 8 > data.length) return output;
      for (var i = offset; i < offset + 8; i++) {
        final target = data[i] - 1;
        if (target >= 0 && !output.contains(target)) output.add(target);
      }
    }
    return output;
  }

  /// SearchRoad可穿过己方城池，目的地必须能进入；返回曼哈顿格距而非图的边数。
  int? distance(GameWorld world, int source, int target) {
    final origin = world.city(source);
    final destination = world.city(target);
    if (origin == null || destination == null || source == target) return null;
    final visited = <int>{source};
    final queue = <int>[source];
    for (var cursor = 0; cursor < queue.length; cursor++) {
      for (final next in neighbours(queue[cursor])) {
        final city = world.city(next);
        if (city == null ||
            city.belong != origin.belong ||
            !visited.add(next)) {
          continue;
        }
        if (next == target) {
          final coordinates = resources.constant(6);
          return (coordinates[source * 2] - coordinates[target * 2]).abs() +
              (coordinates[source * 2 + 1] - coordinates[target * 2 + 1]).abs();
        }
        queue.add(next);
      }
    }
    return null;
  }

  int maximumArms(GamePerson person, {GameWorld? world}) {
    if (options?.enabled('enemyArmsLimitEnabled') == true &&
        world != null &&
        person.belong > 0 &&
        person.belong != 65535 &&
        person.belong != (world.playerRulerIndex ?? -1) + 1) {
      return options!.enemyArmsLimit;
    }
    return resources.rule('enableCustomRatio') == 0
        ? u16(person.level * 100 + person.force * 10 + person.iq * 10)
        : math.min(
            65534,
            person.level * resources.rule('ratioOfArmsToLevel') +
                person.age * resources.rule('ratioOfArmsToAge') +
                person.iq * resources.rule('ratioOfArmsToIQ') +
                person.force * resources.rule('ratioOfArmsToForce'),
          );
  }

  /// 装备兵种覆盖按两件装备的顺序应用，与GetArmType保持一致。
  int armType(GameWorld world, GamePerson person) {
    var type = person.armsType;
    for (final equipment in [person.equip0, person.equip1]) {
      final value = equipment == 0 ? 0 : world.tool(equipment - 1)?.arm ?? 0;
      type = switch (value) {
        0 => type,
        1 => 3,
        2 => 5,
        3 => 4,
        _ => value - 4,
      };
    }
    return type.clamp(0, 5);
  }

  /// 出征提交复用独立的30个出征槽，不将Person字段误当作武将编号。
  StrategyResult expedition(
    GameWorld world,
    int cityIndex,
    int targetIndex,
    List<int> fighters,
    int food, {
    bool attackAnyCity = false,
  }) {
    final city = world.city(cityIndex), target = world.city(targetIndex);
    if (city == null ||
        target == null ||
        city.belong != (world.playerRulerIndex ?? -1) + 1 ||
        target.belong == city.belong ||
        fighters.isEmpty ||
        fighters.length > 10) {
      return const StrategyResult(false, '请选择有效的出征城市和武将');
    }
    if (city.money < moneyCost(27)) return StrategyResult(false, _str(59));
    if (food <= 0 || food > city.food) {
      return const StrategyResult(false, '粮草不足');
    }
    final available = world.personsInCity(cityIndex, belong: city.belong);
    if (fighters.toSet().length != fighters.length ||
        fighters.any((id) => !available.contains(id))) {
      return StrategyResult(false, _str(84));
    }
    // 选将面板和最终提交均校验；旧局面或中途修改兵力后不能把空编部队加入队列。
    if (fighters.any((id) => (world.person(id)?.arms ?? 0) <= 0)) {
      return const StrategyResult(false, '兵力为0的武将不能出征');
    }
    if (!attackAnyCity && !neighbours(cityIndex).contains(targetIndex)) {
      return StrategyResult(false, _str(55));
    }
    final coordinates = resources.constant(6);
    final distance =
        (coordinates[cityIndex * 2] - coordinates[targetIndex * 2]).abs() +
        (coordinates[cityIndex * 2 + 1] - coordinates[targetIndex * 2 + 1])
            .abs();
    final order = GameOrder(
      orderId: 27,
      person: 0,
      city: cityIndex,
      object: targetIndex,
      arms: 0,
      food: food,
      money: 0,
      consume: 0,
      timeCount: distance,
    );
    if (!world.addFightOrder(order, fighters)) {
      return const StrategyResult(false, '出征命令队列已满');
    }
    world.setCity(
      cityIndex,
      city.copyWith(
        food: _word(city.food - food),
        money: _word(city.money - moneyCost(27)),
      ),
    );
    for (final id in fighters) {
      world.removePerson(cityIndex, id);
    }
    return const StrategyResult(true, '');
  }

  StrategyResult make(GameWorld world, StrategyAction action) {
    final command = action.command;
    final city = world.city(action.city);
    final person = world.person(action.person);
    if (city == null ||
        person == null ||
        city.belong != (world.playerRulerIndex ?? -1) + 1) {
      return StrategyResult(false, _str(54));
    }
    final direct = [7, 8, 9, 10, 12, 25].contains(command);
    if (!direct && world.orders.length >= 200) {
      return const StrategyResult(false, '命令队列已满');
    }
    final isCaptive =
        person.belong == 0xffff &&
        world.personsInCity(action.city).contains(action.person);
    if (!(person.belong == city.belong &&
            world.personsInCity(action.city).contains(action.person)) &&
        !([7, 8].contains(command) && isCaptive)) {
      return StrategyResult(false, _str(84));
    }
    final consumeCommand = command == 4
        ? 0
        : command == 26
        ? 24
        : command == 14 && resources.rule('fixThewOverFlow') == 0
        ? 13
        : command;
    final consumesThew = ![7, 8, 9, 10, 12, 25].contains(command);
    final consumesMoney =
        [1, 2, 3, 4, 5, 15, 16, 17, 19, 23].contains(command) ||
        command == 6 && resources.rule('fixConsumeMoney') != 0;
    if (consumesThew && person.thew < thewCost(consumeCommand)) {
      return StrategyResult(false, _str(60));
    }
    if (consumesMoney && city.money < moneyCost(consumeCommand)) {
      return StrategyResult(false, _str(59));
    }
    if (command == 1 && city.farming >= city.farmingLimit) {
      return StrategyResult(false, _str(52));
    }
    if (command == 2 && city.commerce >= city.commerceLimit) {
      return StrategyResult(false, _str(53));
    }
    if (command == 4 && city.state == 0 && city.avoidCalamity >= 100) {
      return StrategyResult(false, _str(61));
    }
    final target = action.target == null ? null : world.person(action.target!);
    final targetCity = action.target == null
        ? null
        : world.city(action.target!);
    if ([6, 15, 16, 17, 19].contains(command) && target == null) {
      return const StrategyResult(false, '请选择目标武将');
    }
    if (command == 6 &&
        (target!.belong != 0xffff ||
            !world.personsInCity(action.city).contains(action.target))) {
      return StrategyResult(false, _str(88));
    }
    if ([13, 14].contains(command) &&
        (targetCity == null ||
            targetCity.belong != city.belong ||
            distance(world, action.city, action.target!) == null)) {
      return StrategyResult(false, _str(55));
    }
    if (command == 23 &&
        (targetCity == null ||
            action.target == action.city ||
            targetCity.belong == city.belong)) {
      return StrategyResult(false, _str(58));
    }
    if ([11, 24, 25].contains(command) &&
        (action.amount == null || action.amount! < 0)) {
      return const StrategyResult(false, '数量无效');
    }
    if (command == 11) {
      final amount = action.amount!;
      if (action.slot == 0 && amount > city.money ~/ 5 ||
          action.slot == 1 && amount > city.food ||
          (action.slot != 0 && action.slot != 1)) {
        return const StrategyResult(false, '数量无效');
      }
    }
    if (command == 24) {
      if (city.money < moneyCost(command)) {
        return StrategyResult(false, _str(59));
      }
      final max = math.min(
        u16(city.peopleDevotion * resources.rule('armsPerDevotion', 20)),
        math.min(city.money * resources.rule('armsPerMoney', 10), 65534),
      );
      if (action.amount! > max) return const StrategyResult(false, '数量超过上限');
    }
    if (command == 25 &&
        action.amount! >
            math.min(
              math.max(maximumArms(person, world: world), person.arms),
              city.mothballArms + person.arms,
            )) {
      return const StrategyResult(false, '数量超过上限');
    }
    if (command == 13 &&
        ((action.food ?? -1) < 0 ||
            (action.money ?? -1) < 0 ||
            (action.arms ?? -1) < 0 ||
            action.food! > city.food ||
            action.money! > city.money ||
            action.arms! > city.mothballArms)) {
      return const StrategyResult(false, '物资数量无效');
    }
    if (command == 12 && city.money < moneyCost(12)) {
      return StrategyResult(false, _str(59));
    }
    if (command == 9) return _giveTool(world, action);
    if (command == 10) return _takeTool(world, action);
    if (command == 7) return _kill(world, action);
    if (command == 8) {
      world.setPerson(action.person, person.copyWith(belong: 0));
      world.addPerson(world.random.next() % world.cities.length, action.person);
      return const StrategyResult(true, '');
    }
    if (command == 12) {
      final thew = u8(person.thew + 50).clamp(0, 100);
      world.setCity(
        action.city,
        city.copyWith(money: _word(city.money - moneyCost(12))),
      );
      world.setPerson(
        action.person,
        person.copyWith(
          thew: thew,
          devotion: action.person != world.playerRulerIndex
              ? math.min(100, person.devotion + 1)
              : null,
        ),
      );
      return StrategyResult(true, _str(161));
    }
    if (command == 25) {
      world.setCity(
        action.city,
        city.copyWith(
          mothballArms: person.arms > 65535
              ? (city.mothballArms + person.arms - action.amount!).clamp(
                  0,
                  65535,
                )
              : u16(city.mothballArms + person.arms - action.amount!),
        ),
      );
      world.setPerson(action.person, person.copyWith(arms: action.amount));
      return const StrategyResult(true, '');
    }
    if (![
      1,
      2,
      3,
      4,
      5,
      6,
      11,
      13,
      14,
      15,
      16,
      17,
      19,
      23,
      24,
      26,
    ].contains(command)) {
      return const StrategyResult(false, '当前操作暂不可用');
    }
    var nextCity = city;
    var nextPerson = person;
    final reports = <String>[];
    switch (command) {
      case 1:
      case 2:
        final increase = u16(
          person.iq ~/ 10 * (world.random.next() % 4 + 2) + (person.iq >> 1),
        );
        nextCity = command == 1
            ? city.copyWith(
                farming: math.min(
                  city.farmingLimit,
                  u16(city.farming + increase),
                ),
              )
            : city.copyWith(
                commerce: math.min(
                  city.commerceLimit,
                  u16(city.commerce + increase),
                ),
              );
        reports.add(
          '${_str(command == 1 ? 113 : 116)}${command == 1 ? nextCity.farming : nextCity.commerce}${_str(114)}${u8(increase)}${_str(115)}',
        );
      case 3:
        reports.add(
          _str(
            (action.person == world.playerRulerIndex ? 145 : 142) +
                world.random.next() % 3,
          ),
        );
      case 4:
        final increase = 1 + world.random.next() % 4;
        nextCity = city.copyWith(
          state: 0,
          avoidCalamity: math.min(100, u8(city.avoidCalamity + increase)),
        );
        reports.add(
          '${_str(118)}${nextCity.avoidCalamity}${_str(114)}$increase${_str(115)}',
        );
      case 5:
        final increase = 1 + world.random.next() % 4;
        nextCity = city.copyWith(
          peopleDevotion: math.min(100, u8(city.peopleDevotion + increase)),
          population: math.min(
            city.populationLimit,
            u32(city.population + 100),
          ),
        );
        reports.add(
          '${_str(117)}${nextCity.peopleDevotion}${_str(114)}$increase${_str(115)}',
        );
      case 11:
        final amount = action.amount!;
        nextCity = action.slot == 0
            ? city.copyWith(
                food: _word(city.food + amount),
                money: _word(city.money - u16(amount * 5)),
              )
            : city.copyWith(
                food: _word(city.food - amount),
                money: math.min(30000, _word(city.money + u16(amount * 2))),
              );
      case 13:
        nextCity = city.copyWith(
          food: _word(city.food - action.food!),
          money: _word(city.money - action.money!),
          mothballArms: _word(city.mothballArms - action.arms!),
        );
        reports.add(_str(152));
      case 14:
        reports.add(_str(152));
      case 24:
        nextCity = city.copyWith(
          mothballArms: (city.mothballArms + action.amount!).clamp(0, 65535),
          money:
              (city.money -
                      action.amount! ~/
                          math.max(1, resources.rule('armsPerMoney', 10)))
                  .clamp(0, 65535),
        );
      case 26:
        reports.add(_str(148));
      default:
        break;
    }
    if (consumesThew) {
      nextPerson = nextPerson.copyWith(
        thew: u8(person.thew - thewCost(consumeCommand)),
      );
    }
    if (consumesMoney) {
      nextCity = nextCity.copyWith(
        money: _word(nextCity.money - moneyCost(consumeCommand)),
      );
    }
    world.setCity(action.city, nextCity);
    world.setPerson(action.person, nextPerson);
    final order = GameOrder(
      orderId: command,
      person: action.person,
      city: action.city,
      object: action.target ?? 0,
      food: action.food ?? 0,
      money: action.money ?? 0,
      arms: action.arms ?? 0,
      consume: 0,
      timeCount: [13, 14].contains(command)
          ? distance(world, action.city, action.target!) ?? 0
          : [15, 16, 17, 19].contains(command)
          ? 10
          : command == 23
          ? 1
          : 0,
    );
    world.addOrder(order);
    world.removePerson(action.city, action.person);
    return StrategyResult(true, '', reports: reports);
  }

  StrategyResult _kill(GameWorld world, StrategyAction action) {
    final person = world.person(action.person)!;
    if (person.belong != 0xffff) return StrategyResult(false, _str(88));
    for (final equipment in [person.equip0, person.equip1]) {
      if (equipment > 0) {
        world.addTool(action.city, equipment - 1, discovered: true);
      }
    }
    final report = _str(125 + world.random.next() % 3);
    world.removePerson(action.city, action.person);
    // 旧KillMake仅将俘虏从城池队列删除；保留其归属和装备字段的原始语义。
    return StrategyResult(true, report);
  }

  StrategyResult _giveTool(GameWorld world, StrategyAction action) {
    final index = action.target;
    final person = world.person(action.person)!;
    final tool = index == null ? null : world.tool(index);
    if (tool == null ||
        !world
            .goodsInCity(action.city, discoveredOnly: true)
            .any((v) => (v & 0x7fff) == index)) {
      return StrategyResult(false, _str(86));
    }
    if (person.equip0 != 0 && person.equip1 != 0) {
      return StrategyResult(false, _str(87));
    }
    var armsType = person.armsType;
    if (tool.useFlag != 0) {
      if (tool.arm == 2 && person.iq <= 105 ||
          tool.arm == 3 && person.force <= 105) {
        return StrategyResult(false, _str(109));
      }
      armsType = switch (tool.arm) {
        0 => armsType,
        1 => 3,
        2 => 5,
        3 => 4,
        _ => tool.arm - 4,
      };
    }
    final slot = person.equip0 == 0 ? 0 : 1;
    world.setPerson(
      action.person,
      person.copyWith(
        force: u8(person.force + tool.attack),
        iq: u8(person.iq + tool.iq),
        armsType: armsType,
        equip0: tool.useFlag == 0 && slot == 0 ? index! + 1 : null,
        equip1: tool.useFlag == 0 && slot == 1 ? index! + 1 : null,
      ),
    );
    world.removeTool(action.city, index!);
    if (action.person != world.playerRulerIndex) {
      final updated = world.person(action.person)!;
      world.setPerson(
        action.person,
        updated.copyWith(devotion: math.min(100, u8(updated.devotion + 8))),
      );
      return StrategyResult(true, _str(131 + world.random.next() % 3));
    }
    return const StrategyResult(true, '');
  }

  StrategyResult _takeTool(GameWorld world, StrategyAction action) {
    final person = world.person(action.person)!;
    final slot = action.slot;
    final equipment = slot == 0
        ? person.equip0
        : slot == 1
        ? person.equip1
        : 0;
    final tool = world.tool(equipment - 1);
    if (tool == null) return StrategyResult(false, _str(85));
    if (world.addTool(action.city, equipment - 1, discovered: true) == null) {
      return const StrategyResult(false, '道具队列已满');
    }
    world.setPerson(
      action.person,
      person.copyWith(
        force: u8(person.force - tool.attack),
        iq: u8(person.iq - tool.iq),
        equip0: slot == 0 ? 0 : null,
        equip1: slot == 1 ? 0 : null,
        devotion: action.person != world.playerRulerIndex
            ? math.max(0, person.devotion - 20)
            : null,
      ),
    );
    return StrategyResult(
      true,
      action.person == world.playerRulerIndex
          ? ''
          : _str(128 + world.random.next() % 3),
    );
  }

  /// 下令归队时校验人物当前势力和原城市归属，沿用仓库补丁的ReturnOrderPerson。
  void returnPerson(GameWorld world, GameOrder order) {
    final person = world.person(order.person);
    if (person == null ||
        world.cityOfPerson(order.person) != null ||
        person.belong == 0 ||
        person.belong == 65535) {
      return;
    }
    if (world.city(order.city)?.belong == person.belong) {
      world.addPerson(order.city, order.person);
      return;
    }
    final cities = world.citiesOf(person.belong - 1);
    if (cities.isNotEmpty) {
      world.addPerson(cities.first, order.person);
    } else if (world.city(order.city) != null) {
      world.setPerson(
        order.person,
        person.copyWith(oldBelong: person.belong, belong: 0),
      );
      world.addPerson(order.city, order.person);
    }
  }
}

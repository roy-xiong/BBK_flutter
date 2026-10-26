import 'dart:math' as math;

import '../../engine/core/original_random.dart';
import '../../engine/resources/baye_database.dart';
import '../models/game_order.dart';
import '../models/game_world.dart';
import '../models/game_options.dart';
import 'strategy_commands.dart';

/// 当前仓库ComputerTactic及AI世界活跃度补丁的Dart迁移。
///
/// 城市、人物和随机调用均按旧内核顺序遍历。无人城扩张、前线调兵独立于
/// 活跃度；普通策略保留旧版参数与共享武将指针行为，不能用新的AI启发式替换。
final class ComputerStrategy {
  ComputerStrategy(this.resources, {GameOptions? options})
    : commands = StrategyCommands(resources, options: options);
  final BayeDatabase resources;
  final StrategyCommands commands;

  void call(GameWorld world, {int activity = 50}) {
    activity = activity.clamp(0, 100);
    final levelSpeed = resources.rule('aiLevelUpSpeed');
    if (levelSpeed != 0) {
      for (var id = 0; id < world.persons.length; id++) {
        final chance = world.random.next() % 100;
        final person = world.person(id)!;
        if (chance < levelSpeed &&
            person.belong != (world.playerRulerIndex ?? -1) + 1 &&
            person.belong != 65535) {
          _levelUp(world, id);
        }
      }
    }
    final interior = resources.constant(12);
    final diplomacy = resources.constant(13);
    for (var cityId = 0; cityId < world.cities.length; cityId++) {
      var city = world.city(cityId)!.copyWith(state: 0);
      world.setCity(cityId, city);
      if (city.belong == 0 ||
          city.belong == (world.playerRulerIndex ?? -1) + 1) {
        continue;
      }
      city = city.copyWith(
        avoidCalamity: math.min(100, u8(city.avoidCalamity + 1)),
        food: city.food < 100 ? 500 : city.food,
        money: city.money > 10000 ? city.money ~/ 2 : city.money,
      );
      world.setCity(cityId, city);
      if (_advanceFront(world, cityId)) continue;
      final random = world.random.next() % 100;
      final character = world.person(city.belong - 1)?.character ?? 0;
      if (random < interior[character.clamp(0, interior.length - 1)]) {
        _interior(world, cityId);
        _harmonize(world, cityId);
      } else if (random < diplomacy[character.clamp(0, diplomacy.length - 1)]) {
        if (activity >= 25 || world.random.next() % 25 < activity) {
          _diplomacy(world, cityId, activity);
        }
      } else {
        if (activity >= 25 || world.random.next() % 25 < activity) {
          _armament(world, cityId, activity);
        }
      }
      if (activity > 25 && world.random.next() % 100 < _bonus(activity)) {
        if (world.random.next() % 2 != 0) {
          _diplomacy(world, cityId, activity);
        } else {
          _armament(world, cityId, activity);
        }
      }
    }
  }

  int _bonus(int activity) => activity <= 25 ? 0 : (activity - 25) * 100 ~/ 75;
  List<int> _people(GameWorld world, int city) =>
      world.personsInCity(city, belong: world.city(city)?.belong);
  List<int> _enemies(GameWorld world, int city) => commands
      .neighbours(city)
      .where((id) => world.city(id)?.belong != world.city(city)?.belong)
      .toList();
  int _priority(GameWorld world, int city) => world.city(city)?.belong == 0
      ? 0
      : world.city(city)?.belong == (world.playerRulerIndex ?? -1) + 1
      ? 1
      : 2;

  /// 多源BFS只计算战略排序距离，实际移动仍只返回下一座相邻己方城。
  List<int> _playerDistances(GameWorld world) {
    final distances = List<int>.filled(world.cities.length, 255);
    final queue = world.citiesOf(world.playerRulerIndex ?? -1);
    for (final id in queue) {
      distances[id] = 0;
    }
    for (var head = 0; head < queue.length; head++) {
      for (final next in commands.neighbours(queue[head])) {
        if (next >= distances.length || distances[next] != 255) continue;
        distances[next] = distances[queue[head]] + 1;
        queue.add(next);
      }
    }
    return distances;
  }

  int? _attackTarget(GameWorld world, int city) {
    final distances = _playerDistances(world);
    final candidates = <int>[];
    var bestPriority = 3, bestDistance = 255;
    for (final next in _enemies(world, city)) {
      final priority = _priority(world, next), distance = distances[next];
      if (priority < bestPriority ||
          priority == bestPriority && distance < bestDistance) {
        bestPriority = priority;
        bestDistance = distance;
        candidates.clear();
      }
      if (priority == bestPriority && distance == bestDistance) {
        candidates.add(next);
      }
    }
    int? weakest;
    var weakestArms = 65535;
    for (final next in candidates) {
      var arms = 0;
      for (final id in _people(world, next)) {
        arms += world.person(id)!.arms;
        if (!world.hasLargeArmies &&
            commands.options?.enabled('enemyArmsLimitEnabled') != true) {
          arms = u16(arms);
        }
      }
      for (final order in world.orders) {
        if (order.orderId != 14 && order.orderId != 27 && order.city == next) {
          arms += world.person(order.person)?.arms ?? 0;
          if (!world.hasLargeArmies &&
              commands.options?.enabled('enemyArmsLimitEnabled') != true) {
            arms = u16(arms);
          }
        }
      }
      if (weakest == null || weakestArms > arms) {
        weakest = next;
        weakestArms = arms;
      }
    }
    return weakest;
  }

  int? _frontHop(GameWorld world, int city) {
    final belong = world.city(city)?.belong;
    if (belong == null || belong == 0) return null;
    final playerDistances = _playerDistances(world);
    final hops = <int, int>{city: city}, distances = <int, int>{city: 0};
    final queue = <int>[city];
    int? bestCity;
    var bestPriority = 3, bestDistance = 255, bestOwnDistance = 255;
    for (var head = 0; head < queue.length; head++) {
      final current = queue[head];
      for (final next in commands.neighbours(current)) {
        if (world.city(next)?.belong == belong) {
          if (distances.containsKey(next)) continue;
          distances[next] = distances[current]! + 1;
          hops[next] = current == city ? next : hops[current]!;
          queue.add(next);
          continue;
        }
        final priority = _priority(world, next),
            distance = playerDistances[next];
        if (priority < bestPriority ||
            priority == bestPriority && distance < bestDistance ||
            priority == bestPriority &&
                distance == bestDistance &&
                distances[current]! < bestOwnDistance) {
          bestPriority = priority;
          bestDistance = distance;
          bestOwnDistance = distances[current]!;
          bestCity = current;
        }
      }
    }
    return bestCity == null || bestCity == city ? null : hops[bestCity];
  }

  GameOrder _order(
    int command,
    int city, {
    int person = 0,
    int target = 0,
    int food = 0,
  }) => GameOrder(
    orderId: command,
    person: person,
    city: city,
    object: target,
    arms: 0,
    food: food,
    money: 0,
    consume: 0,
    timeCount: 0,
  );

  bool _advanceFront(GameWorld world, int city) {
    final people = _people(world, city);
    if (people.isEmpty) return false;
    var target = _attackTarget(world, city);
    if (target != null && world.city(target)?.belong == 0) {
      if (world.orders.any(
        (order) =>
            order.orderId == 27 &&
            order.object == target &&
            world.city(order.city)?.belong == world.city(city)?.belong,
      )) {
        return true;
      }
      final count = math.min(10, people.length > 1 ? people.length - 1 : 1);
      _sortStrongest(world, people, count);
      final fighters = people.take(count).toList();
      if (!world.addFightOrder(
        _order(27, city, target: target, food: world.city(city)!.food),
        fighters,
      )) {
        return false;
      }
      for (final id in fighters) {
        world.removePerson(city, id);
      }
      return true;
    }
    target = _frontHop(world, city);
    if (target == null) return false;
    _sortStrongest(world, people, 1);
    if (!world.addOrder(
      _order(14, city, person: people.first, target: target),
      atEnd: true,
    )) {
      return false;
    }
    world.removePerson(city, people.first);
    return true;
  }

  /// 使用原版交换排序；同兵力人物不交换，保持选将次序与出征队首一致。
  void _sortStrongest(GameWorld world, List<int> people, int count) {
    for (var i = 0; i < count; i++) {
      for (var j = i + 1; j < people.length; j++) {
        if (world.person(people[j])!.arms <= world.person(people[i])!.arms) {
          continue;
        }
        final previous = people[i];
        people[i] = people[j];
        people[j] = previous;
      }
    }
  }

  void _submit(GameWorld world, GameOrder order) {
    if (world.addOrder(order)) world.removePerson(order.city, order.person);
  }

  void _interior(GameWorld world, int cityId) {
    for (final id in _people(world, cityId)) {
      final random = world.random.next() % 5;
      var city = world.city(cityId)!;
      final command = switch (random) {
        0 => 1,
        1 => 2,
        2 => 3,
        3 => 5,
        _ => 0,
      };
      if (command == 0) continue;
      if (random == 0) {
        city = city.copyWith(
          farming: math.min(city.farmingLimit, u16(city.farming + 200)),
        );
      }
      if (random == 1) {
        city = city.copyWith(
          commerce: math.min(city.commerceLimit, u16(city.commerce + 200)),
        );
      }
      if (random == 3) {
        city = city.copyWith(
          peopleDevotion: math.min(100, u8(city.peopleDevotion + 4)),
          population: math.min(
            city.populationLimit,
            u32(city.population + 100),
          ),
        );
      }
      world.setCity(cityId, city);
      _submit(world, _order(command, cityId, person: id, target: cityId));
    }
  }

  void _harmonize(GameWorld world, int cityId) {
    final people = _people(world, cityId);
    for (var index = 0; index < people.length; index++) {
      final random = world.random.next() % 7;
      if (random == 0) {
        final city = world.city(cityId)!;
        world.setCity(
          cityId,
          city.copyWith(
            state: 0,
            avoidCalamity: math.min(100, u8(city.avoidCalamity + 4)),
          ),
        );
        _submit(world, _order(4, cityId, person: people[index]));
      } else if (random == 5 && index >= 3) {
        final target = _frontHop(world, cityId);
        if (target != null) {
          _submit(
            world,
            _order(14, cityId, person: people[index], target: target),
          );
        }
      }
    }
  }

  List<int> _enemyPeople(GameWorld world, int king, int kind) {
    final output = <int>[];
    // 旧AI传入的是城市Belong；GetEnemy*内部仍比较king+1，保留该编号语义。
    for (var cityId = 0; cityId < world.cities.length; cityId++) {
      final city = world.city(cityId)!;
      if (city.belong == 0 || city.belong == king + 1) continue;
      if (kind == 0) {
        output.addAll(
          _people(world, cityId).where((id) => id + 1 != city.belong),
        );
      } else if (kind == 1) {
        if (city.satrapId != 0 && city.satrapId != city.belong) {
          output.add(city.satrapId - 1);
        }
      } else if (!output.contains(city.belong - 1)) {
        output.add(city.belong - 1);
      }
    }
    return output;
  }

  void _diplomacy(GameWorld world, int cityId, int activity) {
    for (final id in _people(world, cityId)) {
      var random = world.random.next() % 8;
      final bonus = _bonus(activity);
      if (bonus > 0 && world.random.next() % 100 < bonus) {
        random = 3 + world.random.next() % 4;
      }
      final captives = world.personsInCity(cityId, belong: 65535);
      if (captives.isNotEmpty) random = 0;
      if (random == 0) {
        if (captives.isNotEmpty) {
          final target = captives[world.random.next() % captives.length];
          world.setPerson(
            target,
            world.person(target)!.copyWith(belong: world.city(cityId)!.belong),
          );
        }
        continue;
      }
      if (random < 3 || random == 7) continue;
      final enemies = _enemyPeople(
        world,
        world.city(cityId)!.belong,
        random < 5
            ? 0
            : random == 5
            ? 1
            : 2,
      );
      if (enemies.isEmpty) continue;
      final target = enemies[world.random.next() % enemies.length];
      final command = const [15, 16, 17, 19][random - 3];
      _submit(world, _order(command, cityId, person: id, target: target));
    }
  }

  void _armament(GameWorld world, int cityId, int activity) {
    final people = _people(world, cityId);
    if (people.isEmpty) return;
    final selected = people[world.random.next() % people.length];
    if (resources.rule('aiLevelUpSpeed') == 0 && world.month % 3 == 0) {
      _levelUp(world, selected);
    }
    for (var index = 0; index < people.length; index++) {
      var random = world.random.next() % 9;
      var forced = false;
      if (index == 0 &&
          activity > 25 &&
          world.random.next() % 100 < (activity - 25) * 30 ~/ 75) {
        random = 7;
        forced = true;
      }
      if (random >= 1 && random <= 5) {
        final person = world.person(selected)!;
        world.setPerson(
          selected,
          person.copyWith(arms: commands.maximumArms(person, world: world)),
        );
        continue;
      }
      if (random != 7 || index >= 1) continue;
      final enemies = _enemies(world, cityId);
      if (enemies.isEmpty) continue;
      if (!forced &&
          world.random.next() % (enemies.length * 2) >= enemies.length) {
        continue;
      }
      final target = _attackTarget(world, cityId);
      if (target == null) continue;
      final fighters = _people(world, cityId);
      var count = fighters.length;
      // 保留旧版排序时按原pcount末位判断零兵力的行为，边界限制防止损坏存档下溢。
      for (var i = 0; i < count - 1; i++) {
        for (var j = i + 1; j < count; j++) {
          if (world.person(fighters[i])!.arms <
              world.person(fighters[j])!.arms) {
            final old = fighters[i];
            fighters[i] = fighters[j];
            fighters[j] = old;
          }
          if (world.person(fighters[people.length - 1])!.arms == 0 &&
              count > 0) {
            count--;
          }
        }
      }
      final minArms = activity >= 80
          ? 0
          : activity >= 50
          ? 800
          : 1000;
      final minPeople = activity >= 80
          ? 1
          : activity >= 50
          ? 3
          : 4;
      if (fighters.isEmpty ||
          world.person(fighters.first)!.arms < minArms ||
          count < minPeople) {
        continue;
      }
      count = math.min(10, count - (activity >= 80 ? 0 : 1));
      if (count <= 0) continue;
      final sent = fighters
          .take(count)
          .where((id) => (world.person(id)?.arms ?? 0) > 0)
          .toList();
      if (sent.isEmpty) continue;
      if (world.addFightOrder(
        _order(27, cityId, target: target, food: world.city(cityId)!.food),
        sent,
      )) {
        for (final id in sent) {
          world.removePerson(cityId, id);
        }
      }
      return;
    }
  }

  void _levelUp(GameWorld world, int id) {
    final person = world.person(id);
    if (person != null) {
      world.setPerson(
        id,
        person.copyWith(
          level: math.min(resources.rule('maxLevel', 10), u8(person.level + 1)),
        ),
      );
    }
  }
}

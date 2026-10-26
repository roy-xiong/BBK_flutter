import 'dart:math' as math;

import '../../engine/core/original_random.dart';
import '../../engine/resources/baye_database.dart';
import '../models/game_battle.dart';
import '../models/game_order.dart';
import '../models/game_report.dart';
import '../models/game_world.dart';
import 'strategy_commands.dart';

/// 战斗入口结果。需要玩家防守选将时保留原订单，不提前移走任何人物。
final class PreparedBattle {
  const PreparedBattle({this.battle, this.defenders, this.reports = const []});
  final GameBattle? battle;
  final List<int>? defenders;
  final List<GameReport> reports;
}

/// FightResultDeal的结果，玩家君主遭劫时由会话展示合法继承者供选择。
final class ResolvedBattle {
  const ResolvedBattle(this.reports, {this.lostRuler, this.heirs = const []});
  final List<GameReport> reports;
  final int? lostRuler;
  final List<int> heirs;
}

/// citycmdd的开战、占城、败军处置、逃跑路线与君主继承。
///
/// 被俘与战死保持不同处理：只有实际死亡回收装备并产生死亡事件，俘虏保留装备。
/// 退路和继承者均包括当前有效队列，避免把执行命令的武将误判为失踪或势力灭亡。
final class ResolveBattle {
  ResolveBattle(this.resources) : commands = StrategyCommands(resources);
  final BayeDatabase resources;
  final StrategyCommands commands;
  void Function(int person, int belong, int arms, int winnerBelong)?
  onGeneralDied;
  String _s(int id) => resources.text(64, id);
  String _name(GameWorld world, int id) =>
      resources.personName(world.period, id);

  PreparedBattle prepare(
    GameWorld world,
    GameOrder order, {
    List<int>? selectedDefenders,
  }) {
    final fighters = order.fighters
        .where((id) => (world.person(id)?.arms ?? 0) > 0)
        .take(10)
        .toList();
    // 旧存档或月度减兵可能使已在路上的武将归零。归队后从战场候选剔除，不能作为
    // 主将、守将、攻击目标或死亡统计来源；全队归零则取消此次战斗并退还剩余粮草。
    for (final id in order.fighters.where((id) => !fighters.contains(id))) {
      commands.returnPerson(world, order.copyWith(person: id));
    }
    if (fighters.isEmpty) {
      final source = world.city(order.city);
      final originalLeader = order.fighters.isEmpty
          ? null
          : world.person(order.fighters.first);
      if (source != null &&
          source.belong == (world.playerRulerIndex ?? -1) + 1 &&
          originalLeader?.belong == source.belong) {
        world.setCity(
          order.city,
          source.copyWith(food: math.min(65535, source.food + order.food)),
        );
      }
      // 与原版无有效部队时的处理一致：静默跳过，避免自动策略反复弹出取消提示。
      // 上方仍执行归队和退粮，零兵力人员不会进入战场或产生阵亡统计。
      return const PreparedBattle();
    }
    final city = world.city(order.object), first = fighters.firstOrNull;
    final attacker = first == null ? null : world.person(first);
    if (city == null || attacker == null) return const PreparedBattle();
    final reports = <GameReport>[];
    final player = (world.playerRulerIndex ?? -1) + 1;
    if (city.belong == 0 || city.belong == attacker.belong) {
      for (final id in fighters) {
        world.addPerson(order.object, id);
      }
      if (city.belong == 0) {
        world.setCity(
          order.object,
          world.city(order.object)!.copyWith(belong: attacker.belong),
        );
      }
      reports.add(
        GameReport(
          '',
          kind: GameReportKind.victory,
          actor: attacker.belong - 1,
          city: order.object,
        ),
      );
      return PreparedBattle(reports: reports);
    }
    final defending = city.belong == player;
    final available = world
        .personsInCity(order.object, belong: city.belong)
        .where((id) => (world.person(id)?.arms ?? 0) > 0)
        .toList();
    if (defending && selectedDefenders == null) {
      return PreparedBattle(defenders: available);
    }
    final people = List<int?>.filled(20, null);
    var mode = attacker.belong == player
        ? 1
        : defending
        ? 0
        : 2;
    List<int> defenders;
    if (defending) {
      defenders = (selectedDefenders ?? [])
          .where(available.contains)
          .take(10)
          .toSet()
          .toList();
    } else {
      defenders = List<int>.of(available);
      var count = defenders.length;
      for (var i = 0; i < count - 1; i++) {
        for (var j = i + 1; j < count; j++) {
          if (world.person(defenders[i])!.arms <
              world.person(defenders[j])!.arms) {
            final previous = defenders[i];
            defenders[i] = defenders[j];
            defenders[j] = previous;
          }
          if (world.person(defenders[count - 1])!.arms == 0) count--;
        }
      }
      defenders = defenders
          .take(count == 0 && defenders.isNotEmpty ? 1 : math.min(10, count))
          .toList();
    }
    for (var i = 0; i < fighters.length; i++) {
      people[(defending ? 10 : 0) + i] = fighters[i];
    }
    for (var i = 0; i < defenders.length; i++) {
      people[(defending ? 0 : 10) + i] = defenders[i];
      world.removePerson(order.object, defenders[i]);
    }
    final links = resources.requiredItem(59), positions = resources.constant(6);
    var way = 255;
    for (var i = 0; i < 8; i++) {
      if (links[order.object * 16 + i] == order.city + 1) {
        way = i;
        break;
      }
    }
    if (way >= 8) {
      final dx = positions[order.city * 2] - positions[order.object * 2],
          dy = positions[order.city * 2 + 1] - positions[order.object * 2 + 1];
      way = dy < 0
          ? dx < 0
                ? 7
                : dx > 0
                ? 1
                : 0
          : dy > 0
          ? dx < 0
                ? 5
                : dx > 0
                ? 3
                : 4
          : dx < 0
          ? 6
          : 2;
    }
    final battle = GameBattle(
      mode: mode,
      city: order.object,
      sourceCity: order.city,
      way: way,
      mapId: 110 + resources.constant(15)[order.object],
      playerFood: defending ? city.food : order.food,
      enemyFood: defending ? order.food : city.food,
      people: people,
    );
    battle.originalCityBelong = city.belong;
    battle.initialCaptives.addAll(
      world.personsInCity(order.object, belong: 65535),
    );
    return PreparedBattle(battle: battle, reports: reports);
  }

  /// 结算不删除订单，继承者查找需要看见其余仍未执行的出征与普通订单。
  ResolvedBattle call(
    GameWorld world,
    GameBattle battle, {
    int loserOutcome = 0,
    bool enemyEscapeRoute = false,
  }) {
    final reports = <GameReport>[];
    int? lostRuler;
    final won = battle.result == 1;
    final winners = battle.people
        .skip(won ? 0 : 10)
        .take(10)
        .whereType<int>()
        .toList();
    final losers = battle.people
        .skip(won ? 10 : 0)
        .take(10)
        .whereType<int>()
        .toList();
    if (battle.result == 0 || winners.isEmpty) return ResolvedBattle(reports);
    for (final id in winners) {
      world.addPerson(battle.city, id);
    }
    final captured = <int>[];
    void capture(int id) {
      _captive(world, id);
      captured.add(id);
    }

    final notice = GameReport(
      '',
      kind: won || battle.mode == 2
          ? GameReportKind.victory
          : GameReportKind.defeat,
      actor: world.person(winners.first)!.belong - 1,
      city: battle.city,
      person: !won && battle.mode != 2 ? world.playerRulerIndex : null,
    );
    if (won) reports.add(notice);
    if (won && (battle.mode == 1 || battle.mode == 2) ||
        !won && battle.mode == 0) {
      final old = world.city(battle.city)!;
      final stationed = world.personsInCity(battle.city, belong: old.belong);
      world.setCity(
        battle.city,
        old.copyWith(
          belong: world.person(winners.first)!.belong,
          satrapId: winners.first + 1,
        ),
      );
      for (final id in stationed) {
        final person = world.person(id)!,
            king = world.person(id)!.belong == id + 1;
        if (loserOutcome == 1) {
          if (king) lostRuler = id;
          _dead(world, id, battle.city);
          world.removePerson(battle.city, id);
        } else if (loserOutcome == 2) {
          if (king) lostRuler = id;
          capture(id);
        } else if (loserOutcome == 3) {
          world.removePerson(battle.city, id);
          if (!_escape(world, id, battle.city, enemyEscapeRoute)) {
            if (king) lostRuler = id;
            _wild(world, id, battle.city, true);
          }
        } else if (loserOutcome == 4) {
          if (king) lostRuler = id;
          _wild(world, id, battle.city, false);
        } else {
          if (king) {
            lostRuler = id;
            captured.add(id);
          }
          world.setPerson(
            id,
            person.copyWith(belong: king ? 65535 : 0, arms: 0),
          );
        }
      }
    }
    for (final id in losers) {
      final person = world.person(id)!,
          king = world.person(id)!.belong == id + 1;
      if (loserOutcome == 1) {
        if (king) lostRuler = id;
        _dead(world, id, battle.city);
        if (battle.mode != 2) {
          reports.add(GameReport('${_name(world, id)}${_s(108)}'));
        }
      } else if (loserOutcome == 2) {
        if (king) lostRuler = id;
        capture(id);
        world.addPerson(battle.city, id);
      } else if (loserOutcome == 3) {
        if (!_escape(world, id, battle.city, enemyEscapeRoute)) {
          if (king) lostRuler = id;
          _wild(world, id, battle.city, true);
        }
      } else if (loserOutcome == 4) {
        if (king) lostRuler = id;
        _wild(world, id, battle.city, true);
      } else {
        final random = world.random.next() % 100;
        if (random > person.iq) {
          if (king) lostRuler = id;
          capture(id);
          world.addPerson(battle.city, id);
        } else if (!_escape(world, id, battle.city, enemyEscapeRoute)) {
          if (king) lostRuler = id;
          if (random != 0 || resources.rule('disableFightToDeath') != 0) {
            capture(id);
            world.addPerson(battle.city, id);
          } else {
            _dead(world, id, battle.city);
            if (battle.mode != 2) {
              reports.add(GameReport('${_name(world, id)}${_s(108)}'));
            }
          }
        }
      }
    }
    if (!won) {
      reports.add(notice);
      if (battle.mode != 2 && captured.isNotEmpty) {
        reports.add(
          GameReport(
            '${_name(world, captured.last)}${_s(captured.length > 1 ? 107 : 106)}',
          ),
        );
      }
    }
    final city = world.city(battle.city)!;
    final food = battle.playerFood + battle.enemyFood;
    world.setCity(
      battle.city,
      city.copyWith(
        farming: city.farming - city.farming ~/ 20,
        commerce: city.commerce - city.commerce ~/ 20,
        money: city.money - city.money ~/ 20,
        peopleDevotion: city.peopleDevotion - city.peopleDevotion ~/ 10,
        food: resources.rule('fixOverFlow16') != 0
            ? food.clamp(0, 65535)
            : u16(food),
      ),
    );
    if (lostRuler == null) return ResolvedBattle(reports);
    reports.add(GameReport('${_s(78)}${_name(world, lostRuler)}${_s(79)}'));
    final heirs = _heirs(world, lostRuler);
    if (world.citiesOf(lostRuler).isEmpty || heirs.isEmpty) {
      for (final id in world.citiesOf(lostRuler)) {
        world.setCity(id, world.city(id)!.copyWith(belong: 0));
      }
      reports.add(GameReport('${_name(world, lostRuler)}${_s(83)}'));
      resources.assignSatraps(world);
      return ResolvedBattle(reports);
    }
    if (lostRuler == world.playerRulerIndex) {
      return ResolvedBattle(
        [...reports, GameReport(_s(80))],
        lostRuler: lostRuler,
        heirs: heirs,
      );
    }
    var heir = heirs.first;
    for (final id in heirs.skip(1)) {
      if (world.person(id)!.iq > world.person(heir)!.iq) heir = id;
    }
    inherit(world, lostRuler, heir, heirs);
    reports.add(GameReport('${_name(world, heir)}${_s(81)}'));
    return ResolvedBattle(reports);
  }

  void inherit(GameWorld world, int king, int heir, List<int> candidates) {
    if (!candidates.contains(heir)) return;
    for (final id in world.citiesOf(king)) {
      world.setCity(id, world.city(id)!.copyWith(belong: heir + 1));
    }
    for (final id in candidates) {
      final person = world.person(id)!;
      world.setPerson(
        id,
        person.copyWith(belong: heir + 1, devotion: id == heir ? 100 : null),
      );
    }
    if (world.playerRulerIndex == king) world.playerRulerIndex = heir;
    resources.assignSatraps(world);
  }

  List<int> _heirs(GameWorld world, int ruler) {
    final output = <int>[];
    void add(int id) {
      if (!output.contains(id) && world.person(id)?.belong == ruler + 1) {
        output.add(id);
      }
    }

    for (final city in world.citiesOf(ruler)) {
      for (final id in world.personsInCity(city, belong: ruler + 1)) {
        add(id);
      }
    }
    for (final order in world.orders) {
      if (order.orderId == 27) {
        for (final id in order.fighters) {
          add(id);
        }
      } else {
        add(order.person);
      }
    }
    return output;
  }

  bool _escape(GameWorld world, int person, int city, bool route) {
    final belong = world.person(person)!.belong;
    var cities = world.citiesOf(belong - 1);
    if (route && belong != (world.playerRulerIndex ?? -1) + 1) {
      cities = <int>[];
      final seen = <int>{city}, queue = <int>[city];
      for (var cursor = 0; cursor < queue.length; cursor++) {
        for (final next in commands.neighbours(queue[cursor])) {
          if (seen.contains(next) || world.city(next)?.belong != belong) {
            continue;
          }
          seen.add(next);
          queue.add(next);
          cities.add(next);
        }
      }
    }
    if (cities.isEmpty) return false;
    world.addPerson(cities[world.random.next() % cities.length], person);
    return true;
  }

  void _captive(GameWorld world, int id) {
    final person = world.person(id)!;
    world.setPerson(
      id,
      person.copyWith(oldBelong: person.belong, belong: 65535, arms: 0),
    );
  }

  void _wild(GameWorld world, int id, int city, bool add) {
    final person = world.person(id)!;
    world.setPerson(
      id,
      person.copyWith(oldBelong: person.belong, belong: 0, arms: 0),
    );
    if (add) world.addPerson(city, id);
  }

  void _dead(GameWorld world, int id, int city) {
    final person = world.person(id)!;
    if (person.belong != 0 && person.belong != 65535) {
      onGeneralDied?.call(
        id,
        person.belong,
        person.arms,
        world.city(city)!.belong,
      );
    }
    for (final equipment in [person.equip0, person.equip1]) {
      if (equipment > 0) world.addTool(city, equipment - 1, discovered: true);
    }
    world.setPerson(
      id,
      person.copyWith(
        oldBelong: person.belong,
        belong: 65535,
        arms: 0,
        equip0: 0,
        equip1: 0,
      ),
    );
  }
}

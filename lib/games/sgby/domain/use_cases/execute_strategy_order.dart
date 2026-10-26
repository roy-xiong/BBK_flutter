import 'dart:math' as math;
import 'dart:typed_data';

import '../../engine/core/original_random.dart';
import '../../engine/resources/baye_database.dart';
import '../models/game_order.dart';
import '../models/game_report.dart';
import '../models/game_world.dart';
import 'strategy_commands.dart';

/// 原版OrderExec的非战斗分支。调用方按订单队列顺序逐条执行并消费报告。
///
/// TimeCount由原版当前实现写入但PolicyExec并不扣减等待，此处同样逐月执行。
/// 报告随机数属于规则随机流，即使敌方报告不可见也保留原函数的随机调用次数。
final class ExecuteStrategyOrder {
  ExecuteStrategyOrder(this.resources, {required this.dialogs})
    : commands = StrategyCommands(resources);
  final BayeDatabase resources;
  final StrategyCommands commands;
  final Map<String, dynamic> dialogs;
  int _word(int value) =>
      resources.rule('fixOverFlow16') != 0 ? value.clamp(0, 65535) : u16(value);
  String _s(int index) => resources.text(64, index);

  List<GameReport> call(
    GameWorld world,
    GameOrder order, {
    int worldActivity = 50,
    bool diplomacyProtection = false,
  }) {
    final reports = <GameReport>[];
    final person = world.person(order.person);
    final city = world.city(order.city);
    if (person == null || city == null) return reports;
    final player = person.belong == (world.playerRulerIndex ?? -1) + 1;
    // 在结算时读取目标当前归属，兼容命令排队后易主；拦截也必须归还执行敌将。
    final target = world.person(order.object);
    final targetCity = order.orderId == 17
        ? world.cityOfPerson(order.object)
        : null;
    if (diplomacyProtection &&
        !player &&
        const [6, 15, 16, 17, 18, 19].contains(order.orderId) &&
        target != null &&
        (target.belong == (world.playerRulerIndex ?? -1) + 1 ||
            targetCity != null &&
                world.city(targetCity)?.belong ==
                    (world.playerRulerIndex ?? -1) + 1)) {
      commands.returnPerson(world, order);
      return reports;
    }
    void report(int who, String text) {
      reports.add(GameReport(text, person: who));
    }

    switch (order.orderId) {
      case 3:
        _search(world, order, reports);
      case 6:
        final target = world.person(order.object);
        if (target != null && target.belong != person.belong) {
          var success = false;
          if (world.random.next() % 100 <= person.iq - target.iq + 50) {
            final devotion = target.devotion;
            world.setPerson(
              order.object,
              target.copyWith(devotion: u8(devotion - devotion ~/ 10)),
            );
            final modulus = const [2, 5, 4, 3, 1][target.character.clamp(0, 4)];
            if (devotion <= 60 &&
                world.random.next() % 100 >= devotion ~/ modulus) {
              world.setPerson(
                order.object,
                world
                    .person(order.object)!
                    .copyWith(
                      belong: person.belong,
                      devotion: 40 + world.random.next() % 40,
                    ),
              );
              success = true;
            }
          }
          if (player) {
            report(
              order.object,
              success ? _s(95) : _s(122 + world.random.next() % 3),
            );
          }
        }
      case 13:
        final success = world.random.next() % 100 > 20;
        final destination = world.city(order.object);
        if (success && destination != null) {
          world.setCity(
            order.object,
            destination.copyWith(
              food: _word(destination.food + order.food),
              money: _word(destination.money + order.money),
              mothballArms: _word(destination.mothballArms + order.arms),
            ),
          );
        }
        report(order.person, _s(success ? 119 : 120));
      case 14:
        final destination = world.city(order.object);
        if (destination != null) {
          var target = order.object;
          if (destination.belong == 0) {
            world.setCity(target, destination.copyWith(belong: person.belong));
          } else if (destination.belong != person.belong) {
            target = order.city;
          }
          world.addPerson(target, order.person);
        }
      case 15:
      case 16:
      case 17:
      case 19:
        _diplomacy(world, order, reports, worldActivity);
      case 26:
        final food = u16((person.iq + person.force) * 5);
        final money = u16((person.iq + person.force) * 2);
        world.setCity(
          order.city,
          city.copyWith(
            peopleDevotion: city.peopleDevotion ~/ 2,
            farming: city.farming ~/ 2,
            commerce: city.commerce ~/ 2,
            food: _word(city.food + food),
            money: _word(city.money + money),
          ),
        );
        if (player) {
          report(order.person, '${_s(149)}$money${_s(150)}$food${_s(151)}');
        }
      case 27:
        throw StateError('出征订单必须交由战斗状态机处理');
      default:
        break;
    }
    commands.returnPerson(world, order);
    return reports;
  }

  void _search(GameWorld world, GameOrder order, List<GameReport> reports) {
    final person = world.person(order.person)!;
    final player = person.belong == (world.playerRulerIndex ?? -1) + 1;
    var branch = world.random.next() % 4;
    var quantity = 0;
    void report(int who, String text) {
      if (player) reports.add(GameReport(text, person: who));
    }

    switch (branch) {
      case 0:
        break;
      case 1:
        branch = 0;
        final random = world.random.next() % 150;
        if (random >= person.iq) break;
        if (random.isEven) {
          final people = world.personsInCity(order.city, belong: 0);
          if (people.isEmpty) break;
          final targetIndex = people[world.random.next() % people.length];
          final target = world.person(targetIndex)!;
          final data = resources.requiredItem(63, world.period);
          final offset = targetIndex * 4;
          final bole = offset + 4 <= data.length
              ? ByteData.sublistView(data).getUint16(offset + 1, Endian.little)
              : 0;
          var outcome = 0;
          if (bole - 1 == order.person) {
            outcome = 1;
          } else if (bole == 0) {
            outcome = world.random.next() % 110 < person.iq ? 1 : 2;
          }
          if (outcome == 1) {
            world.setPerson(
              targetIndex,
              target.copyWith(
                belong: person.belong,
                devotion: 70 + world.random.next() % 30,
              ),
            );
          }
          if (player) {
            branch = 1;
            if (outcome == 0) {
              report(order.person, _s(100));
            } else {
              report(
                order.person,
                _s(99) + resources.personName(world.period, targetIndex),
              );
              report(
                targetIndex,
                _s((outcome == 1 ? 134 : 138) + world.random.next() % 4),
              );
            }
          }
        } else {
          final goods = world
              .goodsInCity(order.city)
              .where((value) => value & 0x8000 == 0)
              .toList();
          if (goods.isEmpty) break;
          final targetIndex = goods[world.random.next() % goods.length];
          final conditions = resources.requiredItem(67, world.period);
          final offset = targetIndex * 4;
          final bole = offset + 4 <= conditions.length
              ? ByteData.sublistView(
                  conditions,
                ).getUint16(offset + 1, Endian.little)
              : 0;
          if (bole == 0 || bole - 1 == order.person) {
            if (player) {
              report(order.person, _s(99) + resources.toolName(targetIndex));
              branch = 1;
            }
            world.discoverTool(order.city, targetIndex);
          }
        }
      case 2:
      case 3:
        quantity = 10 + world.random.next() % math.max(1, person.iq * 2);
        final city = world.city(order.city)!;
        world.setCity(
          order.city,
          branch == 2
              ? city.copyWith(money: _word(city.money + quantity))
              : city.copyWith(food: _word(city.food + quantity)),
        );
    }
    if (player && branch != 1) {
      report(
        order.person,
        branch == 0 ? _s(101) : '${_s(100 + branch)}$quantity',
      );
    }
  }

  /// 参数和比较符保留原版边界，例如rand > chance时失败，等号仍可成功。
  void _diplomacy(
    GameWorld world,
    GameOrder order,
    List<GameReport> reports,
    int activity,
  ) {
    final person = world.person(order.person)!;
    final target = world.person(order.object);
    if (target == null) return;
    final player = person.belong == (world.playerRulerIndex ?? -1) + 1;
    final bonus = player || activity <= 25
        ? 0
        : (activity.clamp(0, 100) - 25) * 20 ~/ 75;
    int chance(int base, int addition) => (base + addition).clamp(0, 100);
    bool passed = false;
    final command = order.orderId;
    if (command == 19) {
      if (order.object != world.playerRulerIndex &&
          world.citiesOf(person.belong - 1).length >=
              world.citiesOf(target.belong - 1).length * 2 &&
          world.random.next() % 100 <=
              chance(person.iq - target.iq + 50, bonus ~/ 2) &&
          world.random.next() % 100 <=
              chance(
                const [10, 1, 20, 5, 15][target.character.clamp(0, 4)],
                bonus,
              )) {
        final conquered = world.citiesOf(order.object);
        for (final cityIndex in conquered) {
          final city = world.city(cityIndex)!;
          final people = world.personsInCity(cityIndex, belong: city.belong);
          world.setCity(cityIndex, city.copyWith(belong: person.belong));
          for (final index in people) {
            world.setPerson(
              index,
              world.person(index)!.copyWith(belong: person.belong),
            );
          }
        }
        for (var i = 0; i < world.persons.length; i++) {
          final subject = world.person(i)!;
          if (subject.belong == order.object + 1) {
            world.setPerson(
              i,
              subject.copyWith(belong: i == order.object ? person.belong : 0),
            );
          }
        }
        passed = true;
      }
      if (player) {
        reports.add(
          GameReport(
            _s((passed ? 157 : 153) + world.random.next() % 4),
            person: order.object,
          ),
        );
      }
      return;
    }
    final threshold = chance(
      person.iq - target.iq + (command == 16 ? 0 : 50),
      bonus ~/ 2,
    );
    if (world.random.next() % 100 <= threshold &&
        world.random.next() % 100 >=
            math.max(0, target.devotion - bonus ~/ 2)) {
      final rates = command == 15
          ? const [50, 30, 40, 30, 5]
          : command == 16
          ? const [15, 40, 30, 20, 5]
          : const [30, 10, 20, 60, 5];
      if (world.random.next() % 100 <=
          chance(rates[target.character.clamp(0, 4)], bonus)) {
        if (command == 15) {
          world.setPerson(
            order.object,
            target.copyWith(devotion: math.max(0, target.devotion - 4)),
          );
          passed = true;
        } else {
          final cityIndex = world.cityOfPerson(order.object);
          if (cityIndex != null) {
            if (command == 16) {
              world.addPerson(order.city, order.object);
              world.setPerson(
                order.object,
                target.copyWith(
                  belong: person.belong,
                  devotion: 40 + world.random.next() % 40,
                ),
              );
            } else {
              world.setPerson(
                order.object,
                target.copyWith(belong: order.object + 1),
              );
              final oldCity = world.city(cityIndex)!;
              final people = world.personsInCity(
                cityIndex,
                belong: oldCity.belong,
              );
              world.setCity(
                cityIndex,
                oldCity.copyWith(belong: order.object + 1),
              );
              for (final id in people) {
                world.setPerson(
                  id,
                  world.person(id)!.copyWith(belong: order.object + 1),
                );
              }
            }
            passed = true;
          }
        }
      }
    }
    final group = command == 15
        ? 'AlienateDrv'
        : command == 16
        ? 'CanvassDrv'
        : 'CounterespiongeDrv';
    final arrays = dialogs[group];
    String dialog(int arrayIndex, int index) {
      if (arrays is! List ||
          arrayIndex >= arrays.length ||
          arrays[arrayIndex] is! List) {
        return '';
      }
      final list = arrays[arrayIndex] as List;
      return index >= 0 && index < list.length ? list[index].toString() : '';
    }

    if (command == 15) {
      final devotion = world.person(order.object)!.devotion;
      final index = passed
          ? (devotion > 80
                ? 0
                : devotion > 60
                ? 1
                : devotion > 40
                ? 2
                : 3)
          : (devotion > 80
                ? 0
                : devotion > 60
                ? 1
                : 2);
      if (player) {
        reports.add(
          GameReport(dialog(passed ? 0 : 1, index), person: order.object),
        );
      }
    } else {
      final count = command == 16 ? (passed ? 5 : 3) : (passed ? 3 : 2);
      final random = world.random.next() % count;
      if (player) {
        reports.add(
          GameReport(dialog(passed ? 0 : 1, random), person: order.object),
        );
      }
      if (command == 17 && passed) {
        // 原函数成功后仍执行失败对白分支，保留第二次随机消费。
        final random = world.random.next() % 2;
        if (player) {
          reports.add(GameReport(dialog(1, random), person: order.object));
        }
      }
    }
  }
}

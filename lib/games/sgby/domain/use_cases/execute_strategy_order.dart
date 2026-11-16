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

  /// 收编被劝降势力的全部在任武将，包含已从城池队列移出的命令执行者和出征队。
  ///
  /// 先保存人员集合再统一易主，避免以“仍在旧势力”为条件漏掉城内外任一批人员。
  /// 随后取消其旧命令：整队取消时退还携粮，输送取消时退还三类物资；混合出征
  /// 只移除本次收编者并保留原槽位和其余成员。所有修改在会话isolate内同步完成。
  void _acceptSurrender(
    GameWorld world,
    int ruler,
    int belong,
    List<int> cities,
  ) {
    final destination = cities.firstOrNull;
    if (destination == null) return;
    final members = <int>{
      for (var id = 0; id < world.persons.length; id++)
        if (world.person(id)?.belong == ruler + 1) id,
    };
    for (final cityIndex in cities) {
      final city = world.city(cityIndex);
      if (city != null) {
        world.setCity(cityIndex, city.copyWith(belong: belong));
      }
    }
    for (final id in members) {
      final person = world.person(id);
      if (person != null) {
        world.setPerson(id, person.copyWith(belong: belong));
      }
    }

    /// 携带物资已在下令时扣除，只对本次真正移除的命令退还一次并限制字段宽度。
    void refund(GameOrder pending, {bool transport = false}) {
      final cityIndex = world.city(pending.city)?.belong == belong
          ? pending.city
          : destination;
      final city = world.city(cityIndex);
      if (city == null) return;
      world.setCity(
        cityIndex,
        city.copyWith(
          food: (city.food + pending.food).clamp(0, 65535),
          money: transport
              ? (city.money + pending.money).clamp(0, 65535)
              : null,
          mothballArms: transport
              ? (city.mothballArms + pending.arms).clamp(0, 65535)
              : null,
        ),
      );
    }

    final orders = <GameOrder>[];
    final returning = <int, GameOrder>{};
    for (final pending in world.orders) {
      if (pending.orderId == 27) {
        final retained = <int>[];
        for (final id in pending.fighters) {
          if (members.contains(id)) {
            returning[id] = pending.copyWith(person: id);
          } else {
            retained.add(id);
          }
        }
        if (retained.length == pending.fighters.length) {
          orders.add(pending);
        } else if (retained.isNotEmpty) {
          orders.add(pending.copyWith(fighters: retained));
        } else {
          refund(pending);
        }
      } else if (members.contains(pending.person)) {
        returning[pending.person] = pending;
        if (pending.orderId == 13) refund(pending, transport: true);
      } else {
        orders.add(pending);
      }
    }
    // 完成遍历后一次替换，避免迭代期间删改集合，也保留无关命令的固定队列槽位。
    world.replaceOrders(orders);
    for (final id in members) {
      if (world.cityOfPerson(id) != null) continue;
      final pending = returning[id];
      if (pending != null) {
        commands.returnPerson(world, pending);
      } else {
        // 兼容没有对应命令的旧城外人员，不能收编后仍永久滞留城外。
        world.addPerson(destination, id);
      }
    }
  }

  /// 概率和比较符保留原版边界；结算时重新验证敌我关系，拦截过期或非法外交。
  ///
  /// 目标可能在下令后已被招降或随势力易主。直接跳过仍由call统一归还执行者，
  /// 不额外消耗随机数，不对同势力、在野、俘虏或失效执行者继续执行反间等操作。
  void _diplomacy(
    GameWorld world,
    GameOrder order,
    List<GameReport> reports,
    int activity,
  ) {
    final person = world.person(order.person);
    final target = world.person(order.object);
    if (person == null ||
        target == null ||
        person.belong == 0 ||
        person.belong == 65535 ||
        target.belong == 0 ||
        target.belong == 65535 ||
        target.belong == person.belong) {
      return;
    }
    final player = person.belong == (world.playerRulerIndex ?? -1) + 1;
    final bonus = player || activity <= 25
        ? 0
        : (activity.clamp(0, 100) - 25) * 20 ~/ 75;
    int chance(int base, int addition) => (base + addition).clamp(0, 100);
    bool passed = false;
    final command = order.orderId;
    if (command == 19) {
      // 劝降只对仍在任的目标君主生效，防止旧命令把普通武将当成势力入口。
      if (target.belong != order.object + 1) return;
      final conquered = world.citiesOf(order.object);
      if (order.object != world.playerRulerIndex &&
          conquered.isNotEmpty &&
          world.citiesOf(person.belong - 1).length >= conquered.length * 2 &&
          world.random.next() % 100 <=
              chance(person.iq - target.iq + 50, bonus ~/ 2) &&
          world.random.next() % 100 <=
              chance(
                const [10, 1, 20, 5, 15][target.character.clamp(0, 4)],
                bonus,
              )) {
        _acceptSurrender(world, order.object, person.belong, conquered);
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

import '../models/game_world.dart';
import '../models/hidden_general_backup.dart';
import '../models/general_roster.dart';
import '../../engine/resources/baye_database.dart';

/// 对齐BBK特殊武将管理器：安全隐藏、君主继承、排队命令清理及普通身份恢复。
///
/// 先计算所有继任方案再写入，任一势力没有合法继任者时保持整个世界不变。
/// 本服务不持有世界或页面；可逆数据全部由GameWorld拥有并随存档保存。
final class SpecialGenerals {
  SpecialGenerals(this.resources);
  final BayeDatabase resources;

  /// BBK隐藏管理器重选太守时取最高智力，君主不享受策略阶段的优先规则。
  void _updateSatraps(GameWorld world) {
    for (var city = 0; city < world.cities.length; city++) {
      final value = world.city(city)!;
      int? best;
      for (final id in world.personsInCity(city)) {
        final person = world.person(id)!;
        if (value.belong != 0 &&
            person.belong == value.belong &&
            (best == null || person.iq > world.person(best)!.iq)) {
          best = id;
        }
      }
      world.setCity(
        city,
        value.copyWith(satrapId: best == null ? 0 : best + 1),
      );
    }
  }

  List<int> indexes(GameWorld world) => [
    for (var id = 0; id < world.persons.length; id++)
      if (const ['通宵虫', '通宵蟲', '南方小鬼'].contains(
        resources
            .personName(world.period, id)
            .replaceAll(RegExp(r'\s'), '')
            .trim(),
      ))
        id,
  ];

  Map<int, int> _locations(GameWorld world) {
    final result = <int, int>{};
    for (var city = 0; city < world.cities.length; city++) {
      for (final id in world.personsInCity(city)) {
        result[id] = city;
      }
    }
    for (final order in world.orders) {
      if (order.orderId == 27) {
        for (final id in order.fighters) {
          result.putIfAbsent(id, () => order.city);
        }
      } else {
        result.putIfAbsent(order.person, () => order.city);
      }
    }
    return result;
  }

  CheatResult hide(GameWorld world, {bool battleActive = false}) {
    if (battleActive) {
      return const CheatResult(isSuccess: false, message: '请回到战略地图后切换特殊武将隐藏');
    }
    final special = indexes(world).toSet(), locations = _locations(world);
    final pending = special
        .where(
          (id) =>
              !world.hiddenGenerals.containsKey(id) &&
              (world.person(id)!.belong != 65535 || locations.containsKey(id)),
        )
        .toList();
    final replacements = <int, int>{};
    for (final id in pending) {
      if (world.person(id)!.belong != id + 1) continue;
      int? best;
      for (var candidate = 0; candidate < world.persons.length; candidate++) {
        final person = world.person(candidate)!;
        if (special.contains(candidate) || person.belong != id + 1) continue;
        final previous = best == null ? null : world.person(best);
        if (best == null ||
            locations.containsKey(candidate) && !locations.containsKey(best) ||
            locations.containsKey(candidate) == locations.containsKey(best) &&
                (person.iq > previous!.iq ||
                    person.iq == previous.iq &&
                        person.force > previous.force)) {
          best = candidate;
        }
      }
      if (best == null) {
        return CheatResult(
          isSuccess: false,
          message:
              '${resources.personName(world.period, id)}所在势力没有可继任武将，请先补充武将',
        );
      }
      replacements[id + 1] = best + 1;
    }
    for (final id in pending) {
      final person = world.person(id)!;
      world.hiddenGenerals[id] = HiddenGeneralBackup(
        index: id,
        belong: replacements[person.belong] ?? person.belong,
        oldBelong: replacements[person.oldBelong] ?? person.oldBelong,
        arms: person.arms,
        city: locations[id],
      );
    }
    for (final replacement in replacements.entries) {
      final previous = replacement.key, successor = replacement.value;
      world.setPerson(
        successor - 1,
        world.person(successor - 1)!.copyWith(devotion: 100),
      );
      for (var id = 0; id < world.persons.length; id++) {
        final person = world.person(id)!;
        world.setPerson(
          id,
          person.copyWith(
            belong: person.belong == previous ? successor : null,
            oldBelong: person.oldBelong == previous ? successor : null,
          ),
        );
      }
      for (var city = 0; city < world.cities.length; city++) {
        final value = world.city(city)!;
        if (value.belong == previous) {
          world.setCity(city, value.copyWith(belong: successor));
        }
      }
      for (final saved in world.hiddenGenerals.values.toList()) {
        world.hiddenGenerals[saved.index] = saved.withSuccessor(
          previous,
          successor,
        );
      }
      if (world.playerRulerIndex == previous - 1) {
        world.playerRulerIndex = successor - 1;
      }
    }
    for (final order in world.orders.toList()) {
      if (order.orderId == 27) {
        final fighters = order.fighters
            .where((id) => !pending.contains(id))
            .toList();
        if (fighters.length == order.fighters.length) continue;
        world.removeOrder(order);
        if (fighters.isEmpty) {
          final city = world.city(order.city)!;
          world.setCity(
            order.city,
            city.copyWith(food: (city.food + order.food).clamp(0, 65535)),
          );
        } else {
          world.replaceOrders([
            ...world.orders,
            order.copyWith(fighters: fighters),
          ]);
        }
      } else if (pending.contains(order.person)) {
        world.removeOrder(order);
      } else if ((order.orderId == 6 ||
              order.orderId >= 15 && order.orderId <= 19) &&
          pending.contains(order.object)) {
        // 原内核把目标失效命令改为空操作再归还执行者；原生直接归队并移除命令。
        world.removeOrder(order);
        world.addPerson(order.city, order.person);
      }
    }
    for (final id in pending) {
      for (var city = 0; city < world.cities.length; city++) {
        while (world.removePerson(city, id)) {}
      }
      world.setPerson(
        id,
        world.person(id)!.copyWith(belong: 65535, oldBelong: 0, arms: 0),
      );
    }
    _updateSatraps(world);
    return const CheatResult(
      isSuccess: true,
      message: '已隐藏通宵虫和南方小鬼，原有君主由同势力武将继任',
    );
  }

  CheatResult restore(GameWorld world, {bool battleActive = false}) {
    if (battleActive) {
      return const CheatResult(isSuccess: false, message: '请回到战略地图后恢复特殊武将');
    }
    for (final saved in world.hiddenGenerals.values.toList()) {
      final person = world.person(saved.index);
      if (person == null || person.belong != 65535) continue;
      final ruler = world.person(saved.belong - 1);
      var belong = ruler != null && ruler.belong != 65535 ? ruler.belong : 0;
      int? city;
      if (belong > 0) {
        for (var id = 0; id < world.cities.length; id++) {
          if (world.city(id)!.belong == belong &&
              (city == null || id == saved.city)) {
            city = id;
          }
        }
      }
      if (city == null &&
          saved.city != null &&
          world.city(saved.city!) != null) {
        city = saved.city;
        belong = world.city(city!)!.belong;
      }
      world.setPerson(
        saved.index,
        person.copyWith(
          belong: belong == saved.index + 1 ? 0 : belong,
          oldBelong: saved.oldBelong,
          arms: saved.arms,
        ),
      );
      if (city != null) world.addPerson(city, saved.index);
    }
    world.hiddenGenerals.clear();
    _updateSatraps(world);
    return const CheatResult(
      isSuccess: true,
      message: '已恢复通宵虫和南方小鬼，原君主保留普通武将身份',
    );
  }
}

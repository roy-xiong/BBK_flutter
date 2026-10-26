import 'dart:math' as math;

import '../../engine/core/original_random.dart';
import '../../engine/resources/baye_database.dart';
import '../models/game_report.dart';
import '../models/game_world.dart';

/// ConditionUpdate的日历与城市环境阶段。电脑决策和订单必须先于此阶段完成。
///
/// 跨年出场、季税、夏秋收获、粮耗、灾害损失与随机恢复分别按旧内核次序执行。
/// 所有16/8位中间量显式截断，避免Dart大整数改变缺粮与灾害边界。
final class AdvanceCalendar {
  AdvanceCalendar(this.resources);
  final BayeDatabase resources;
  int _word(int value) =>
      resources.rule('fixOverFlow16') != 0 ? value.clamp(0, 65535) : u16(value);

  List<GameReport> call(
    GameWorld world, {
    bool foodProtection = false,
    bool largeArmies = false,
  }) {
    final reports = <GameReport>[];
    world.month++;
    if (world.month > 12) {
      world.month = 1;
      world.year = u16(world.year + 1);
      _annualGoods(world);
      _annualPersons(world);
    }
    final harvest = world.month == 6 || world.month == 10;
    final tax = world.month % 3 == 0;
    for (var i = 0; i < world.cities.length; i++) {
      var city = world.city(i)!;
      if (harvest && city.food < 30000) {
        city = city.copyWith(food: _word(city.food + city.farming ~/ 4));
      }
      if (tax && city.money < 30000) {
        city = city.copyWith(money: u16(city.money + city.commerce ~/ 2));
      }
      world.setCity(i, city);
    }
    for (var i = 0; i < world.persons.length; i++) {
      final person = world.person(i)!;
      world.setPerson(
        i,
        person.copyWith(thew: math.min(100, u8(person.thew + 4))),
      );
    }
    for (var i = 0; i < world.cities.length; i++) {
      var city = world.city(i)!;
      if (city.belong == 0) continue;
      if (tax) {
        final reduction = 1 + world.random.next() % 4;
        if (city.avoidCalamity > reduction) {
          city = city.copyWith(avoidCalamity: city.avoidCalamity - reduction);
        }
      }
      city = city.copyWith(
        money: math.min(30000, city.money),
        population: math.min(city.populationLimit, u32(city.population + 50)),
      );
      var soldiers = city.mothballArms;
      final people = world.personsInCity(i, belong: city.belong);
      for (final id in people) {
        final person = world.person(id)!;
        final arms = switch (city.state) {
          2 || 3 => person.arms - person.arms ~/ 4,
          4 => person.arms ~/ 2,
          _ => person.arms,
        };
        soldiers += arms;
        if (!largeArmies && !world.hasLargeArmies) soldiers = u16(soldiers);
        world.setPerson(id, person.copyWith(arms: arms));
      }
      final divisor = resources.rule('ratioOfFoodToArmsPerMouth');
      final consumed = soldiers ~/ (divisor > 0 ? divisor : 50);
      final protect =
          foodProtection && city.belong == (world.playerRulerIndex ?? -1) + 1;
      if (city.food > consumed) {
        city = city.copyWith(food: city.food - consumed);
      } else if (!protect) {
        for (final id in people) {
          final person = world.person(id)!;
          world.setPerson(id, person.copyWith(arms: person.arms ~/ 2));
        }
        if (city.state != 1 &&
            city.belong == (world.playerRulerIndex ?? -1) + 1) {
          _report(world, i, 1, reports);
        }
        city = city.copyWith(food: 0, state: 1);
      }
      for (final id in world.personsInCity(i, belong: 65535)) {
        final captive = world.person(id)!;
        if (captive.oldBelong == city.belong) {
          world.setPerson(id, captive.copyWith(belong: city.belong));
        }
      }
      world.setCity(i, city);
    }
    for (var i = 0; i < world.cities.length; i++) {
      final city = world.city(i)!;
      final next = switch (city.state) {
        1 => city.copyWith(
          commerce: city.commerce - city.commerce ~/ 20,
          peopleDevotion: city.peopleDevotion - city.peopleDevotion ~/ 20,
          mothballArms: city.mothballArms ~/ 2,
          population: city.population - city.population ~/ 4,
        ),
        2 => city.copyWith(
          food: city.food - city.food ~/ 20,
          mothballArms: city.mothballArms - city.mothballArms ~/ 4,
          population: city.population - city.population ~/ 4,
        ),
        3 => city.copyWith(
          food: city.food - city.food ~/ 20,
          commerce: city.commerce - city.commerce ~/ 10,
          money: city.money - city.money ~/ 10,
          mothballArms: city.mothballArms - city.mothballArms ~/ 4,
          population: city.population - city.population ~/ 4,
        ),
        4 => city.copyWith(
          food: city.food - city.food ~/ 20,
          commerce: city.commerce - city.commerce ~/ 20,
          money: city.money - city.money ~/ 20,
          peopleDevotion: city.peopleDevotion - city.peopleDevotion ~/ 10,
          mothballArms: city.mothballArms ~/ 2,
        ),
        _ => city,
      };
      world.setCity(
        i,
        city.state == 0
            ? next
            : next.copyWith(farming: city.farming - city.farming ~/ 20),
      );
    }
    for (var i = 0; i < world.cities.length; i++) {
      final city = world.city(i)!;
      if (city.belong == 0) continue;
      var state = city.state;
      final random = world.random.next() % 100;
      switch (state) {
        case 0:
          if (random > city.avoidCalamity) {
            final event = world.random.next() % 5;
            if (event == 0) {
              state = 2;
            } else if (event == 1) {
              state = 3;
            } else if (event == 2 &&
                world.random.next() % 100 > city.peopleDevotion) {
              state = 4;
            }
            if (state != 0 &&
                city.belong == (world.playerRulerIndex ?? -1) + 1) {
              _report(world, i, state, reports);
            }
          }
        case 1:
          if (city.food > 0) state = 0;
        case 2:
        case 3:
          if (random < city.avoidCalamity) state = 0;
        case 4:
          if (random < city.peopleDevotion) state = 0;
      }
      world.setCity(i, city.copyWith(state: state));
    }
    return reports;
  }

  void _annualPersons(GameWorld world) {
    final ageGrowth = resources.rule('disableAgeGrow') == 0;
    if (ageGrowth) {
      for (var i = 0; i < world.persons.length; i++) {
        final person = world.person(i)!;
        world.setPerson(i, person.copyWith(age: u8(person.age + 1)));
      }
    }
    final data = resources.requiredItem(63, world.period);
    for (var i = 0; i < world.persons.length && i * 4 + 4 <= data.length; i++) {
      if (world.hiddenGenerals.containsKey(i)) continue;
      if (data[i * 4] + 16 != world.year) continue;
      var city = data[i * 4 + 3];
      if (city == 0) city = world.random.next() % world.cities.length;
      if (resources.rule('fixCityOffset') != 0) city--;
      if (!world.addPerson(city, i)) return;
      if (ageGrowth) world.setPerson(i, world.person(i)!.copyWith(age: 16));
    }
  }

  void _annualGoods(GameWorld world) {
    final data = resources.requiredItem(67, world.period);
    // 原函数按t+=3访问SearchCondition记录。只读取有效条目，不模拟C越界内存。
    for (
      var index = 0, item = 0;
      item + 12 <= data.length;
      index++, item += 12
    ) {
      if (data[item] == world.year) world.addTool(data[item + 11], index);
    }
  }

  void _report(
    GameWorld world,
    int cityIndex,
    int state,
    List<GameReport> output,
  ) {
    final city = world.city(cityIndex)!;
    if (city.satrapId == 0) return;
    output.add(
      GameReport(
        '${resources.text(64, 111)}${resources.cityName(cityIndex)}${resources.text(64, 12 + state)}${resources.text(64, 112)}',
        person: city.satrapId - 1,
      ),
    );
  }
}

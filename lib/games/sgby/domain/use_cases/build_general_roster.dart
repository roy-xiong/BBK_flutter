import '../../engine/resources/baye_database.dart';
import '../models/game_person.dart';
import '../models/game_world.dart';
import '../models/general_roster.dart';
import '../models/game_battle.dart';

/// 将原生世界投影成原查询面板使用的快照，保留四分组、出场条件及装备兵种。
final class BuildGeneralRoster {
  BuildGeneralRoster(this.resources);
  final BayeDatabase resources;

  SgbyCheatData call(GameWorld world, {GameBattle? battle}) {
    final ruler = world.playerRulerIndex;
    if (ruler == null) {
      return const SgbyCheatData(
        isSuccess: false,
        message: '请先开始或载入一局游戏',
        maxLevel: 20,
        generals: [],
      );
    }
    final locations = <int, int>{};
    for (var city = 0; city < world.cities.length; city++) {
      for (final person in world.personsInCity(city)) {
        locations.putIfAbsent(person, () => city);
      }
    }
    final conditions = resources.requiredItem(63, world.period);
    final output = <SgbyGeneralCheatInfo>[];
    final people = world.persons;
    for (var index = 0; index < people.length; index++) {
      final person = people[index];
      if (person.belong == 0xffff) continue;
      final name = resources.personName(world.period, index);
      if (name.trim().isEmpty) continue;
      final offset = index * 4;
      final birth = offset + 4 <= conditions.length ? conditions[offset] : 0;
      final conditionCity = offset + 4 <= conditions.length
          ? conditions[offset + 3]
          : 0;
      final appearance = birth > 0 ? birth + 16 : 0;
      final group = person.belong == ruler + 1
          ? SgbyGeneralGroup.player
          : person.belong == 0
          ? (appearance > world.year
                ? SgbyGeneralGroup.futureWild
                : SgbyGeneralGroup.currentWild)
          : SgbyGeneralGroup.enemy;
      var cityIndex = locations[index];
      var cityName = cityIndex == null ? '城外' : resources.cityName(cityIndex);
      if (cityIndex == null &&
          person.belong == 0 &&
          offset + 4 <= conditions.length) {
        if (conditionCity == 0) {
          cityName = '随机城池';
        } else {
          final candidate =
              conditionCity - (resources.rule('fixCityOffset') != 0 ? 1 : 0);
          if (world.city(candidate) != null) {
            cityIndex = candidate;
            cityName = resources.cityName(candidate);
          }
        }
      }
      final factionIndex = person.belong - 1;
      final faction = factionIndex >= 0 && factionIndex < people.length
          ? resources.personName(world.period, factionIndex)
          : '未知主公';
      final battleIndex = battle?.people.indexOf(index) ?? -1;
      final position = battleIndex >= 0 ? battle?.units[battleIndex] : null;
      output.add(
        SgbyGeneralCheatInfo(
          index: index,
          name: name,
          group: group,
          factionName: person.belong == 0 ? '在野' : faction,
          isRuler: person.belong == index + 1,
          appearanceYear: appearance,
          cityIndex: cityIndex ?? 65535,
          cityName: cityName,
          level: person.level,
          force: person.force,
          iq: person.iq,
          devotion: person.devotion,
          thew: person.thew,
          experience: person.experience,
          arms: person.arms,
          baseArmsType: person.armsType,
          effectiveArmsType: effectiveArmsType(world, person),
          inBattle: position != null,
          battleMove: position?.move ?? 0,
          battleHp: position?.hp ?? 0,
          battleMp: position?.mp ?? 0,
          battleState: position?.state ?? 0,
          canAct: position?.active == 0,
        ),
      );
    }
    final nameOrder = resources.ruleArray('uiNameOrder${world.period}');
    final ranks = <int, int>{
      for (var i = 0; i < nameOrder.length; i++) nameOrder[i]: i,
    };
    output.sort((a, b) {
      var result = a.group.index.compareTo(b.group.index);
      if (result != 0) return result;
      result = a.cityIndex.compareTo(b.cityIndex);
      if (result != 0) return result;
      result = (a.isRuler ? 0 : 1).compareTo(b.isRuler ? 0 : 1);
      if (result != 0) return result;
      result = a.appearanceYear.compareTo(b.appearanceYear);
      if (result != 0) return result;
      return (ranks[a.index] ?? a.index).compareTo(ranks[b.index] ?? b.index);
    });
    return SgbyCheatData(
      isSuccess: true,
      message: '',
      maxLevel: resources.rule('maxLevel', 20),
      generals: List.unmodifiable(output),
    );
  }

  /// 两个装备按原顺序覆盖兵种，后者优先，不把基础兵种直接当成实际兵种。
  int effectiveArmsType(GameWorld world, GamePerson person) {
    var result = person.armsType;
    for (final id in [person.equip0, person.equip1]) {
      if (id <= 0) continue;
      final tool = world.tool(id - 1);
      if (tool == null || tool.arm == 0) continue;
      result = switch (tool.arm) {
        1 => 3,
        2 => 5,
        3 => 4,
        _ => tool.arm - 4,
      };
    }
    return result;
  }
}

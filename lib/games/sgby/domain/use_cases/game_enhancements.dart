import 'dart:math' as math;

import '../../engine/resources/baye_database.dart';
import '../models/game_battle.dart';
import '../models/game_options.dart';
import '../models/game_person.dart';
import '../models/game_world.dart';
import '../models/general_roster.dart';
import 'special_generals.dart';

/// 当前仓库bbk-enhancements的城市、人事、搜索和持久开关迁移。
///
/// 只接受固定动作与结构化参数；历史记录最多50条。界面暂停期间可调用本服务，
/// 游戏逻辑与修改仍在同一isolate顺序执行，不执行来自存档的脚本。
final class GameEnhancements {
  GameEnhancements(this.resources, this.options, {List<dynamic>? history}) {
    if (history != null) {
      _history.addAll(
        history
            .whereType<Map>()
            .where((entry) => entry.keys.every((key) => key is String))
            .take(50)
            .map((entry) => Map<String, Object?>.from(entry)),
      );
    }
  }
  final BayeDatabase resources;
  final GameOptions options;
  final List<Map<String, Object?>> _history = [];
  int revision = 0;
  List<Map<String, Object?>> get history =>
      List<Map<String, Object?>>.unmodifiable(_history);
  GamePerson _max(GamePerson p) => p.copyWith(
    level: resources.rule('maxLevel', 20),
    force: 100,
    iq: 100,
    devotion: 100,
    thew: 100,
    experience: 0,
    arms: 65535,
  );
  String _person(GameWorld world, int id) =>
      resources.personName(world.period, id);

  void applyPersistent(GameWorld world) {
    if (!options.enabled('autoMaxGenerals')) return;
    for (var i = 0; i < world.persons.length; i++) {
      if (world.person(i)!.belong == (world.playerRulerIndex ?? -1) + 1) {
        world.setPerson(i, _max(world.person(i)!));
      }
    }
  }

  /// 读档/新局只同步本局隐藏记录，不产生自动存档，也不借用其他档位备份。
  CheatResult synchronizeWorld(GameWorld world) {
    final special = SpecialGenerals(resources);
    final result = options.enabled('hideSpecialGenerals')
        ? special.hide(world)
        : world.hiddenGenerals.isNotEmpty
        ? special.restore(world)
        : const CheatResult(isSuccess: true, message: '');
    applyEnemyArmsLimit(world);
    applyPersistent(world);
    return result;
  }

  /// 只压低有势力敌将超额兵力，不给其补兵，不改玩家、在野和俘虏或伤亡战绩。
  void applyEnemyArmsLimit(GameWorld world) {
    if (!options.enabled('enemyArmsLimitEnabled')) return;
    final player = (world.playerRulerIndex ?? -1) + 1;
    for (var id = 0; id < world.persons.length; id++) {
      final person = world.person(id)!;
      if (person.belong > 0 &&
          person.belong != 65535 &&
          person.belong != player &&
          person.arms > options.enemyArmsLimit) {
        world.setPerson(id, person.copyWith(arms: options.enemyArmsLimit));
      }
    }
  }

  void maximizeCities(
    GameWorld world, {
    bool resourcesOnly = false,
    bool developmentOnly = false,
  }) {
    for (final id in world.citiesOf(world.playerRulerIndex ?? -1)) {
      final city = world.city(id)!;
      world.setCity(
        id,
        city.copyWith(
          money: developmentOnly ? null : 65535,
          food: developmentOnly ? null : 65535,
          mothballArms: developmentOnly ? null : 65535,
          state: resourcesOnly ? null : 0,
          farming: resourcesOnly ? null : city.farmingLimit,
          commerce: resourcesOnly ? null : city.commerceLimit,
          population: resourcesOnly ? null : city.populationLimit,
          peopleDevotion: resourcesOnly ? null : 100,
          avoidCalamity: resourcesOnly ? null : 100,
        ),
      );
    }
  }

  Map<String, Object?> _row(int city) => {
    'cityName': resources.cityName(city),
    'people': <String>[],
    'tools': <String>[],
    'recruited': <String>[],
    'executed': <String>[],
    'exiled': <String>[],
  };
  void _record(
    GameWorld world,
    String source,
    List<Map<String, Object?>> cities, {
    Map<String, Object?>? battle,
  }) {
    final keys = ['people', 'tools', 'recruited', 'executed', 'exiled'];
    final counts = [
      for (final key in keys)
        cities.fold<int>(
          0,
          (sum, city) => sum + ((city[key] as List?)?.length ?? 0),
        ),
    ];
    if (counts.every((count) => count == 0)) return;
    final now = DateTime.now();
    _history.insert(0, {
      'id': '${now.microsecondsSinceEpoch}',
      'timestamp': now.toUtc().toIso8601String(),
      'realTime':
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}',
      'gameTime': '${world.year}年${world.month}月',
      'source': source,
      'battle': battle,
      'peopleCount': counts[0],
      'toolCount': counts[1],
      'recruitedCount': counts[2],
      'executedCount': counts[3],
      'exiledCount': counts[4],
      'cities': cities,
    });
    if (_history.length > 50) _history.removeRange(50, _history.length);
    revision++;
  }

  void _materialize(GameWorld world) {
    final cities = world.citiesOf(world.playerRulerIndex ?? -1);
    if (cities.isEmpty) return;
    final data = resources.requiredItem(63, world.period);
    for (var i = 0; i < world.persons.length; i++) {
      final person = world.person(i)!;
      if (i * 4 + 4 > data.length ||
          data[i * 4] == 0 ||
          data[i * 4] + 16 <= world.year ||
          person.belong != 0 ||
          world.cityOfPerson(i) != null) {
        continue;
      }
      final birthCity = data[i * 4 + 3];
      final city = birthCity == 0
          ? cities[i % cities.length]
          : birthCity - (resources.rule('fixCityOffset') == 0 ? 0 : 1);
      if (world.city(city)?.belong != (world.playerRulerIndex ?? -1) + 1) {
        continue;
      }
      if (world.addPerson(city, i)) {
        world.setPerson(
          i,
          person.copyWith(age: (world.year - data[i * 4]).clamp(16, 255)),
        );
      }
    }
  }

  List<Map<String, Object?>> searchOwned(
    GameWorld world,
    String source, {
    List<Map<String, Object?>>? captiveRows,
    Map<String, Object?>? battle,
  }) {
    final rows = <int, Map<String, Object?>>{};
    for (final row in captiveRows ?? <Map<String, Object?>>[]) {
      final city = world.cities.indexWhere(
        (value) =>
            resources.cityName(world.cities.indexOf(value)) == row['cityName'],
      );
      if (city >= 0) rows[city] = Map<String, Object?>.from(row);
    }
    if (options.choice('searchOutcome') != 'none') {
      _materialize(world);
      final ruler = (world.playerRulerIndex ?? -1) + 1;
      for (final city in world.citiesOf(ruler - 1)) {
        final found = <String>[], tools = <String>[];
        for (final id in world.personsInCity(city, belong: 0)) {
          final person = world.person(id)!;
          found.add(_person(world, id));
          world.setPerson(
            id,
            options.enabled('autoMaxGenerals')
                ? _max(person.copyWith(belong: ruler))
                : person.copyWith(belong: ruler, devotion: 100),
          );
        }
        for (final tool in world.goodsInCity(city)) {
          if ((tool & 0x8000) == 0) {
            tools.add(resources.toolName(tool & 0x7fff));
            world.discoverTool(city, tool & 0x7fff);
          }
        }
        if (found.isNotEmpty || tools.isNotEmpty) {
          final row = rows.putIfAbsent(city, () => _row(city));
          row['people'] = found;
          row['tools'] = tools;
        }
      }
    }
    final output = rows.values.toList(growable: false);
    _record(world, source, output, battle: battle);
    return output;
  }

  List<({int id, int city, int? actual})> _wild(
    GameWorld world,
    bool includeFuture,
  ) {
    final data = resources.requiredItem(63, world.period);
    final output = <({int id, int city, int? actual})>[];
    for (var i = 0; i < world.persons.length; i++) {
      if (world.person(i)!.belong != 0 ||
          _person(world, i).trim().isEmpty ||
          !includeFuture && data[i * 4] + 16 > world.year) {
        continue;
      }
      final actual = world.cityOfPerson(i);
      var city =
          actual ??
          (data[i * 4 + 3] == 0
              ? -1
              : data[i * 4 + 3] -
                    (resources.rule('fixCityOffset') == 0 ? 0 : 1));
      if (world.city(city) == null) city = i % world.cities.length;
      output.add((id: i, city: city, actual: actual));
    }
    return output;
  }

  int searchWorld(GameWorld world) {
    final grouped = <int, List<({int id, int city, int? actual})>>{};
    for (final entry in _wild(world, false)) {
      grouped.putIfAbsent(entry.city, () => []).add(entry);
    }
    final rows = <Map<String, Object?>>[];
    for (var cityId = 0; cityId < world.cities.length; cityId++) {
      final entries = grouped[cityId];
      if (entries == null || entries.isEmpty) continue;
      var city = world.city(cityId)!;
      if (city.belong == 0) {
        city = city.copyWith(
          belong: entries.first.id + 1,
          satrapId: entries.first.id + 1,
        );
        world.setCity(cityId, city);
      }
      final names = <String>[];
      for (final entry in entries) {
        var person = world
            .person(entry.id)!
            .copyWith(oldBelong: 0, belong: city.belong, devotion: 100);
        if (city.belong == (world.playerRulerIndex ?? -1) + 1 &&
            options.enabled('autoMaxGenerals')) {
          person = _max(person);
        }
        world.setPerson(entry.id, person);
        if (entry.actual == null) world.addPerson(cityId, entry.id);
        names.add(_person(world, entry.id));
      }
      rows.add(_row(cityId)..['people'] = names);
    }
    _record(world, '全地图搜索', rows);
    return rows.fold(0, (sum, row) => sum + (row['people'] as List).length);
  }

  void _equipment(GameWorld world, int city, int personId) {
    final person = world.person(personId)!;
    for (final equipment in [person.equip0, person.equip1]) {
      if (equipment > 0) world.addTool(city, equipment - 1, discovered: true);
    }
    world.setPerson(personId, person.copyWith(equip0: 0, equip1: 0));
  }

  List<Map<String, Object?>> captives(
    GameWorld world,
    List<int> cities,
    String action, {
    int? winnerBelong,
  }) {
    final ruler = (world.playerRulerIndex ?? -1) + 1,
        winner = winnerBelong ?? (world.playerRulerIndex ?? -1) + 1;
    var destinations = <int>[
      for (var i = 0; i < world.cities.length; i++)
        if (world.city(i)!.belong != winner && world.city(i)!.belong != ruler)
          i,
    ];
    if (destinations.isEmpty) {
      destinations = [
        for (var i = 0; i < world.cities.length; i++)
          if (world.city(i)!.belong != winner) i,
      ];
    }
    final occupied = destinations
        .where((id) => world.city(id)!.persons > 0)
        .toList();
    if (occupied.isNotEmpty) destinations = occupied;
    final rows = <Map<String, Object?>>[];
    for (final city in cities) {
      final names = <String>[];
      for (final id in world.personsInCity(city, belong: 65535)) {
        final person = world.person(id)!;
        if (action == 'exile' && destinations.isEmpty) continue;
        names.add(_person(world, id));
        if (action == 'recruit') {
          final next = person.copyWith(belong: winner, devotion: 100);
          world.setPerson(
            id,
            winner == ruler && options.enabled('autoMaxGenerals')
                ? _max(next)
                : next,
          );
        } else if (action == 'execute') {
          world.battleRecord.generalDied(
            ruler,
            id,
            person.oldBelong,
            person.arms,
            world.city(city)!.belong,
          );
          _equipment(world, city, id);
          world.removePerson(city, id);
        } else if (action == 'exile') {
          world.setPerson(id, person.copyWith(belong: 0));
          world.removePerson(city, id);
          world.addPerson(
            destinations[(world.random.next() % 65536 * destinations.length) ~/
                65536],
            id,
          );
        }
      }
      if (names.isNotEmpty) {
        rows.add(
          _row(city)
            ..[action == 'recruit'
                    ? 'recruited'
                    : action == 'execute'
                    ? 'executed'
                    : 'exiled'] =
                names,
        );
      }
    }
    return rows;
  }

  void maintenance(GameWorld world) {
    if (options.enabled('autoMaxCities')) {
      maximizeCities(world);
      searchOwned(world, '策略结束自动');
    }
  }

  Map<int, int> protectFood(GameWorld world) {
    final consumed = <int, int>{};
    for (final cityId in world.citiesOf(world.playerRulerIndex ?? -1)) {
      final city = world.city(cityId)!;
      var arms = city.mothballArms;
      for (final id in world.personsInCity(cityId, belong: city.belong)) {
        final person = world.person(id)!;
        final soldiers = city.state == 2 || city.state == 3
            ? person.arms - person.arms ~/ 4
            : city.state == 4
            ? person.arms ~/ 2
            : person.arms;
        arms += soldiers;
        if (!world.hasLargeArmies &&
            !options.enabled('enemyArmsLimitEnabled')) {
          arms &= 65535;
        }
      }
      final ratio = resources.rule('ratioOfFoodToArmsPerMouth');
      final amount = arms ~/ (ratio == 0 ? 50 : ratio);
      if (options.enabled('foodProtection') &&
          city.food <= amount &&
          amount < 65535) {
        world.setCity(cityId, city.copyWith(food: amount + 1));
      }
      if (options.enabled('autoMaxCities')) consumed[cityId] = amount;
    }
    return consumed;
  }

  void restoreFood(GameWorld world, Map<int, int> consumed) {
    for (final entry in consumed.entries) {
      final city = world.city(entry.key);
      if (city?.belong == (world.playerRulerIndex ?? -1) + 1) {
        world.setCity(
          entry.key,
          city!.copyWith(food: math.min(65535, city.food + entry.value)),
        );
      }
    }
  }

  void postBattle(GameWorld world, GameBattle battle) {
    if (!options.enabled('postBattleAutomation')) return;
    maximizeCities(world);
    final winner = world.city(battle.city)!.belong;
    final rows = captives(
      world,
      world.citiesOf(winner - 1),
      options.choice('postBattleCaptiveAction'),
      winnerBelong: winner,
    );
    searchOwned(
      world,
      '战后自动',
      captiveRows: rows,
      battle: {
        'direction': battle.mode == 1
            ? 'playerAttack'
            : battle.mode == 0
            ? 'playerDefence'
            : 'auto',
        'cityName': resources.cityName(battle.city),
        'cityIndex': battle.city,
      },
    );
  }

  /// “必死”模式还处理城破前已有俘虏，只在返回战略地图的安全边界执行。
  void executeDefeatedCaptives(GameWorld world, GameBattle battle) {
    final city = world.city(battle.city);
    if (options.loserOutcome != 1 ||
        city == null ||
        city.belong == battle.originalCityBelong) {
      return;
    }
    for (final id in battle.initialCaptives) {
      final person = world.person(id);
      if (person == null ||
          person.belong != 65535 ||
          world.cityOfPerson(id) != battle.city) {
        continue;
      }
      _equipment(world, battle.city, id);
      world.battleRecord.generalDied(
        (world.playerRulerIndex ?? -1) + 1,
        id,
        person.oldBelong,
        person.arms,
        city.belong,
      );
      world.removePerson(battle.city, id);
    }
  }

  CheatResult apply(
    GameWorld world,
    String action, {
    Map<String, Object?>? parameters,
    int? selectedCity,
    GameBattle? battle,
  }) {
    if (action == 'sgby_hide_special_generals') {
      final enabled = !options.enabled('hideSpecialGenerals');
      final special = SpecialGenerals(resources);
      final result = enabled
          ? special.hide(world, battleActive: battle != null)
          : special.restore(world, battleActive: battle != null);
      if (result.isSuccess) {
        options.toggle('hideSpecialGenerals', enabled: enabled);
      }
      return result;
    }
    if (action == 'sgby_enemy_arms_limit_value') {
      final success = options.setEnemyArmsLimit(parameters?['value']);
      if (success) applyEnemyArmsLimit(world);
      return CheatResult(
        isSuccess: success,
        message: success ? '敌军带兵上限已更新，不立即补兵' : '兵力上限必须是800至200000之间的整数',
      );
    }
    const switches = {
      'sgby_auto_save_after_turn': 'autoSaveAfterTurn',
      'sgby_enemy_arms_limit': 'enemyArmsLimitEnabled',
      'sgby_diplomacy_protection': 'diplomacyProtection',
      'sgby_max_all': 'autoMaxCities',
      'sgby_generals': 'autoMaxGenerals',
      'sgby_free_movement': 'freeMovement',
      'sgby_food_protection': 'foodProtection',
      'sgby_attack_any_city': 'attackAnyCity',
      'sgby_enemy_escape_route': 'enemyEscapeRoute',
      'sgby_disable_animations': 'animationsDisabled',
      'sgby_invincible': 'invincible',
      'sgby_one_hit_kill': 'oneHitKill',
      'sgby_wide_group_attack': 'wideGroupAttack',
      'sgby_faction_colors': 'factionColors',
      'sgby_post_battle_automation': 'postBattleAutomation',
    };
    final key = switches[action];
    if (key != null) {
      options.toggle(key);
      if (key == 'autoMaxCities' && options.enabled(key)) {
        maximizeCities(world);
        searchOwned(world, '开启自动拉满');
      }
      if (key == 'autoMaxGenerals') applyPersistent(world);
      if (key == 'enemyArmsLimitEnabled') applyEnemyArmsLimit(world);
      return CheatResult(
        isSuccess: true,
        message: options.enabled(key) ? '已开启' : '已关闭',
      );
    }
    const choices = {
      'sgby_search_outcome': 'searchOutcome',
      'sgby_post_battle_captive_action': 'postBattleCaptiveAction',
      'sgby_battle_loser_outcome': 'battleLoserOutcome',
    };
    if (choices.containsKey(action)) {
      final mode = parameters?['mode'];
      final success =
          mode is String && options.setChoice(choices[action]!, mode);
      return CheatResult(
        isSuccess: success,
        message: success ? '设置已更新' : '参数无效',
      );
    }
    if (action == 'sgby_resources') {
      maximizeCities(world, resourcesOnly: true);
      return const CheatResult(isSuccess: true, message: '我方城池资源已拉满');
    }
    if (action == 'sgby_development') {
      maximizeCities(world, developmentOnly: true);
      return const CheatResult(isSuccess: true, message: '我方城池发展已拉满');
    }
    if (action == 'sgby_search_city') {
      final result = searchOwned(world, '手动搜索');
      return CheatResult(
        isSuccess: true,
        message: '搜索完成，共发现${result.length}座城池的新内容',
      );
    }
    if (action == 'sgby_search_world_generals') {
      final count = searchWorld(world);
      return CheatResult(isSuccess: true, message: '全地图搜索完成，搜出$count名在野武将');
    }
    if (action == 'sgby_execute_wild_generals') {
      final entries = _wild(world, true), rows = <int, Map<String, Object?>>{};
      for (final entry in entries) {
        _equipment(world, entry.city, entry.id);
        final p = world.person(entry.id)!;
        world.setPerson(
          entry.id,
          p.copyWith(oldBelong: 0, belong: 65535, arms: 0),
        );
        if (entry.actual != null) world.removePerson(entry.actual!, entry.id);
        (rows.putIfAbsent(entry.city, () => _row(entry.city))['executed']
                as List<String>)
            .add(_person(world, entry.id));
      }
      _record(world, '处死全部在野', rows.values.toList());
      return CheatResult(isSuccess: true, message: '已处死${entries.length}名在野武将');
    }
    if (action == 'sgby_recruit_captives' ||
        action == 'sgby_execute_captives') {
      if (selectedCity == null ||
          world.city(selectedCity)?.belong !=
              (world.playerRulerIndex ?? -1) + 1) {
        return const CheatResult(isSuccess: false, message: '请先在主地图选中一座我方城池');
      }
      final rows = captives(world, [
        selectedCity,
      ], action == 'sgby_recruit_captives' ? 'recruit' : 'execute');
      _record(world, action == 'sgby_recruit_captives' ? '手动招降' : '手动处斩', rows);
      return const CheatResult(isSuccess: true, message: '当前城池俘虏处理完成');
    }
    if (action == 'sgby_force_win') {
      if (battle == null || battle.result != 0) {
        return const CheatResult(isSuccess: false, message: '当前没有进行中的战斗');
      }
      for (var i = 10; i < 20; i++) {
        final id = battle.people[i];
        if (id == null) continue;
        final p = world.person(id)!;
        world.battleRecord.armsLost(
          (world.playerRulerIndex ?? -1) + 1,
          (world.playerRulerIndex ?? -1) + 1,
          p.belong,
          p.arms,
        );
        world.setPerson(id, p.copyWith(arms: 0));
        battle.units[i].state = 8;
      }
      battle.result = 1;
      return const CheatResult(isSuccess: true, message: '当前战斗已判定为我方胜利');
    }
    return const CheatResult(isSuccess: false, message: '未知操作');
  }
}

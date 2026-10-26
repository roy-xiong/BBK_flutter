/// 单座城池一次搜索中发现的人物和物品。
class SgbySearchCityRecord {
  const SgbySearchCityRecord({
    required this.cityName,
    required this.people,
    required this.tools,
    required this.recruited,
    required this.executed,
    required this.exiled,
  });

  factory SgbySearchCityRecord.fromJson(Map<String, dynamic> json) {
    List<String> strings(String key) {
      final value = json[key];
      return value is List
          ? value.whereType<String>().toList(growable: false)
          : const <String>[];
    }

    return SgbySearchCityRecord(
      cityName: json['cityName'] as String? ?? '未知城池',
      people: strings('people'),
      tools: strings('tools'),
      recruited: strings('recruited'),
      executed: strings('executed'),
      exiled: strings('exiled'),
    );
  }

  final String cityName;
  final List<String> people;
  final List<String> tools;
  final List<String> recruited;
  final List<String> executed;
  final List<String> exiled;
}

/// 三国霸业搜索记录对应的战斗方向。
enum SgbyBattleDirection {
  playerAttack,
  playerDefence,
  auto;

  static SgbyBattleDirection? fromWireValue(String? value) {
    for (final direction in values) {
      if (direction.name == value) return direction;
    }
    return null;
  }
}

/// 战斗开始时保存的来源快照。
///
/// 城池归属会在结算时改变，因此 UI 只展示引擎在 `enterBattle` 阶段记录的双方主公和
/// 战斗城市，不根据当前存档状态二次推断，避免胜利占城后把防守主公显示成我方。
class SgbySearchBattleSource {
  const SgbySearchBattleSource({
    required this.direction,
    required this.cityName,
    required this.attackerRulerName,
    required this.defenderRulerName,
  });

  factory SgbySearchBattleSource.fromJson(Map<String, dynamic> json) {
    final rawDirection = json['direction'];
    final direction = SgbyBattleDirection.fromWireValue(
      rawDirection is String ? rawDirection : null,
    );
    if (direction == null) {
      throw const FormatException('无效的战斗来源方向');
    }
    String readString(String key, String fallback) {
      final value = json[key];
      return value is String && value.isNotEmpty ? value : fallback;
    }

    return SgbySearchBattleSource(
      direction: direction,
      cityName: readString('cityName', '未知城池'),
      attackerRulerName: readString('attackerRulerName', '未知主公'),
      defenderRulerName: readString('defenderRulerName', '未知主公'),
    );
  }

  final SgbyBattleDirection direction;
  final String cityName;
  final String attackerRulerName;
  final String defenderRulerName;
}

/// 三国霸业单次搜索历史记录。
class SgbySearchHistoryRecord {
  const SgbySearchHistoryRecord({
    required this.realTime,
    required this.gameTime,
    required this.source,
    required this.peopleCount,
    required this.toolCount,
    required this.recruitedCount,
    required this.executedCount,
    required this.exiledCount,
    required this.cities,
    this.battleSource,
  });

  factory SgbySearchHistoryRecord.fromJson(Map<String, dynamic> json) {
    final rawCities = json['cities'];
    final rawBattleSource = json['battle'];
    SgbySearchBattleSource? battleSource;
    if (rawBattleSource is Map) {
      try {
        battleSource = SgbySearchBattleSource.fromJson(
          Map<String, dynamic>.from(rawBattleSource),
        );
      } on FormatException {
        // 旧版本或损坏的可选来源不应阻断整份搜索历史展示。
      }
    }
    return SgbySearchHistoryRecord(
      realTime: json['realTime'] as String? ?? '未知时间',
      gameTime: json['gameTime'] as String? ?? '未知年月',
      source: json['source'] as String? ?? '搜索',
      peopleCount: (json['peopleCount'] as num?)?.toInt() ?? 0,
      toolCount: (json['toolCount'] as num?)?.toInt() ?? 0,
      recruitedCount: (json['recruitedCount'] as num?)?.toInt() ?? 0,
      executedCount: (json['executedCount'] as num?)?.toInt() ?? 0,
      exiledCount: (json['exiledCount'] as num?)?.toInt() ?? 0,
      battleSource: battleSource,
      cities: rawCities is List
          ? rawCities
                .whereType<Map>()
                .map(
                  (value) => SgbySearchCityRecord.fromJson(
                    Map<String, dynamic>.from(value),
                  ),
                )
                .toList(growable: false)
          : const <SgbySearchCityRecord>[],
    );
  }

  final String realTime;
  final String gameTime;
  final String source;
  final int peopleCount;
  final int toolCount;
  final int recruitedCount;
  final int executedCount;
  final int exiledCount;
  final List<SgbySearchCityRecord> cities;
  final SgbySearchBattleSource? battleSource;
}

/// 搜索历史查询结果。
class SgbySearchHistoryData {
  const SgbySearchHistoryData({required this.isSuccess, required this.records});

  factory SgbySearchHistoryData.fromJson(Map<String, dynamic> json) {
    final rawRecords = json['records'];
    return SgbySearchHistoryData(
      isSuccess: json['ok'] == true,
      records: rawRecords is List
          ? rawRecords
                .whereType<Map>()
                .map(
                  (value) => SgbySearchHistoryRecord.fromJson(
                    Map<String, dynamic>.from(value),
                  ),
                )
                .toList(growable: false)
          : const <SgbySearchHistoryRecord>[],
    );
  }

  final bool isSuccess;
  final List<SgbySearchHistoryRecord> records;
}

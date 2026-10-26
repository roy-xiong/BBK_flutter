/// 三国霸业敌方城池内单个武将的只读信息。
class SgbyEnemyCityGeneralInfo {
  const SgbyEnemyCityGeneralInfo({
    required this.name,
    required this.level,
    required this.force,
    required this.iq,
    required this.devotion,
    required this.arms,
    required this.armsType,
    required this.isCaptive,
  });

  factory SgbyEnemyCityGeneralInfo.fromJson(Map<String, dynamic> json) {
    int integer(String key) => (json[key] as num?)?.toInt() ?? 0;

    return SgbyEnemyCityGeneralInfo(
      name: json['name'] as String? ?? '未知武将',
      level: integer('level'),
      force: integer('force'),
      iq: integer('iq'),
      devotion: integer('devotion'),
      arms: integer('arms'),
      armsType: integer('armsType'),
      isCaptive: json['captive'] == true,
    );
  }

  final String name;
  final int level;
  final int force;
  final int iq;
  final int devotion;
  final int arms;
  final int armsType;
  final bool isCaptive;
}

/// 三国霸业长按敌方城池时由本地游戏引擎返回的信息快照。
class SgbyEnemyCityInfo {
  const SgbyEnemyCityInfo({
    required this.name,
    required this.rulerName,
    required this.generals,
  });

  factory SgbyEnemyCityInfo.fromJson(Map<String, dynamic> json) {
    final rawGenerals = json['generals'];
    return SgbyEnemyCityInfo(
      name: json['name'] as String? ?? '未知城池',
      rulerName: json['rulerName'] as String? ?? '未知势力',
      generals: rawGenerals is List
          ? rawGenerals
                .whereType<Map>()
                .map(
                  (value) => SgbyEnemyCityGeneralInfo.fromJson(
                    Map<String, dynamic>.from(value),
                  ),
                )
                .toList(growable: false)
          : const <SgbyEnemyCityGeneralInfo>[],
    );
  }

  final String name;
  final String rulerName;
  final List<SgbyEnemyCityGeneralInfo> generals;
}

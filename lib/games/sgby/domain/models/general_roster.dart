/// 游戏引擎执行作弊操作后的结构化结果。
class CheatResult {
  const CheatResult({required this.isSuccess, required this.message});

  final bool isSuccess;
  final String message;
}

/// 请求游戏引擎打开存档界面后的结构化结果。
class SaveMenuResult {
  const SaveMenuResult({required this.isSuccess, required this.message});

  final bool isSuccess;
  final String message;
}

/// 三国霸业将领列表固定分组。
enum SgbyGeneralGroup {
  player,
  enemy,
  currentWild,
  futureWild;

  /// 解析增强脚本返回的白名单值；未知值按敌方只读处理，避免误开放属性修改。
  static SgbyGeneralGroup fromWireValue(String? value) {
    for (final group in values) {
      if (group.name == value) return group;
    }
    return enemy;
  }
}

/// 三国霸业单个武将的属性与列表归属快照。
class SgbyGeneralCheatInfo {
  const SgbyGeneralCheatInfo({
    required this.index,
    required this.name,
    required this.group,
    required this.factionName,
    required this.isRuler,
    required this.appearanceYear,
    required this.cityIndex,
    required this.cityName,
    required this.level,
    required this.force,
    required this.iq,
    required this.devotion,
    required this.thew,
    required this.experience,
    required this.arms,
    required this.baseArmsType,
    required this.effectiveArmsType,
    required this.inBattle,
    required this.battleMove,
    required this.battleHp,
    required this.battleMp,
    required this.battleState,
    required this.canAct,
  });

  factory SgbyGeneralCheatInfo.fromJson(Map<String, dynamic> json) {
    int integer(String key) => (json[key] as num?)?.toInt() ?? 0;

    return SgbyGeneralCheatInfo(
      index: integer('index'),
      name: json['name'] as String? ?? '未知武将',
      group: SgbyGeneralGroup.fromWireValue(json['group'] as String?),
      factionName: json['factionName'] as String? ?? '未知势力',
      isRuler: json['isRuler'] == true,
      appearanceYear: integer('appearanceYear'),
      cityIndex: integer('cityIndex'),
      cityName: json['cityName'] as String? ?? '未知城池',
      level: integer('level'),
      force: integer('force'),
      iq: integer('iq'),
      devotion: integer('devotion'),
      thew: integer('thew'),
      experience: integer('experience'),
      arms: integer('arms'),
      baseArmsType: integer('baseArmsType'),
      effectiveArmsType: integer('effectiveArmsType'),
      inBattle: json['inBattle'] == true,
      battleMove: integer('battleMove'),
      battleHp: integer('battleHp'),
      battleMp: integer('battleMp'),
      battleState: integer('battleState'),
      canAct: json['canAct'] == true,
    );
  }

  final int index;
  final String name;
  final SgbyGeneralGroup group;
  final String factionName;
  final bool isRuler;
  final int appearanceYear;
  final int cityIndex;
  final String cityName;
  final int level;
  final int force;
  final int iq;
  final int devotion;
  final int thew;
  final int experience;
  final int arms;
  final int baseArmsType;
  final int effectiveArmsType;
  final bool inBattle;
  final int battleMove;
  final int battleHp;
  final int battleMp;
  final int battleState;
  final bool canAct;
}

/// 三国霸业作弊面板所需的武将列表和版本级别上限。
class SgbyCheatData {
  const SgbyCheatData({
    required this.isSuccess,
    required this.message,
    required this.maxLevel,
    required this.generals,
  });

  factory SgbyCheatData.fromJson(Map<String, dynamic> json) {
    final rawGenerals = json['generals'];
    return SgbyCheatData(
      isSuccess: json['ok'] == true,
      message: json['message'] as String? ?? '',
      maxLevel: (json['maxLevel'] as num?)?.toInt() ?? 20,
      generals: rawGenerals is List
          ? rawGenerals
                .whereType<Map>()
                .map(
                  (value) => SgbyGeneralCheatInfo.fromJson(
                    Map<String, dynamic>.from(value),
                  ),
                )
                .toList(growable: false)
          : const <SgbyGeneralCheatInfo>[],
    );
  }

  final bool isSuccess;
  final String message;
  final int maxLevel;
  final List<SgbyGeneralCheatInfo> generals;
}

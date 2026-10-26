/// 原版37字节城池记录。队列起点和长度原样保存，不能根据人物归属重新推断在野或俘虏位置。
///
/// 会话通过替换整个记录提交变化，界面持有的旧记录不会被异步任务修改。
final class GameCity {
  const GameCity({
    required this.state,
    required this.belong,
    required this.satrapId,
    required this.farmingLimit,
    required this.farming,
    required this.commerceLimit,
    required this.commerce,
    required this.peopleDevotion,
    required this.avoidCalamity,
    required this.populationLimit,
    required this.population,
    required this.money,
    required this.food,
    required this.mothballArms,
    required this.personQueue,
    required this.persons,
    required this.toolQueue,
    required this.tools,
  });

  final int state;
  final int belong;
  final int satrapId;
  final int farmingLimit;
  final int farming;
  final int commerceLimit;
  final int commerce;
  final int peopleDevotion;
  final int avoidCalamity;
  final int populationLimit;
  final int population;
  final int money;
  final int food;
  final int mothballArms;
  final int personQueue;
  final int persons;
  final int toolQueue;
  final int tools;

  /// 生成属性快照；未指定的可空参数保留当前值。
  GameCity copyWith({
    int? state,
    int? belong,
    int? satrapId,
    int? farmingLimit,
    int? farming,
    int? commerceLimit,
    int? commerce,
    int? peopleDevotion,
    int? avoidCalamity,
    int? populationLimit,
    int? population,
    int? money,
    int? food,
    int? mothballArms,
    int? personQueue,
    int? persons,
    int? toolQueue,
    int? tools,
  }) => GameCity(
    state: state ?? this.state,
    belong: belong ?? this.belong,
    satrapId: satrapId ?? this.satrapId,
    farmingLimit: farmingLimit ?? this.farmingLimit,
    farming: farming ?? this.farming,
    commerceLimit: commerceLimit ?? this.commerceLimit,
    commerce: commerce ?? this.commerce,
    peopleDevotion: peopleDevotion ?? this.peopleDevotion,
    avoidCalamity: avoidCalamity ?? this.avoidCalamity,
    populationLimit: populationLimit ?? this.populationLimit,
    population: population ?? this.population,
    money: money ?? this.money,
    food: food ?? this.food,
    mothballArms: mothballArms ?? this.mothballArms,
    personQueue: personQueue ?? this.personQueue,
    persons: persons ?? this.persons,
    toolQueue: toolQueue ?? this.toolQueue,
    tools: tools ?? this.tools,
  );

  /// 使用原版字段名导出，以便对照旧内核或写入版本化存档。
  Map<String, Object?> toJson() => <String, Object?>{
    'State': state,
    'Belong': belong,
    'SatrapId': satrapId,
    'FarmingLimit': farmingLimit,
    'Farming': farming,
    'CommerceLimit': commerceLimit,
    'Commerce': commerce,
    'PeopleDevotion': peopleDevotion,
    'AvoidCalamity': avoidCalamity,
    'PopulationLimit': populationLimit,
    'Population': population,
    'Money': money,
    'Food': food,
    'MothballArms': mothballArms,
    'PersonQueue': personQueue,
    'Persons': persons,
    'ToolQueue': toolQueue,
    'Tools': tools,
  };
}

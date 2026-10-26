/// 原版19字节武将记录的不可变表示。人物编号为0基，归属与装备引用保留原版1基值。
///
/// 会话通过替换整个记录提交变化，界面持有的旧记录不会被异步任务修改。
final class GamePerson {
  const GamePerson({
    required this.oldBelong,
    required this.belong,
    required this.level,
    required this.force,
    required this.iq,
    required this.devotion,
    required this.character,
    required this.experience,
    required this.thew,
    required this.armsType,
    required this.arms,
    required this.equip0,
    required this.equip1,
    required this.age,
  });

  final int oldBelong;
  final int belong;
  final int level;
  final int force;
  final int iq;
  final int devotion;
  final int character;
  final int experience;
  final int thew;
  final int armsType;
  final int arms;
  final int equip0;
  final int equip1;
  final int age;

  /// 生成属性快照；未指定的可空参数保留当前值。
  GamePerson copyWith({
    int? oldBelong,
    int? belong,
    int? level,
    int? force,
    int? iq,
    int? devotion,
    int? character,
    int? experience,
    int? thew,
    int? armsType,
    int? arms,
    int? equip0,
    int? equip1,
    int? age,
  }) => GamePerson(
    oldBelong: oldBelong ?? this.oldBelong,
    belong: belong ?? this.belong,
    level: level ?? this.level,
    force: force ?? this.force,
    iq: iq ?? this.iq,
    devotion: devotion ?? this.devotion,
    character: character ?? this.character,
    experience: experience ?? this.experience,
    thew: thew ?? this.thew,
    armsType: armsType ?? this.armsType,
    arms: arms ?? this.arms,
    equip0: equip0 ?? this.equip0,
    equip1: equip1 ?? this.equip1,
    age: age ?? this.age,
  );

  /// 使用原版字段名导出，以便对照旧内核或写入版本化存档。
  Map<String, Object?> toJson() => <String, Object?>{
    'OldBelong': oldBelong,
    'Belong': belong,
    'Level': level,
    'Force': force,
    'IQ': iq,
    'Devotion': devotion,
    'Character': character,
    'Experience': experience,
    'Thew': thew,
    'ArmsType': armsType,
    'Arms': arms,
    'Age': age,
    'Equip': <int>[equip0, equip1],
  };
}

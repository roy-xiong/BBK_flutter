/// 道具的基础与精修属性。攻击范围保存在资源层，状态模型只保存可变属性。
///
/// 会话通过替换整个记录提交变化，界面持有的旧记录不会被异步任务修改。
final class GameTool {
  const GameTool({
    required this.useFlag,
    required this.attack,
    required this.iq,
    required this.move,
    required this.arm,
  });

  final int useFlag;
  final int attack;
  final int iq;
  final int move;
  final int arm;

  /// 生成属性快照；未指定的可空参数保留当前值。
  GameTool copyWith({
    int? useFlag,
    int? attack,
    int? iq,
    int? move,
    int? arm,
  }) => GameTool(
    useFlag: useFlag ?? this.useFlag,
    attack: attack ?? this.attack,
    iq: iq ?? this.iq,
    move: move ?? this.move,
    arm: arm ?? this.arm,
  );

  /// 使用原版字段名导出，以便对照旧内核或写入版本化存档。
  Map<String, Object?> toJson() => <String, Object?>{
    'useflag': useFlag,
    'at': attack,
    'iq': iq,
    'move': move,
    'arm': arm,
  };
}

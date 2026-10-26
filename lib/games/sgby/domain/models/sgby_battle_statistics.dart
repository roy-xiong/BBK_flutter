/// 三国霸业一局游戏的累计战斗伤亡；数据由实际伤害和死亡事件产生。
class SgbyBattleStatistics {
  const SgbyBattleStatistics({
    required this.lostSoldiers,
    required this.lostGenerals,
    required this.killedSoldiers,
    required this.killedGenerals,
    required this.hasFullHistory,
  });

  final int lostSoldiers;
  final int lostGenerals;
  final int killedSoldiers;
  final int killedGenerals;
  final bool hasFullHistory;

  /// 只接受完整、非负且可精确表示的计数；坏消息不能覆盖正在显示的有效战绩。
  static SgbyBattleStatistics? tryParse(Object? value) {
    if (value is! Map || value['hasFullHistory'] is! bool) return null;
    final counters = <int>[];
    for (final field in const <String>[
      'lostSoldiers',
      'lostGenerals',
      'killedSoldiers',
      'killedGenerals',
    ]) {
      final count = value[field];
      if (count is! num ||
          !count.isFinite ||
          count < 0 ||
          count > 9007199254740991 ||
          count != count.truncate()) {
        return null;
      }
      counters.add(count.toInt());
    }
    return SgbyBattleStatistics(
      lostSoldiers: counters[0],
      lostGenerals: counters[1],
      killedSoldiers: counters[2],
      killedGenerals: counters[3],
      hasFullHistory: value['hasFullHistory'] as bool,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SgbyBattleStatistics &&
      lostSoldiers == other.lostSoldiers &&
      lostGenerals == other.lostGenerals &&
      killedSoldiers == other.killedSoldiers &&
      killedGenerals == other.killedGenerals &&
      hasFullHistory == other.hasFullHistory;

  @override
  int get hashCode => Object.hash(
    lostSoldiers,
    lostGenerals,
    killedSoldiers,
    killedGenerals,
    hasFullHistory,
  );
}

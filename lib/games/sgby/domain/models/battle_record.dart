import 'sgby_battle_statistics.dart';

/// 与世界存档绑定的战绩；同一武将的真正死亡只累计一次，俘虏不计阵亡。
final class BattleRecord {
  BattleRecord({this.hasFullHistory = true});
  bool hasFullHistory;
  int lostSoldiers = 0,
      lostGenerals = 0,
      killedSoldiers = 0,
      killedGenerals = 0;
  final Set<int> deadPeople = <int>{};
  int _add(int a, int b) => (a + b).clamp(0, 9007199254740991);
  void armsLost(int player, int source, int victim, int loss) {
    if (loss <= 0 || victim == 0 || victim == 65535) return;
    if (victim == player) {
      lostSoldiers = _add(lostSoldiers, loss);
    } else if (source == player) {
      killedSoldiers = _add(killedSoldiers, loss);
    }
  }

  void generalDied(int player, int person, int victim, int arms, int winner) {
    if (victim == 0 || victim == 65535 || deadPeople.contains(person)) return;
    if (victim == player) {
      lostGenerals = _add(lostGenerals, 1);
    } else if (winner == player) {
      killedGenerals = _add(killedGenerals, 1);
    } else {
      return;
    }
    deadPeople.add(person);
    armsLost(player, winner, victim, arms);
  }

  SgbyBattleStatistics get statistics => SgbyBattleStatistics(
    lostSoldiers: lostSoldiers,
    lostGenerals: lostGenerals,
    killedSoldiers: killedSoldiers,
    killedGenerals: killedGenerals,
    hasFullHistory: hasFullHistory,
  );
  Map<String, Object?> toJson() => {
    'lostSoldiers': lostSoldiers,
    'lostGenerals': lostGenerals,
    'killedSoldiers': killedSoldiers,
    'killedGenerals': killedGenerals,
    'hasFullHistory': hasFullHistory,
    'deadPeople': deadPeople.toList(growable: false),
  };
  static BattleRecord decode(Object? value) {
    final statistics = SgbyBattleStatistics.tryParse(value);
    if (statistics == null || value is! Map) {
      return BattleRecord(hasFullHistory: false);
    }
    final record = BattleRecord(hasFullHistory: statistics.hasFullHistory)
      ..lostSoldiers = statistics.lostSoldiers
      ..lostGenerals = statistics.lostGenerals
      ..killedSoldiers = statistics.killedSoldiers
      ..killedGenerals = statistics.killedGenerals;
    final dead = value['deadPeople'];
    if (dead is List) {
      record.deadPeople.addAll(
        dead.whereType<int>().where((id) => id >= 0 && id < 2000),
      );
    }
    return record;
  }
}

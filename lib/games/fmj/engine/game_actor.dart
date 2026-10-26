import 'dart:math' as math;
import '../data/game_data.dart';

/// 单个会话拥有的角色实例；资源定义与可变战斗状态分别保存。
final class GameActor {
  GameActor(this.type, this.index);
  final int type;
  final int index;
  String name = '';
  int x = 0, y = 0, direction = 3, step = 0, state = 0, delay = 0;
  int sprite = 1, level = 1, maxHp = 1, hp = 1, maxMp = 0, mp = 0;
  int attack = 0, defense = 0, speed = 0, spirit = 0, luck = 0, exp = 0;
  int chain = 0, learned = 0, immunity = 0, attackStatus = 0, status = 0;
  int money = 0, rewardExp = 0, combatX = 0, combatY = 0, combatFrame = 1;
  int tick = 0, pause = 0, iq = 0, attackStatusRounds = 0, permanentStatus = 0;
  bool visible = true;
  final Map<int, int> immunityCounts = {};
  final Map<int, (int, int)> modifiers = {};

  /// 免疫由多件装备共同贡献，卸下一件不会误清除另一件的相同免疫。
  void changeImmunity(int mask, int delta) {
    for (final bit in [1, 2, 4, 8, 16]) {
      if (mask & bit == 0) continue;
      final count = math.max(
        0,
        (immunityCounts[bit] ?? (immunity & bit != 0 ? 1 : 0)) + delta,
      );
      immunityCounts[bit] = count;
      if (count > 0) {
        immunity |= bit;
      } else {
        immunity &= ~bit;
      }
    }
  }

  void clearStatus(int mask) {
    status &= ~mask;
    permanentStatus &= ~mask;
    for (final bit in statusRounds.keys.toList()) {
      if (mask & bit != 0) statusRounds.remove(bit);
    }
  }

  final List<String?> equipment = List.filled(8, null);
  final List<String> extraMagic = [];
  final Map<int, int> statusRounds = {};
  final List<int> drop = [0, 0, 0];
  final List<int> steal = [0, 0, 0];
  bool get alive => hp > 0;

  static GameActor? load(GameData data, int type, int index) {
    final r = data.record(3, type, index);
    if (r == null) return null;
    final a = GameActor(type, index);
    if (type == 1) {
      a.direction = r.byte(2).clamp(1, 4);
      a.step = r.byte(3);
      a.sprite = r.byte(22);
      a.name = r.text(10);
      a.chain = r.byte(23);
      a.learned = r.byte(9);
      a.level = r.byte(32);
      a.maxHp = math.min(999, r.word(38));
      a.hp = math.min(a.maxHp, r.word(40));
      a.maxMp = math.min(999, r.word(42));
      a.mp = math.min(a.maxMp, r.word(44));
      a.attack = r.word(46);
      a.defense = r.word(48);
      a.exp = r.word(50);
      a.speed = r.byte(54);
      a.spirit = r.byte(55);
      a.luck = r.byte(56);
      const offsets = [30, 31, 27, 29, 28, 25, 26, 24],
          types = [6, 6, 5, 3, 7, 2, 4, 1];
      for (var i = 0; i < 8; i++) {
        final item = r.byte(offsets[i]);
        if (item > 0) a.equipment[i] = '${types[i]}:$item';
      }
    } else if (type == 3) {
      a.name = r.text(6);
      a.level = r.byte(18);
      a.speed = r.byte(19);
      a.spirit = r.byte(20);
      a.luck = r.byte(22);
      a.maxHp = math.min(999, r.word(24));
      a.hp = a.maxHp;
      a.maxMp = math.min(999, r.word(28));
      a.mp = a.maxMp;
      a.attack = r.word(32);
      a.defense = r.word(34);
      a.money = r.word(36);
      a.rewardExp = r.word(38);
      a.iq = r.byte(21);
      a.attackStatusRounds = r.byte(23);
      a.chain = r.byte(47);
      a.learned = r.byte(2);
      a.immunity = r.byte(3);
      a.attackStatus = r.byte(4);
      a.sprite = r.byte(46);
      for (var i = 0; i < 3; i++) {
        a.steal[i] = r.byte(40 + i);
        a.drop[i] = r.byte(43 + i);
      }
    } else {
      a.name = r.text(9);
      a.direction = type == 4 ? 1 : r.byte(2).clamp(1, 4);
      a.step = r.byte(3);
      a.state = r.byte(4);
      a.delay = r.byte(21);
      a.sprite = r.byte(22);
      if (type == 2 && a.delay == 0) a.state = 0;
    }
    return a;
  }

  List<String> magics(GameData data) {
    final r = data.record(12, 1, chain);
    final result = <String>[];
    if (r != null) {
      for (var i = 0; i < math.min(learned, r.byte(2)); i++) {
        result.add('${r.byte(3 + i * 2)}:${r.byte(4 + i * 2)}');
      }
    }
    result.addAll(extraMagic.where((v) => !result.contains(v)));
    return result;
  }

  /// 升级按 MLR 每级差值增量处理，保留仙药和剧情增加的永久属性。
  void levelUp(GameData data, int to) {
    final r = data.record(12, 2, index);
    if (r == null) return;
    to = to.clamp(1, r.byte(2));
    if (to <= level) return;
    int word(int l, int field) => r.word(4 + (l - 1) * 20 + field);
    int byte(int l, int field) => r.byte(4 + (l - 1) * 20 + field);
    maxHp = (maxHp + word(to, 0) - word(level, 0)).clamp(1, 999);
    hp = maxHp;
    maxMp = (maxMp + word(to, 4) - word(level, 4)).clamp(0, 999);
    mp = maxMp;
    attack = (attack + word(to, 8) - word(level, 8)).clamp(0, 999);
    defense = (defense + word(to, 10) - word(level, 10)).clamp(0, 999);
    speed = (speed + byte(to, 16) - byte(level, 16)).clamp(0, 99);
    spirit = (spirit + byte(to, 17) - byte(level, 17)).clamp(0, 99);
    luck = (luck + byte(to, 18) - byte(level, 18)).clamp(0, 99);
    learned = byte(to, 19);
    level = to;
  }

  Map<String, dynamic> toJson() => {
    'type': type,
    'index': index,
    'name': name,
    'x': x,
    'y': y,
    'direction': direction,
    'step': step,
    'state': state,
    'delay': delay,
    'sprite': sprite,
    'level': level,
    'maxHp': maxHp,
    'hp': hp,
    'maxMp': maxMp,
    'mp': mp,
    'attack': attack,
    'defense': defense,
    'speed': speed,
    'spirit': spirit,
    'luck': luck,
    'exp': exp,
    'chain': chain,
    'learned': learned,
    'immunity': immunity,
    'attackStatus': attackStatus,
    'status': status,
    'equipment': equipment,
    'extraMagic': extraMagic,
    'statusRounds': statusRounds.map((key, value) => MapEntry('$key', value)),
    'immunityCounts': immunityCounts.map(
      (key, value) => MapEntry('$key', value),
    ),
    'modifiers': modifiers.map(
      (key, value) => MapEntry('$key', [value.$1, value.$2]),
    ),
    'permanentStatus': permanentStatus,
    'attackStatusRounds': attackStatusRounds,
    'tick': tick,
    'pause': pause,
  };
  static GameActor fromJson(Map<String, dynamic> j) {
    int n(String key, [int fallback = 0]) =>
        j[key] is int ? (j[key] as int).clamp(-1000000, 1000000) : fallback;
    final a = GameActor(n('type'), n('index'));
    a.name = j['name'] as String? ?? '';
    a.x = n('x');
    a.y = n('y');
    a.direction = n('direction', 3).clamp(1, 4);
    a.step = n('step') % 4;
    a.state = n('state');
    a.delay = n('delay');
    a.sprite = n('sprite', 1);
    a.level = n('level', 1).clamp(1, 255);
    a.maxHp = n('maxHp', 1).clamp(1, 999);
    a.hp = n('hp').clamp(0, a.maxHp);
    a.maxMp = n('maxMp').clamp(0, 999);
    a.mp = n('mp').clamp(0, a.maxMp);
    a.attack = n('attack');
    a.defense = n('defense');
    a.speed = n('speed');
    a.spirit = n('spirit');
    a.luck = n('luck');
    a.exp = n('exp');
    a.chain = n('chain');
    a.learned = n('learned');
    a.immunity = n('immunity');
    a.attackStatus = n('attackStatus');
    a.status = n('status');
    a.permanentStatus = n('permanentStatus');
    a.attackStatusRounds = n('attackStatusRounds');
    final rounds = j['statusRounds'];
    if (rounds is Map) {
      for (final entry in rounds.entries) {
        final bit = int.tryParse('${entry.key}');
        if (bit != null && entry.value is int) {
          a.statusRounds[bit] = entry.value as int;
        }
      }
    }
    final immunity = j['immunityCounts'];
    if (immunity is Map) {
      for (final entry in immunity.entries) {
        final bit = int.tryParse('${entry.key}');
        if (bit != null && entry.value is int) {
          a.immunityCounts[bit] = entry.value as int;
        }
      }
    }
    final modifiers = j['modifiers'];
    if (modifiers is Map) {
      for (final entry in modifiers.entries) {
        final bit = int.tryParse('${entry.key}'), value = entry.value;
        if (bit != null &&
            value is List &&
            value.length == 2 &&
            value[0] is int &&
            value[1] is int) {
          a.modifiers[bit] = (value[0] as int, value[1] as int);
        }
      }
    }

    a.tick = n('tick');
    a.pause = n('pause');
    final equipment = j['equipment'];
    if (equipment is List) {
      for (var i = 0; i < math.min(8, equipment.length); i++) {
        a.equipment[i] = equipment[i] is String ? equipment[i] as String : null;
      }
    }
    final magic = j['extraMagic'];
    if (magic is List) a.extraMagic.addAll(magic.whereType<String>());
    return a;
  }
}

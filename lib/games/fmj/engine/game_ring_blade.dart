part of 'game_engine.dart';

/// 大环刀只属于当前会话；配置经偏好持久化，图标复用全局图集的生命周期。
/// 加成使用实际已应用值回滚，避免改配置、升级、重读旧档导致重复加500。
final class GameRingBlade {
  GameRingBlade(this.game);
  final GameEngine game;
  static const id = '7:33';
  static const attributes = [
    'maxHp',
    'maxMp',
    'attack',
    'defense',
    'speed',
    'spirit',
    'luck',
  ];
  static const defaults = <String, dynamic>{
    'maxHp': 500,
    'maxMp': 500,
    'attack': 500,
    'defense': 500,
    'speed': 500,
    'spirit': 500,
    'luck': 500,
    'maxHpOn': true,
    'maxMpOn': true,
    'attackOn': true,
    'defenseOn': true,
    'speedOn': true,
    'spiritOn': true,
    'luckOn': true,
    'hpDrainOn': true,
    'hpDrain': 200,
    'mpDrainOn': true,
    'mpDrain': 200,
    'experienceOn': true,
    'experienceMultiplier': 2,
    'experienceScope': 'team',
    'groupAttack': true,
    'enemyPoison': false,
    'enemyConfuse': false,
    'enemySeal': false,
    'enemySleep': false,
    'statusRounds': 3,
    'immunityPoison': true,
    'immunityConfuse': true,
    'immunitySeal': true,
    'immunitySleep': true,
  };
  GameRecord? _record;
  Map<String, dynamic> _settings = defaults;
  Map<String, dynamic> get settings => _settings;
  bool enabled(String key) => settings[key] == true;
  int value(String key) => settings[key] as int? ?? defaults[key] as int? ?? 0;
  int _mask(String prefix) =>
      (enabled('${prefix}Sleep') ? 1 : 0) |
      (enabled('${prefix}Seal') ? 2 : 0) |
      (enabled('${prefix}Confuse') ? 4 : 0) |
      (enabled('${prefix}Poison') ? 8 : 0);
  int bonus(String key) => enabled('${key}On') ? value(key) : 0;

  /// 严格接受已知字段；设置页和旧偏好读入走同一校验，不接受NaN、浮点或字符串数值。
  void update(Map changes) {
    final next = Map<String, dynamic>.from(settings);
    for (final key in defaults.keys) {
      final candidate = changes[key];
      if (defaults[key] is bool && candidate is bool) {
        next[key] = candidate;
      }
      if (defaults[key] is int && candidate is int) {
        final minimum = key == 'experienceMultiplier' ? 1 : 0;
        final maximum = key == 'experienceMultiplier'
            ? 1000
            : key == 'statusRounds'
            ? 999
            : 999999;
        next[key] = candidate.clamp(minimum, maximum);
      }
      if (key == 'experienceScope' &&
          (candidate == 'team' || candidate == 'wearer')) {
        next[key] = candidate;
      }
    }
    _settings = Map<String, dynamic>.unmodifiable(next);
    game.preferences['ringBlade'] = _settings;
    _record = null;
    synchronizePlayers();
  }

  GameRecord get record {
    game.data.customImages.putIfAbsent(
      '9:7:33',
      () => GameImage(16, 16, [
        GameBitmap.monochrome([
          0,
          2,
          6,
          14,
          62,
          124,
          504,
          1008,
          8128,
          3840,
          7168,
          12288,
          24576,
          16384,
          12288,
          0,
        ]),
      ], 32),
    );
    return _record ??= GameRecord.custom(
      game.data,
      {
        0: 7,
        1: 33,
        2: 134,
        3: 7,
        4: value('statusRounds'),
        5: 33,
        18: 0,
        20: 0,
        22: bonus('maxMp'),
        23: bonus('maxHp'),
        24: bonus('defense'),
        25: bonus('attack'),
        26: bonus('spirit'),
        27: bonus('speed'),
        28: (enabled('groupAttack') ? 16 : 0) | _mask('enemy'),
        29: bonus('luck'),
        132: 0,
      },
      {6: '大环刀', 30: '百草地隐藏宝刀。命中吸取气血/真气；经验、群攻、免疫与属性可在作弊的大环刀设置中调整。'},
    );
  }

  int _read(GameActor p, String key) => switch (key) {
    'maxHp' => p.maxHp,
    'maxMp' => p.maxMp,
    'attack' => p.attack,
    'defense' => p.defense,
    'speed' => p.speed,
    'spirit' => p.spirit,
    _ => p.luck,
  };
  void _write(GameActor p, String key, int n) {
    switch (key) {
      case 'maxHp':
        p.maxHp = n;
      case 'maxMp':
        p.maxMp = n;
      case 'attack':
        p.attack = n;
      case 'defense':
        p.defense = n;
      case 'speed':
        p.speed = n;
      case 'spirit':
        p.spirit = n;
      default:
        p.luck = n;
    }
  }

  /// 同时用于真正换装和只读换装投影；投影使用独立的bonus副本，不触碰实际库存。
  void applyAttributes(GameActor p, bool equipped) {
    for (final key in attributes) {
      final old = p.ringBladeBonus[key] ?? 0, next = equipped ? bonus(key) : 0;
      _write(
        p,
        key,
        math.max(key == 'maxHp' ? 1 : 0, _read(p, key) - old + next),
      );
      if (equipped) {
        p.ringBladeBonus[key] = next;
      } else {
        p.ringBladeBonus.remove(key);
      }
    }
    p.hp = p.hp.clamp(0, p.maxHp);
    p.mp = p.mp.clamp(0, p.maxMp);
  }

  void applySpecial(GameActor p, bool equipped) {
    if (p.ringBladeImmunity != 0) p.changeImmunity(p.ringBladeImmunity, -1);
    p.ringBladeImmunity = equipped ? _mask('immunity') : 0;
    if (p.ringBladeImmunity != 0) {
      p.changeImmunity(p.ringBladeImmunity, 1);
      p.clearStatus(p.ringBladeImmunity);
    }
    p.attackStatus = equipped ? record.byte(28) : 0;
    p.attackStatusRounds = equipped ? value('statusRounds') : 0;
  }

  void synchronizePlayers() {
    for (final p in game.players) {
      final equipped = p.equipment[4] == id;
      if (equipped || p.ringBladeBonus.isNotEmpty || p.ringBladeImmunity != 0) {
        applyAttributes(p, equipped);
        applySpecial(p, equipped);
      }
    }
  }

  /// 仅普通攻击真实命中的敌人结算，空挥、防御、自伤、法术和投掷不触发。
  /// 先普通伤害，再按敌人剩余资源吸取；回复不得超过装备者上限，资源不足不凭空增加。
  void drain(GameActor source, GameActor target, BattleAction? action) {
    if (action?.kind != 'attack' ||
        source.type != 1 ||
        target.type != 3 ||
        source.equipment[4] != id ||
        identical(source, target)) {
      return;
    }
    final hp = enabled('hpDrainOn')
        ? math.min(value('hpDrain'), math.max(0, target.hp))
        : 0;
    final mp = enabled('mpDrainOn')
        ? math.min(value('mpDrain'), math.max(0, target.mp))
        : 0;
    if (hp == 0 && mp == 0) return;
    action?.changes.putIfAbsent(source, () => source.hp);
    target.hp -= hp;
    target.mp -= mp;
    source.hp = math.min(source.maxHp, source.hp + hp);
    source.mp = math.min(source.maxMp, source.mp + mp);
  }

  /// 全队只乘一次，多人装备不指数叠加；装备者模式仅在逐人的经验分配阶段相乘。
  int experienceMultiplierFor(GameActor? actor) {
    if (!enabled('experienceOn')) return 1;
    if (settings['experienceScope'] == 'team') {
      return actor == null && game.players.any((p) => p.equipment[4] == id)
          ? value('experienceMultiplier')
          : 1;
    }
    return actor?.equipment[4] == id ? value('experienceMultiplier') : 1;
  }

  Iterable<String> get effectLabels sync* {
    if (enabled('groupAttack')) yield '普通攻击全体';
    for (final v in [(8, '中毒'), (4, '混乱'), (2, '咒封'), (1, '昏眠')]) {
      if (_mask('immunity') & v.$1 != 0) yield '免疫${v.$2}';
    }
    if (enabled('hpDrainOn')) yield '命中吸血${value('hpDrain')}';
    if (enabled('mpDrainOn')) yield '命中吸真气${value('mpDrain')}';
    if (enabled('experienceOn')) {
      yield '${settings['experienceScope'] == 'team' ? '全队' : '装备者'}经验×${value('experienceMultiplier')}';
    }
  }
}

/// 三国霸业增强开关的唯一状态。只持久化白名单字段，不接受任意脚本或代码。
///
/// 开关属于应用偏好，跨开局保留；战绩、搜索历史等每局数据由世界模型单独拥有。
final class GameOptions {
  GameOptions([Map<String, Object?>? saved]) {
    for (final key in booleans) {
      _values[key] = saved?[key] == true;
    }
    _values['factionColors'] = saved?['factionColors'] != false;
    _values['autoSaveAfterTurn'] = saved?['autoSaveAfterTurn'] != false;
    final armsLimit = saved?['enemyArmsLimit'];
    _values['enemyArmsLimit'] =
        armsLimit is int &&
            armsLimit >= minimumEnemyArms &&
            armsLimit <= maximumPersonArms
        ? armsLimit
        : maximumPersonArms;
    _values['searchOutcome'] = saved?['searchOutcome'] == 'none'
        ? 'none'
        : 'all';
    _values['postBattleCaptiveAction'] =
        [
          'recruit',
          'execute',
          'exile',
        ].contains(saved?['postBattleCaptiveAction'])
        ? saved!['postBattleCaptiveAction']
        : 'recruit';
    _values['battleLoserOutcome'] =
        [
          'original',
          'death',
          'captive',
          'escape',
          'wild',
        ].contains(saved?['battleLoserOutcome'])
        ? saved!['battleLoserOutcome']
        : 'original';
    final activity = saved?['worldActivity'];
    _values['worldActivity'] = activity is int ? activity.clamp(0, 100) : 50;
  }
  static const booleans = <String>[
    'autoSaveAfterTurn',
    'enemyArmsLimitEnabled',
    'diplomacyProtection',
    'hideSpecialGenerals',
    'invincible',
    'oneHitKill',
    'wideGroupAttack',
    'freeMovement',
    'autoMaxGenerals',
    'autoMaxCities',
    'foodProtection',
    'autoBattle',
    'autoEndTurn',
    'showTroopIcons',
    'attackAnyCity',
    'enemyEscapeRoute',
    'animationsDisabled',
    'postBattleAutomation',
    'factionColors',
  ];
  final Map<String, Object?> _values = <String, Object?>{};
  static const minimumEnemyArms = 800;
  static const maximumPersonArms = 200000;
  int get enemyArmsLimit => _values['enemyArmsLimit'] as int;

  /// 滑块提交必须为完整整数；非法输入不修改原设置。
  bool setEnemyArmsLimit(Object? value) {
    if (value is! int ||
        value < minimumEnemyArms ||
        value > maximumPersonArms) {
      return false;
    }
    _values['enemyArmsLimit'] = value;
    return true;
  }

  bool enabled(String key) => _values[key] == true;
  int get worldActivity => _values['worldActivity'] as int;
  String choice(String key) => _values[key] as String? ?? '';
  int get loserOutcome => [
    'original',
    'death',
    'captive',
    'escape',
    'wild',
  ].indexOf(choice('battleLoserOutcome')).clamp(0, 4);
  void toggle(String key, {bool? enabled}) {
    if (booleans.contains(key)) _values[key] = enabled ?? !this.enabled(key);
  }

  bool setChoice(String key, String value) {
    final choices = switch (key) {
      'searchOutcome' => ['none', 'all'],
      'postBattleCaptiveAction' => ['recruit', 'execute', 'exile'],
      'battleLoserOutcome' => [
        'original',
        'death',
        'captive',
        'escape',
        'wild',
      ],
      _ => <String>[],
    };
    if (!choices.contains(value)) return false;
    _values[key] = value;
    return true;
  }

  void setActivity(int value) => _values['worldActivity'] = value.clamp(0, 100);
  Map<String, Object?> toJson() => Map<String, Object?>.of(_values);
}

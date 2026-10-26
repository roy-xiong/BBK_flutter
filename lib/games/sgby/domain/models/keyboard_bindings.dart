import 'game_definition.dart';

/// 可持久化的实体键盘映射，按逻辑键 ID 解析，不持有页面、FocusNode 或平台资源。
///
/// 每个动作允许多个键。同一键仅属于一个动作；重新绑定时从旧动作移除，避免一次
/// 按键同时下达两条命令。损坏设置、无效动作及异常键值不会覆盖默认操作能力。
final class KeyboardBindings {
  KeyboardBindings([Object? saved]) {
    if (saved is! Map) return;
    final parsed = <GameInput, List<int>>{};
    final used = <int>{};
    for (final action in supported) {
      final values = saved[action.name];
      if (values is! List || values.length > 8) continue;
      parsed[action] = [
        for (final id in values)
          if (id is int && id > 0 && id <= 0x200000000 && used.add(id)) id,
      ];
    }
    for (final entry in parsed.entries) {
      _overrides[entry.key] = entry.value;
    }
  }
  static const supported = <GameInput>[
    GameInput.up,
    GameInput.down,
    GameInput.left,
    GameInput.right,
    GameInput.confirm,
    GameInput.cancel,
    GameInput.pageUp,
    GameInput.pageDown,
    GameInput.search,
    GameInput.help,
    GameInput.endTurn,
    GameInput.autoBattle,
    GameInput.autoEndTurn,
    GameInput.quickExpedition,
    GameInput.toggleBattleSpeed,
    GameInput.generalRoster,
    GameInput.searchHistory,
    GameInput.battleInfo,
    GameInput.toggleTroopIcons,
  ];
  final Map<GameInput, List<int>> _overrides = {};
  Map<String, Object?> toJson() => {
    for (final entry in _overrides.entries) entry.key.name: entry.value,
  };
  List<int>? keysFor(GameInput action) => _overrides[action];
  GameInput? resolve(int key, Map<int, GameInput> defaults) {
    for (final entry in _overrides.entries) {
      if (entry.value.contains(key)) return entry.key;
    }
    final action = defaults[key];
    return action != null && !_overrides.containsKey(action) ? action : null;
  }

  bool bind(GameInput action, int key, Map<int, GameInput> defaults) {
    if (!supported.contains(action) || key <= 0 || key > 0x200000000) {
      return false;
    }
    final previous = resolve(key, defaults);
    if (previous != null && previous != action) {
      _overrides[previous] = [
        for (final entry in defaults.entries)
          if (entry.value == previous &&
              entry.key != key &&
              !_overrides.containsKey(previous))
            entry.key,
        ...?_overrides[previous]?.where((id) => id != key),
      ];
    }
    for (final values in _overrides.values) {
      values.remove(key);
    }
    _overrides[action] = [key];
    return true;
  }

  void reset() => _overrides.clear();
}

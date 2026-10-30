import 'package:flutter/services.dart';

import 'game_controls.dart';

/// 沿用 BBK 的物理按键 code 字符串保存绑定，Flutter 各平台采用相同配置。
class GameKeyboardBindings {
  const GameKeyboardBindings(this.bindings);
  final Map<GameControl, List<String>> bindings;
  static const defaults = GameKeyboardBindings({
    GameControl.up: ['ArrowUp', 'KeyW'],
    GameControl.down: ['ArrowDown', 'KeyS'],
    GameControl.left: ['ArrowLeft', 'KeyA'],
    GameControl.right: ['ArrowRight', 'KeyD'],
    GameControl.confirm: ['Enter', 'KeyZ'],
    GameControl.cancel: ['Escape', 'KeyX'],
    GameControl.pageUp: ['PageUp'],
    GameControl.pageDown: ['PageDown'],
    GameControl.search: ['KeyF'],
    GameControl.help: ['KeyH'],
    GameControl.quickTravel: ['KeyQ'],
    GameControl.toggleFmjAutoBattle: ['KeyE'],
    GameControl.cycleFmjRunSpeed: ['KeyT'],
    GameControl.toggleWideView: ['KeyR'],
    GameControl.selectFmjStage: ['KeyV'],
  });
  static const labels = {
    GameControl.up: '上',
    GameControl.down: '下',
    GameControl.left: '左',
    GameControl.right: '右',
    GameControl.confirm: 'A · 确认',
    GameControl.cancel: 'B · 返回',
    GameControl.pageUp: '上翻页',
    GameControl.pageDown: '下翻页',
    GameControl.search: '搜索',
    GameControl.help: '帮助',
    GameControl.quickTravel: '一键前往 / 剧情与战斗 A 键',
    GameControl.toggleFmjAutoBattle: '自动战斗',
    GameControl.cycleFmjRunSpeed: '奔跑倍速',
    GameControl.toggleWideView: '远视野',
    GameControl.selectFmjStage: '选择关卡',
    GameControl.toggleMoneyFarm: '开始 / 停止刷钱',
    GameControl.quickThrow: '快捷投掷弯月刀 / 备用武器',
    GameControl.chooseThrowWeapon: '选择投掷武器',
    GameControl.quickMagic: '战斗技能',
    GameControl.quickCoop: '战斗合击',
  };
  Map<String, String> get byCode => {
    for (final entry in bindings.entries)
      for (final code in entry.value) code: entry.key.name,
  };
  Map<String, Object> toJson() => {
    for (final entry in bindings.entries) entry.key.name: entry.value,
  };
  static GameKeyboardBindings fromJson(Object? json) {
    if (json is! Map) return defaults;
    final result = <GameControl, List<String>>{}, seen = <String>{};
    for (final entry in json.entries) {
      final action = entry.key is String ? _action(entry.key as String) : null;
      if (!labels.containsKey(action) || entry.value is! List) continue;
      final codes = (entry.value as List)
          .whereType<String>()
          .where((code) => physicalKeys.containsKey(code) && seen.add(code))
          .take(8)
          .toList();
      result[action!] = List.unmodifiable(codes);
    }
    return GameKeyboardBindings(Map.unmodifiable(result));
  }

  GameControl? actionFor(String code) => _action(byCode[code]);

  /// 一个物理键只属于一个动作；重新绑定时移除旧动作，保留目标动作已有的其他键。
  GameKeyboardBindings bind(GameControl action, String code) {
    final changed = {
      for (final entry in bindings.entries)
        entry.key: entry.value.where((key) => key != code).toList(),
    };
    changed[action] = [...?changed[action], code];
    return fromJson({
      for (final entry in changed.entries) entry.key.name: entry.value,
    });
  }

  GameKeyboardBindings remove(GameControl action, String code) => fromJson({
    for (final entry in bindings.entries)
      entry.key.name: entry.key == action
          ? entry.value.where((key) => key != code).toList()
          : entry.value,
  });
  static String label(String code) =>
      const {
        'ArrowUp': '↑',
        'ArrowDown': '↓',
        'ArrowLeft': '←',
        'ArrowRight': '→',
        'Space': '空格',
      }[code] ??
      code.replaceFirst('Key', '').replaceFirst('Digit', '');
  static String? codeFor(PhysicalKeyboardKey key) {
    for (final entry in physicalKeys.entries) {
      if (entry.value == key) return entry.key;
    }
    return null;
  }

  static GameControl? _action(String? value) =>
      GameControl.values.where((action) => action.name == value).firstOrNull;

  static const physicalKeys = <String, PhysicalKeyboardKey>{
    'ArrowUp': PhysicalKeyboardKey.arrowUp,
    'ArrowDown': PhysicalKeyboardKey.arrowDown,
    'ArrowLeft': PhysicalKeyboardKey.arrowLeft,
    'ArrowRight': PhysicalKeyboardKey.arrowRight,
    'Enter': PhysicalKeyboardKey.enter,
    'Escape': PhysicalKeyboardKey.escape,
    'Space': PhysicalKeyboardKey.space,
    'PageUp': PhysicalKeyboardKey.pageUp,
    'PageDown': PhysicalKeyboardKey.pageDown,
    'Tab': PhysicalKeyboardKey.tab,
    'Backspace': PhysicalKeyboardKey.backspace,
    'Home': PhysicalKeyboardKey.home,
    'End': PhysicalKeyboardKey.end,
    'Insert': PhysicalKeyboardKey.insert,
    'Delete': PhysicalKeyboardKey.delete,
    'KeyA': PhysicalKeyboardKey.keyA,
    'KeyB': PhysicalKeyboardKey.keyB,
    'KeyC': PhysicalKeyboardKey.keyC,
    'KeyD': PhysicalKeyboardKey.keyD,
    'KeyE': PhysicalKeyboardKey.keyE,
    'KeyF': PhysicalKeyboardKey.keyF,
    'KeyG': PhysicalKeyboardKey.keyG,
    'KeyH': PhysicalKeyboardKey.keyH,
    'KeyI': PhysicalKeyboardKey.keyI,
    'KeyJ': PhysicalKeyboardKey.keyJ,
    'KeyK': PhysicalKeyboardKey.keyK,
    'KeyL': PhysicalKeyboardKey.keyL,
    'KeyM': PhysicalKeyboardKey.keyM,
    'KeyN': PhysicalKeyboardKey.keyN,
    'KeyO': PhysicalKeyboardKey.keyO,
    'KeyP': PhysicalKeyboardKey.keyP,
    'KeyQ': PhysicalKeyboardKey.keyQ,
    'KeyR': PhysicalKeyboardKey.keyR,
    'KeyS': PhysicalKeyboardKey.keyS,
    'KeyT': PhysicalKeyboardKey.keyT,
    'KeyU': PhysicalKeyboardKey.keyU,
    'KeyV': PhysicalKeyboardKey.keyV,
    'KeyW': PhysicalKeyboardKey.keyW,
    'KeyX': PhysicalKeyboardKey.keyX,
    'KeyY': PhysicalKeyboardKey.keyY,
    'KeyZ': PhysicalKeyboardKey.keyZ,
    'Digit0': PhysicalKeyboardKey.digit0,
    'Digit1': PhysicalKeyboardKey.digit1,
    'Digit2': PhysicalKeyboardKey.digit2,
    'Digit3': PhysicalKeyboardKey.digit3,
    'Digit4': PhysicalKeyboardKey.digit4,
    'Digit5': PhysicalKeyboardKey.digit5,
    'Digit6': PhysicalKeyboardKey.digit6,
    'Digit7': PhysicalKeyboardKey.digit7,
    'Digit8': PhysicalKeyboardKey.digit8,
    'Digit9': PhysicalKeyboardKey.digit9,
    'F1': PhysicalKeyboardKey.f1,
    'F2': PhysicalKeyboardKey.f2,
    'F3': PhysicalKeyboardKey.f3,
    'F4': PhysicalKeyboardKey.f4,
    'F5': PhysicalKeyboardKey.f5,
    'F6': PhysicalKeyboardKey.f6,
    'F7': PhysicalKeyboardKey.f7,
    'F8': PhysicalKeyboardKey.f8,
    'F9': PhysicalKeyboardKey.f9,
    'F10': PhysicalKeyboardKey.f10,
    'F11': PhysicalKeyboardKey.f11,
    'F12': PhysicalKeyboardKey.f12,
    'Minus': PhysicalKeyboardKey.minus,
    'Equal': PhysicalKeyboardKey.equal,
    'BracketLeft': PhysicalKeyboardKey.bracketLeft,
    'BracketRight': PhysicalKeyboardKey.bracketRight,
    'Semicolon': PhysicalKeyboardKey.semicolon,
    'Quote': PhysicalKeyboardKey.quote,
    'Comma': PhysicalKeyboardKey.comma,
    'Period': PhysicalKeyboardKey.period,
    'Slash': PhysicalKeyboardKey.slash,
    'Backslash': PhysicalKeyboardKey.backslash,
    'Backquote': PhysicalKeyboardKey.backquote,
  };
}

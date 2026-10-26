/// 三国霸业支持的全局游戏速度倍率，顺序同时用于按钮循环和状态恢复。
const List<int> sgbyGameSpeedMultipliers = <int>[1, 2, 3, 4, 6, 8];

/// 返回指定倍率的下一档；未知值回到 1x，避免界面与引擎状态继续分叉。
int nextSgbyGameSpeedMultiplier(int current) {
  final index = sgbyGameSpeedMultipliers.indexOf(current);
  if (index < 0 || index == sgbyGameSpeedMultipliers.length - 1) return 1;
  return sgbyGameSpeedMultipliers[index + 1];
}

/// Flutter 与游戏引擎之间统一使用的输入动作。
enum GameInput {
  up,
  down,
  left,
  right,
  confirm,
  cancel,
  pageUp,
  pageDown,
  search,
  help,
  endTurn,
  battleInfo,
  autoBattle,
  autoEndTurn,
  toggleTroopIcons,
  quickExpedition,
  quickTravel,
  mazeExit,
  toggleWideView,
  toggleFmjAutoBattle,
  cycleFmjRunSpeed,
  selectFmjStage,
  toggleBattleSpeed,
  searchHistory,
  generalRoster;

  static GameInput? fromWireValue(String? value) {
    for (final input in values) {
      if (input.name == value) return input;
    }
    return null;
  }
}

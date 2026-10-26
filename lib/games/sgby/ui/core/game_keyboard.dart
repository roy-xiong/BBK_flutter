import 'package:flutter/services.dart';

import '../../domain/models/game_definition.dart';

/// macOS、Windows 和移动实体键盘使用相同默认映射，快捷键不依赖操作系统。
final class GameKeyboard {
  static const labels = <GameInput, String>{
    GameInput.up: '上',
    GameInput.down: '下',
    GameInput.left: '左',
    GameInput.right: '右',
    GameInput.confirm: '确认',
    GameInput.cancel: '取消 / 返回',
    GameInput.pageUp: '上翻页',
    GameInput.pageDown: '下翻页',
    GameInput.search: '搜索',
    GameInput.help: '帮助',
    GameInput.endTurn: '结束回合',
    GameInput.autoBattle: '自动战斗',
    GameInput.autoEndTurn: '自动策略',
    GameInput.quickExpedition: '一键出征',
    GameInput.toggleBattleSpeed: '切换倍速',
    GameInput.generalRoster: '将领列表',
    GameInput.searchHistory: '搜索记录',
    GameInput.battleInfo: '战场信息',
    GameInput.toggleTroopIcons: '显示兵种',
  };
  static final defaults = <int, GameInput>{
    LogicalKeyboardKey.arrowUp.keyId: GameInput.up,
    LogicalKeyboardKey.arrowDown.keyId: GameInput.down,
    LogicalKeyboardKey.arrowLeft.keyId: GameInput.left,
    LogicalKeyboardKey.arrowRight.keyId: GameInput.right,
    LogicalKeyboardKey.enter.keyId: GameInput.confirm,
    LogicalKeyboardKey.keyZ.keyId: GameInput.confirm,
    LogicalKeyboardKey.escape.keyId: GameInput.cancel,
    LogicalKeyboardKey.space.keyId: GameInput.cancel,
    LogicalKeyboardKey.keyX.keyId: GameInput.cancel,
    LogicalKeyboardKey.pageUp.keyId: GameInput.pageUp,
    LogicalKeyboardKey.pageDown.keyId: GameInput.pageDown,
    LogicalKeyboardKey.keyH.keyId: GameInput.help,
    LogicalKeyboardKey.keyF.keyId: GameInput.search,
    LogicalKeyboardKey.keyS.keyId: GameInput.search,
    LogicalKeyboardKey.keyE.keyId: GameInput.endTurn,
    LogicalKeyboardKey.keyB.keyId: GameInput.autoBattle,
    LogicalKeyboardKey.keyT.keyId: GameInput.autoEndTurn,
    LogicalKeyboardKey.keyG.keyId: GameInput.quickExpedition,
    LogicalKeyboardKey.keyV.keyId: GameInput.toggleBattleSpeed,
    LogicalKeyboardKey.keyR.keyId: GameInput.generalRoster,
    LogicalKeyboardKey.keyL.keyId: GameInput.searchHistory,
    LogicalKeyboardKey.keyI.keyId: GameInput.battleInfo,
    LogicalKeyboardKey.keyU.keyId: GameInput.toggleTroopIcons,
    LogicalKeyboardKey.gameButtonA.keyId: GameInput.confirm,
    LogicalKeyboardKey.gameButtonB.keyId: GameInput.cancel,
    LogicalKeyboardKey.gameButtonX.keyId: GameInput.search,
    LogicalKeyboardKey.gameButtonY.keyId: GameInput.help,
    LogicalKeyboardKey.gameButtonLeft1.keyId: GameInput.pageUp,
    LogicalKeyboardKey.gameButtonRight1.keyId: GameInput.pageDown,
    LogicalKeyboardKey.gameButtonStart.keyId: GameInput.confirm,
    LogicalKeyboardKey.gameButtonSelect.keyId: GameInput.cancel,
  };
  static String label(int id) {
    final key = LogicalKeyboardKey.findKeyByKeyId(id);
    return key?.keyLabel.isNotEmpty == true ? key!.keyLabel : '键 $id';
  }
}

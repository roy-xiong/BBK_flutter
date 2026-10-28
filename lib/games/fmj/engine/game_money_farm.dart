part of 'game_engine.dart';

/// 建业富贵珠循环只驱动正式输入、导航和交易；不写金钱、不发奖励、不改剧情旗标。
///
/// 生命周期跟随GameEngine的固定帧，既无独立定时器，也不捕获界面。关闭、读档、
/// 手动方向输入均取消路线；已开始的战斗和已成交奖励保留在真实游戏会话中。
final class GameMoneyFarm {
  GameMoneyFarm(this.game);
  final GameEngine game;
  bool active = false;
  int rounds = 0;
  String phase = '';
  int _idle = 0;
  String _progress = '';
  bool _travelPending = false;
  GameBattle? _controlledBattle;
  bool _previousAuto = false;

  void toggle() {
    if (active) {
      stop('已停止刷钱，当前进度和已获得物品保留');
      return;
    }
    if (game.screen != 'play' || game.player == null || game.error.isNotEmpty) {
      game.notice = '进入游戏后才能一键刷钱';
      return;
    }
    if (game.flags.contains(221) ||
        game.flags.contains(1118) && !game.flags.contains(1117)) {
      game.notice = '当前剧情已关闭建业客栈循环；需要归还钱袋且尚未完成钟山赤血剧情';
      return;
    }
    if (game.operation != null ||
        game.battle != null ||
        game.menus.isNotEmpty ||
        game.cursor?.running == true) {
      game.notice = '先完成当前对话、菜单或战斗，再开始刷钱';
      return;
    }
    game.navigation.cancel();
    active = true;
    rounds = 0;
    phase = (game.inventory['6:12'] ?? 0) > 0 ? 'sell' : 'fight';
    _idle = 0;
    _progress = '';
    _travelPending = false;
    game.notice = '刷钱已开始：建业客栈战斗 → 当铺出售富贵珠；再次点击取消';
  }

  void stop([String? message]) {
    if (!active) return;
    active = false;
    game.navigation.cancel();
    final battle = _controlledBattle;
    if (battle != null && identical(game.battle, battle)) {
      battle.auto = _previousAuto;
    }
    _controlledBattle = null;
    _travelPending = false;
    if (message != null) game.notice = message;
  }

  void _confirm() {
    game.key(GameKey.confirm, automatic: true);
    game.key(GameKey.confirm, down: false, automatic: true);
  }

  void _go(GameGoal goal) {
    if (game.navigation.active != null ||
        game.navigation.planning ||
        game.route.isNotEmpty) {
      return;
    }
    if (_travelPending) {
      stop('刷钱路线暂不可达：${goal.label}；请检查道路或剧情条件');
      return;
    }
    _travelPending = true;
    unawaited(game.navigation.startGoal(goal));
  }

  void tick() {
    if (!active) return;
    if (game.screen != 'play' ||
        game.ended ||
        game.error.isNotEmpty ||
        game.flags.contains(221)) {
      stop('刷钱停止：当前剧情或游戏状态已变化');
      return;
    }
    final progress =
        '$phase/${game.cursor?.script.id}/${game.cursor?.pointer}/'
        '${game.player?.x},${game.player?.y}/${game.operation?.start}/'
        '${game.battle?.phase},${game.battle?.round}/${game.inventory["6:12"]}/${game.money}';
    if (progress != _progress || game.navigation.planning) {
      _progress = progress;
      _idle = 0;
    } else if (++_idle > 1500) {
      stop('刷钱停止：路线或战斗长时间未推进，请手动检查');
      return;
    }
    final op = game.operation;
    if (op != null) {
      if (op.kind == 'choice' && op.scriptId == '7:1' && op.address == 683) {
        final index = op.options.indexOf('奉还');
        if (index < 0) {
          stop('刷钱停止：没有归还钱袋选项');
          return;
        }
        game.choose(index, expected: op);
      } else if (const {'dialogue', 'message', 'timed'}.contains(op.kind)) {
        _confirm();
      } else if (op.kind == 'choice' || op.kind == 'menu') {
        stop('刷钱暂停：遇到其他剧情选择，请手动处理');
      }
      return;
    }
    final battle = game.battle;
    if (battle != null) {
      if (!identical(_controlledBattle, battle)) {
        _controlledBattle = battle;
        _previousAuto = battle.auto;
      }
      if (battle.phase == 'loss') {
        stop('刷钱停止：战斗失败');
        return;
      }
      battle.auto = true;
      if (battle.phase == 'win') _confirm();
      return;
    }
    _controlledBattle = null;
    if (game.menus.isNotEmpty) {
      final menu = game.menus.last;
      if (phase != 'sell' || game.cursor?.script.id != '7:5') {
        stop('刷钱已停止：遇到其他菜单');
        return;
      }
      if (menu.kind == 'inventory' && menu.mode == 'sell') {
        final index = menu.ids.indexOf('6:12');
        if (index < 0) {
          stop('没有可出售的富贵珠');
          return;
        }
        game.selectMenu(menu, index, expectedId: '6:12');
      } else if (menu.kind == 'sell-quantity' && menu.purchase?.id == '6:12') {
        final count = game.inventory['6:12'] ?? 0;
        if ((menu.purchase?.limit ?? 0) < count) {
          stop('金钱已达上限，停止刷钱');
          return;
        }
        game.changePurchaseQuantity(menu, count);
        game.selectMenu(menu, 0);
        if ((game.inventory['6:12'] ?? 0) == 0) {
          rounds++;
          phase = 'fight';
          _travelPending = false;
          game.navigation.cancel();
          // 成交后只退出本循环打开的出售列表，按原当铺出口返回客栈。
          if (game.menus.lastOrNull?.kind == 'inventory' &&
              game.menus.lastOrNull?.mode == 'sell') {
            game.menus.removeLast();
          }
          game.notice = '刷钱第$rounds轮完成，继续前往建业客栈；再次点击取消';
        }
      } else {
        stop('刷钱已停止：交易界面发生变化');
      }
      return;
    }
    if (game.cursor?.running == true) return;
    if ((game.inventory['6:12'] ?? 0) > 0 && phase != 'sell') {
      phase = 'sell';
      _travelPending = false;
      game.navigation.cancel();
    }
    final id = game.cursor?.script.id;
    if (phase == 'sell') {
      _go(const GameGoal('当铺出售富贵珠', '7:5', 42));
    } else if (!game.flags.contains(1117)) {
      _go(const GameGoal('建业钱袋：归还后去客栈', '7:1', 21));
      if (game.flags.contains(1117)) {
        _travelPending = false;
        game.navigation.cancel();
      }
    } else {
      // 钱袋剧情完成会停在城内；切换目标时丢弃已经完成的入场目标。
      if (game.navigation.active?.scriptId == '7:1' ||
          _travelPending && id == '7:1' && game.navigation.active == null) {
        _travelPending = false;
        game.navigation.cancel();
      }
      _go(const GameGoal('建业客栈：挑战三人取得富贵珠', '7:2', 0));
    }
  }
}

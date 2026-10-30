part of 'game_engine.dart';

/// 作弊入口只驱动原钱袋、客栈战斗和当铺交易，不生成奖励、不改剧情旗标。
/// 每批凑齐20个富贵珠才出售；中断时保留已取得物品和真实战斗进度。
final class GameMoneyFarm {
  GameMoneyFarm(this.game);
  static const batchSize = 20;
  final GameEngine game;
  bool active = false;
  int rounds = 0, batches = 0;
  String phase = '';
  int _idle = 0, _lastPearls = 0;
  String _progress = '';
  bool _travelPending = false;
  GameBattle? _controlledBattle;
  bool _previousAuto = false;
  int get pearls => game.inventory['6:12'] ?? 0;

  void toggle() {
    if (active) {
      stop('已停止刷钱，当前进度和已获得物品保留');
      return;
    }
    if (game.screen != 'play' || game.player == null || game.error.isNotEmpty) {
      game.notice = '进入游戏后才能一键刷钱';
      return;
    }
    if (game.flags.contains(1118) && !game.flags.contains(1117)) {
      game.notice = '钱袋选择了留下，无法进入归还钱袋后的客栈刷钱分支';
      return;
    }
    // 钱袋的最后一段对白可能仍在播放。仅允许接管这条已确定的归还流程。
    final wallet =
        game.cursor?.script.id == '7:1' &&
        (game.operation == null ||
            const {
              'dialogue',
              'message',
              'timed',
              'choice',
            }.contains(game.operation?.kind));
    if (game.battle != null ||
        game.menus.isNotEmpty ||
        (!wallet && (game.operation != null || game.cursor?.running == true))) {
      game.notice = '先完成当前对话、菜单或战斗，再开始刷钱';
      return;
    }
    game.navigation.cancel();
    active = true;
    rounds = 0;
    batches = 0;
    _lastPearls = pearls;
    phase = pearls >= batchSize
        ? 'sell'
        : game.cursor?.script.id == '7:2'
        ? 'leave'
        : 'fight';
    _idle = 0;
    _progress = '';
    _travelPending = false;
    game.notice = '刷钱已开始：每批收集20个富贵珠，再去当铺一次出售；再次点击取消';
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

  void _setPhase(String next) {
    if (phase == next) return;
    phase = next;
    _travelPending = false;
    game.navigation.cancel();
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
    if (game.screen != 'play' || game.ended || game.error.isNotEmpty) {
      stop('刷钱停止：当前游戏状态已变化');
      return;
    }
    final id = game.cursor?.script.id;
    if (id == '7:2' && pearls > _lastPearls) {
      rounds += pearls - _lastPearls;
      _lastPearls = pearls;
      _setPhase(pearls >= batchSize ? 'sell' : 'leave');
      game.notice =
          '本批富贵珠 ${math.min(pearls, batchSize)}/$batchSize，已完成$rounds场；再次点击取消';
    }
    if (phase == 'leave' && id != '7:2') _setPhase('fight');
    final progress =
        '$phase/$id/${game.cursor?.pointer}/${game.player?.x},${game.player?.y}/'
        '${game.operation?.start}/${game.battle?.phase},${game.battle?.round}/$pearls/${game.money}';
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
      if (phase != 'sell' || id != '7:5') {
        stop('刷钱已停止：遇到其他菜单');
        return;
      }
      if (menu.kind == 'inventory' && menu.mode == 'sell') {
        final index = menu.ids.indexOf('6:12');
        if (index < 0 || pearls < batchSize) {
          stop('没有凑齐20个可出售的富贵珠');
          return;
        }
        game.selectMenu(menu, index, expectedId: '6:12');
      } else if (menu.kind == 'sell-quantity' && menu.purchase?.id == '6:12') {
        if ((menu.purchase?.limit ?? 0) < batchSize) {
          stop('金钱已达上限，停止刷钱');
          return;
        }
        final before = pearls;
        // 数量入口接收增量；从当前数量调整到20，不能把20当成增量而出售21个。
        game.changePurchaseQuantity(
          menu,
          batchSize - (menu.purchase?.quantity ?? 0),
        );
        game.selectMenu(menu, 0);
        if (pearls == before - batchSize) {
          batches++;
          _travelPending = false;
          game.navigation.cancel();
          _lastPearls = pearls;
          _setPhase(pearls >= batchSize ? 'sell' : 'fight');
          if (game.menus.lastOrNull?.kind == 'inventory' &&
              game.menus.lastOrNull?.mode == 'sell') {
            game.menus.removeLast();
          }
          game.notice = '已集中出售20个富贵珠，完成$batches批；继续收集下一批，再次点击取消';
        }
      } else {
        stop('刷钱已停止：交易界面发生变化');
      }
      return;
    }
    // 一键直达的钱袋支线可在主线221之后完成。作弊循环只略过原客栈入口的
    // 关闭检查，随后仍执行114起的原三人战斗、奖励和离场脚本，不删改221。
    final cursor = game.cursor;
    if (phase == 'fight' &&
        id == '7:2' &&
        game.flags.contains(1117) &&
        game.flags.contains(221) &&
        cursor?.running == true &&
        cursor!.script.commands.elementAtOrNull(cursor.pointer)?.address ==
            103) {
      game.jump(114);
    }
    if (cursor?.running == true) return;
    if (phase == 'sell') {
      _go(const GameGoal('当铺集中出售20个富贵珠', '7:5', 42));
    } else if (phase == 'leave') {
      _go(const GameGoal('离开客栈后再次挑战', '7:2', 40));
    } else if (!game.flags.contains(1117)) {
      _go(const GameGoal('建业钱袋：归还后去客栈', '7:1', 21));
    } else {
      if (game.navigation.active?.scriptId == '7:1' ||
          _travelPending && id == '7:1' && game.navigation.active == null) {
        _travelPending = false;
        game.navigation.cancel();
      }
      _go(const GameGoal('建业客栈：挑战三人取得富贵珠', '7:2', 0));
    }
  }
}

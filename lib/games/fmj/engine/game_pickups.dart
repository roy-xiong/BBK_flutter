part of 'game_engine.dart';

/// 从原脚本扫描出的拾取事件，不保存人物、画布、平台资源或可执行回调。
/// 同一个宝箱可有多个剧情/来路分支，奖励是否可领由当前状态逐次解释。
final class GamePickupPoint {
  const GamePickupPoint(
    this.scriptId,
    this.event,
    this.types,
    this.items,
    this.money,
    this.addresses,
  );
  final String scriptId;
  final int event;
  final Set<int> types;
  final List<String> items;
  final int money;
  final Set<int> addresses;
  String get key => '$scriptId/$event';
  String get kind => types.contains(9)
      ? '宝箱'
      : types.contains(18)
      ? '隐藏拾取点'
      : event > 40
      ? '地面拾取点'
      : '场景宝物';
}

/// 某个拾取事件在当前旗标、变量和库存下实际可得到的奖励。
/// 该对象可以通过SendPort传递；后台预测不会提前领取或消耗真实物品。
final class GamePickupTask {
  const GamePickupTask(this.point, this.items, this.money, this.confirmation);
  final GamePickupPoint point;
  final List<String> items;
  final int money;
  final bool confirmation;
}

/// 宝箱和隐藏物品的扫描、条件预览与取消记录。
/// 不推断“背包里没有就是没领过”；出售、使用后的旧档仍按原领取旗标判定。
final class GamePickups {
  GamePickups(this.game);
  final GameEngine game;
  final Set<String> deferred = {};
  GamePickupTask? pending;
  late final List<GamePickupPoint> points = _scan();
  late final Map<String, List<GamePickupPoint>> _byScript = {
    for (final id in game.data.scripts.keys)
      id: points.where((p) => p.scriptId == id).toList(growable: false),
  };

  /// 只允许没有战斗、交易、切图、属性改写的物品事件成为自动拾取候选。
  /// 对话仅用于井中发现物品等说明；选择和物品消耗仍在真实执行阶段交给玩家。
  static const _safe = {3, 9, 10, 11, 13, 21, 26, 27, 31, 33, 34, 41, 47, 57};

  /// 沿用完整剧情的钥匙预留规则，先为三张任务卡留钥匙，再推荐可选锁箱。
  static int reservedKeys(Set<int> flags) =>
      const [(1077, 2330), (1095, 2332), (1099, 2333)]
          .where((card) => !flags.contains(card.$1) && !flags.contains(card.$2))
          .length;

  List<GamePickupPoint> _scan() {
    final result = <GamePickupPoint>[];
    for (final script in game.data.scripts.values) {
      final objects = <int, Set<int>>{};
      for (final command in script.commands.where((c) => c.opcode == 32)) {
        (objects[command.arg(0)] ??= {}).add(command.arg(1));
      }
      for (var event = 1; event <= script.events.length; event++) {
        if (event <= 40 && !objects.containsKey(event)) continue;
        final first = script.addresses[script.events[event - 1]];
        if (first == null) continue;
        final queue = <int>[first], seen = <int>{}, items = <String>[];
        final addresses = <int>{};
        var money = 0, safe = true;
        while (queue.isNotEmpty && seen.length < 400) {
          final at = queue.removeLast();
          if (at < 0 || at >= script.commands.length || !seen.add(at)) continue;
          final c = script.commands[at];
          if (!_safe.contains(c.opcode)) {
            safe = false;
            break;
          }
          if (c.opcode == 34) {
            items.add('${c.arg(0)}:${c.arg(1)}');
            addresses.add(c.address);
          } else if (c.opcode == 41) {
            money += c.arg(0) + (c.arg(1) << 16);
            addresses.add(c.address);
          }
          if (c.opcode == 9) continue;
          void branch(int address) {
            final p = script.addresses[address];
            if (p != null) queue.add(p);
          }

          if (c.opcode == 10) {
            branch(c.arg(0));
            continue;
          }
          if (c.opcode == 11) branch(c.arg(1));
          if (c.opcode == 21) branch(c.arg(2));
          if (c.opcode == 31) branch(c.arg(0));
          if (c.opcode == 57) branch(c.arg(2));
          queue.add(at + 1);
        }
        if (safe && queue.isEmpty && (items.isNotEmpty || money > 0)) {
          result.add(
            GamePickupPoint(
              script.id,
              event,
              Set.unmodifiable(objects[event] ?? {}),
              List.unmodifiable(items),
              money,
              Set.unmodifiable(addresses),
            ),
          );
        }
      }
    }
    return List.unmodifiable(result);
  }

  /// 在副本上精确走当前分支；零成本事件才自动领取，锁箱只预测“使用钥匙”分支。
  /// 原旗标和变量决定宝箱是否出现、是否已领以及本次来路奖励；不覆盖剧情限制。
  GamePickupTask? _preview(_NavState state, GamePickupPoint point) {
    if (deferred.contains(point.key)) return null;
    final pauseFlag = _deferredSideGoals[(point.scriptId, point.event)];
    if (pauseFlag != null && state.flags.contains(pauseFlag)) return null;
    if (point.event <= 40 && !state.npcs.containsKey(point.event)) return null;
    final script = game.data.scripts[point.scriptId];
    if (script == null) return null;
    var at = script.addresses[script.events[point.event - 1]];
    final flags = Set<int>.of(state.flags);
    final inventory = Map<String, int>.of(game.inventory), items = <String>[];
    final seen = <int>{};
    var money = 0, confirmation = false;
    for (var budget = 0; budget < 400; budget++) {
      if (at == null ||
          at < 0 ||
          at >= script.commands.length ||
          !seen.add(at)) {
        return null;
      }
      final c = script.commands[at];
      if (!_safe.contains(c.opcode)) return null;
      int? jump;
      switch (c.opcode) {
        case 9:
          return items.isEmpty && money == 0
              ? null
              : GamePickupTask(
                  point,
                  List.unmodifiable(items),
                  money,
                  confirmation,
                );
        case 10:
          jump = c.arg(0);
        case 11:
          if (flags.contains(c.arg(0))) jump = c.arg(1);
        case 21:
          if (state.variables[c.arg(0)] == c.arg(1)) jump = c.arg(2);
        case 26:
          flags.add(c.arg(0));
        case 27:
          flags.remove(c.arg(0));
        case 31:
          final options = c.text;
          if (options is! List ||
              options.length != 2 ||
              options.first != '取消' ||
              !'${options.last}'.startsWith('使用')) {
            return null;
          }
          confirmation = true;
          if ((point.scriptId == '10:1' || point.scriptId == '2:33') &&
              (inventory['14:2'] ?? 0) <= reservedKeys(flags)) {
            return null;
          }
          jump = c.arg(0);
        case 57:
          // 只预测万能钥匙锁箱，不自动带入其他交物或交换分支。
          final id = '${c.arg(0)}:${c.arg(1)}';
          if (!confirmation || id != '14:2' || (inventory[id] ?? 0) <= 0) {
            return null;
          }
          inventory[id] = inventory[id]! - 1;
        case 34:
          items.add('${c.arg(0)}:${c.arg(1)}');
        case 41:
          money += c.arg(0) + (c.arg(1) << 16);
      }
      at = jump == null ? at + 1 : script.addresses[jump];
    }
    return null;
  }

  String label(GamePickupTask task) => [
    ...task.items.map(game.goodsName),
    if (task.money > 0) '${task.money}金钱',
  ].join('、');

  void onChoice(GameOperation operation, int index) {
    final task = pending;
    if (task == null ||
        !task.confirmation ||
        task.point.scriptId != operation.scriptId) {
      return;
    }
    if (index == 0) deferred.add(task.point.key);
    pending = null;
  }

  /// 一次新的开启表示愿意重新考虑此前取消的锁箱；只清拾取分支的暂缓状态。
  void retryDeferred() {
    deferred.clear();
    for (final point in points) {
      final flag = _deferredSideGoals[(point.scriptId, point.event)];
      if (flag != null) game.flags.remove(flag);
    }
  }
}

extension _PickupNavigation on GameNavigation {
  /// 在后台按实际可通行的地图连接搜索拾取点，先清本图再探索可用支路。
  /// 遇到对白封路、战斗、钥匙消耗等剧情边界不做假设，也不改原剧情旗标。
  Future<_NavLeg?> _pickupRoute(
    _NavState initial,
    GameGoal goal,
    int request,
  ) async {
    final queue = <_NavNode>[_NavNode(initial, null, 0)],
        seen = <String>{},
        scheduled = <String>{initial.key};
    for (var budget = 0; queue.isNotEmpty && budget < 256; budget++) {
      if (budget % 4 == 0) {
        await Future<void>.delayed(Duration.zero);
        if (request != generation) return null;
      }
      queue.sort((a, b) => a.cost.compareTo(b.cost));
      final node = queue.removeAt(0), state = node.state;
      if (!seen.add(state.key)) continue;
      final flood = _flood(state), script = game.data.scripts[state.scriptId];
      if (flood == null || script == null) continue;
      _NavLeg? nearest;
      var distance = 2147483647;
      for (final point
          in game.pickups._byScript[state.scriptId] ?? <GamePickupPoint>[]) {
        final task = game.pickups._preview(state, point);
        if (task == null) continue;
        final near = _pickupApproach(state, flood, point.event);
        if (near == null) continue;
        final cost =
            flood.distances[near.anchorY * flood.map.width + near.anchorX];
        if (cost < distance) {
          distance = cost;
          nearest = _NavLeg(
            near.anchorX,
            near.anchorY,
            near.x,
            near.y,
            near.event,
            boundary: near.boundary,
            pickup: task,
          );
        }
      }
      if (nearest != null) {
        // 支路探索必须保留回到当前剧情目标的路线。后期愚人居的返回口、
        // 迷阵的来路旗标会改变连通性，不能因另一地区还有宝箱就擅自离开。
        if (node.first == null || await _route(state, goal, request) != null) {
          return node.first ?? nearest;
        }
        continue;
      }
      final exits = Map<int, _NavLeg>.of(flood.exits);
      for (final id in state.npcs.keys.where(_transfers(script).contains)) {
        final near = _approach(state, flood, id);
        if (near != null) exits[id] = near;
      }
      for (final exit in exits.values) {
        final input = state.copy()
          ..x = exit.anchorX
          ..y = exit.anchorY;
        final outcome = _simulate(input, exit.event);
        if (!outcome.stable ||
            outcome.state.key == input.key ||
            !scheduled.add(outcome.state.key)) {
          continue;
        }
        final cost =
            node.cost +
            1 +
            math.max(
              0,
              flood.distances[exit.anchorY * flood.map.width + exit.anchorX],
            );
        queue.add(_NavNode(outcome.state, node.first ?? exit, cost.toInt()));
      }
    }
    return null;
  }

  /// 百草地钨龙剑的唯一相邻格同时是出口：见师父前踩上去只有提示对白，
  /// 见师父后却会真正离图。只能在只读解释证明“本次仅对白、状态不变”时
  /// 分段走入该格，真实提示结束后再面向隐藏点领取，不能把出口一律当路走。
  _NavLeg? _pickupApproach(_NavState state, _NavFlood flood, int event) {
    final direct = _approach(state, flood, event);
    if (direct != null) return direct;
    final open = _flood(state, allowEvents: true);
    if (open == null) return null;
    final target = _approach(state, open, event);
    if (target == null) return null;
    final path = <int>[];
    var at = target.anchorY * open.map.width + target.anchorX;
    while (at >= 0) {
      path.add(at);
      at = open.parents[at];
    }
    for (final cell in path.reversed) {
      if (flood.distances[cell] >= 0) continue;
      final x = cell % open.map.width, y = cell ~/ open.map.width;
      final boundaryEvent = open.map.event(x, y) + 40;
      if (boundaryEvent <= 40) return null;
      final near = _approach(state, flood, boundaryEvent);
      if (near == null) return null;
      final input = state.copy()
        ..x = near.anchorX
        ..y = near.anchorY;
      final outcome = _simulate(input, boundaryEvent, preview: true);
      if (!outcome.stable || outcome.state.key != input.key) return null;
      return _NavLeg(
        near.anchorX,
        near.anchorY,
        near.x,
        near.y,
        near.event,
        boundary: true,
      );
    }
    return null;
  }
}

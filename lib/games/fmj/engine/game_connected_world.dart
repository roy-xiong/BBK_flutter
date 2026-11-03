part of 'game_engine.dart';

/// 连续画面的整数格裁剪区域；仅控制绘制，不能作为碰撞或通路依据。
final class ConnectedRegion {
  ConnectedRegion(
    this.left,
    this.top,
    this.right,
    this.bottom, {
    this.cells = const {},
  });
  final int left, top, right, bottom;

  /// 原版不规则入口两侧可能仍有合法地形，使用离散格补齐，不能扩成整个矩形
  /// 覆盖另一条路。contains、点击归属、镜头边界和Painter共用同一组格子。
  final Set<(int, int)> cells;
  late final (int, int, int, int) bounds = _bounds();
  (int, int, int, int) _bounds() {
    var l = left, t = top, r = right, b = bottom;
    for (final point in cells) {
      l = math.min(l, point.$1);
      t = math.min(t, point.$2);
      r = math.max(r, point.$1 + 1);
      b = math.max(b, point.$2 + 1);
    }
    return (l, t, r, b);
  }

  bool contains(int x, int y) =>
      x >= left && y >= top && x < right && y < bottom ||
      cells.contains((x, y));

  ConnectedRegion covering(GameMap map, int ox, int oy) {
    final extra = <(int, int)>{...cells};
    for (var y = 3; y < map.height - 2; y++) {
      for (var x = 4; x < map.width - 4; x++) {
        if (map.canWalk(x, y, player: true) &&
            map.event(x, y) == 0 &&
            !contains(ox + x, oy + y)) {
          extra.add((ox + x, oy + y));
        }
      }
    }
    return extra.isEmpty
        ? this
        : ConnectedRegion(
            left,
            top,
            right,
            bottom,
            cells: Set.unmodifiable(extra),
          );
  }

  ConnectedRegion cut(int direction, int x, int y, {required bool source}) {
    return switch ((direction, source)) {
      (1, true) || (3, false) => ConnectedRegion(
        left,
        math.max(top, y + (direction == 1 ? 1 : 0)),
        right,
        bottom,
      ),
      (3, true) || (1, false) => ConnectedRegion(
        left,
        top,
        right,
        math.min(bottom, y + (direction == 1 ? 1 : 0)),
      ),
      (4, true) || (2, false) => ConnectedRegion(
        math.max(left, x + (direction == 4 ? 1 : 0)),
        top,
        right,
        bottom,
      ),
      _ => ConnectedRegion(
        left,
        top,
        math.min(right, x + (direction == 4 ? 1 : 0)),
        bottom,
      ),
    };
  }
}

/// 同一个地图编号可有多个道路实例。脚本、旗标、变量、来路及世界偏移共同
/// 区分实例，不能把同一桥梁贴图的不同地理位置合并成一条捷径。
final class ConnectedMap {
  ConnectedMap._(this.id, this.map, this._state, this.x, this.y, {this.entry})
    : region = entry ?? ConnectedRegion(x, y, x + map.width, y + map.height);
  final int id, x, y;
  final GameMap map;
  _NavState _state;
  Map<int, GameActor> _actors = {};
  final ConnectedRegion? entry;
  ConnectedRegion region;
  String get routeKey => GameConnectedWorld._key(_state);
}

final class ConnectedExit {
  const ConnectedExit._(
    this.source,
    this.target,
    this.anchorX,
    this.anchorY,
    this.x,
    this.y,
    this.direction,
    this.event,
    this._expected,
  );
  final ConnectedMap source, target;
  final int anchorX, anchorY, x, y, direction, event;
  final _NavState _expected;
}

/// 镜头由实际已解析的相邻路段约束；边缘停止跟随，不强制人物永远居中。
final class ConnectedView {
  const ConnectedView(
    this.left,
    this.top,
    this.columns,
    this.rows,
    this.tileSize,
  );
  final int left, top, columns, rows;
  final double tileSize;
}

/// 原版多格出口汇入固定落点时的显示足迹，不改变碰撞或剧情坐标。
final class _ConnectedFootstep {
  _ConnectedFootstep(
    this.x,
    this.y,
    this.direction,
    this.step, {
    this.dx = 0,
    this.dy = 0,
    this.started = 0,
  });
  final int x, y, direction, step;
  final double dx, dy;
  int started;
}

/// 会话内的道路显示拓扑。只读解释原出口；实际行走仍触发GameEngine.move。
/// 不写入原地图、旗标、碰撞、物品或存档，也不创建计时器、isolate或GPU资源。
final class GameConnectedWorld {
  GameConnectedWorld(this.game);
  final GameEngine game;
  static const _roads = {
    '1:3',
    '1:4',
    '1:5',
    '1:8',
    '1:9',
    '1:10',
    '1:11',
    '1:12',
    '1:13',
    '1:14',
    '1:15',
    '1:16',
    '1:17',
    '1:18',
    '1:19',
    '1:20',
    '1:21',
    '1:22',
    '1:25',
    '1:26',
    '1:27',
    '1:28',
    '1:29',
    '1:30',
    '1:34',
    '1:38',
    '1:45',
  };
  static const safeOpcodes = {
    0,
    1,
    3,
    9,
    10,
    11,
    12,
    14,
    16,
    21,
    22,
    23,
    26,
    27,
    32,
    33,
    35,
    37,
    38,
    46,
    52,
    54,
    55,
    67,
    76,
  };
  ConnectedMap? current;
  final List<ConnectedMap> _history = [];
  final List<ConnectedMap> _maps = [];
  final List<ConnectedMap> _visible = [];
  final List<ConnectedExit> _exits = [];
  final List<_ConnectedFootstep> _trail = [];
  String? _planned;
  int _nextId = 0, revision = 0;
  (int, int)? _click;
  (int, int, String)? _clickIdentity;
  String? _roster;
  int _loadSeen = 0;
  (int, int, int, int, int)?
  _view; // left,top,worldPlayerX,worldPlayerY,columns
  List<ConnectedMap> get maps => List.unmodifiable(_maps);

  /// 当前段、已走路段优先。折返和非平面迷阵的远处预览不能覆盖当前道路，
  /// 点击命中与绘制使用同一顺序，避免点到视觉上被遮住的另一条支路。
  List<ConnectedMap> get visiblePriority => [
    ?current,
    ..._history.reversed.where((n) => !identical(n, current)),
    ..._visible.where((n) => !identical(n, current) && !_history.contains(n)),
  ];

  ConnectedMap? _visibleMapAt(int x, int y) =>
      visiblePriority.where((n) => n.region.contains(x, y)).firstOrNull;
  bool get active => current != null && game.preferences['modernUi'] == true;
  bool get clicking => _click != null;

  static String _key(_NavState state) {
    final flags = state.flags.toList()..sort();
    return '${state.mapId}/${state.scriptId}/${flags.join(',')}/${state.variables.join(',')}';
  }

  void reset() {
    current = null;
    _history.clear();
    _maps.clear();
    _visible.clear();
    _exits.clear();
    _trail.clear();
    _planned = null;
    _view = null;
    _click = null;
    _clickIdentity = null;
    _roster = null;
    revision++;
  }

  void cancelClick() {
    _click = null;
    _clickIdentity = null;
  }

  /// 只在当前场景进入自由行走后预取，不跨过真实对白、门锁、战斗或物品分支。
  void synchronize() {
    final map = game.map, player = game.player;
    if (game.preferences['modernUi'] != true ||
        map == null ||
        player == null ||
        game.screen != 'play' ||
        !_roads.contains(map.id)) {
      if (current != null) reset();
      return;
    }
    if (current != null &&
        (_loadSeen != game.mapLoadRevision ||
            current!.map.id != map.id ||
            current!._state.scriptId != game.cursor?.script.id)) {
      reset();
    }
    if (game.cursor?.running == true ||
        game.operation != null ||
        game.battle != null) {
      return;
    }
    final state = game.navigation._capture();
    if (current == null ||
        current!.map.id != map.id ||
        current!._state.scriptId != state.scriptId) {
      reset();
      current = ConnectedMap._(_nextId++, map, state, 0, 0);
      _loadSeen = game.mapLoadRevision;
    }
    final node = current!;
    node._state = state;
    node._actors = Map.of(game.npcs);
    recordPlayerStep();
    final portals = _portals(node);
    final signature =
        '${_key(state)}/${portals.map((p) => '${p.$1},${p.$2},${p.$3}').join(';')}';
    if (signature == _planned) return;
    _planned = signature;
    final previous = List<ConnectedMap>.of(_maps);
    _maps
      ..clear()
      ..addAll(_history)
      ..add(node);
    _exits.clear();
    node.region =
        node.entry ??
        ConnectedRegion(
          node.x,
          node.y,
          node.x + map.width,
          node.y + map.height,
        );
    final queue = Queue<(ConnectedMap, int)>()..add((node, 0));
    final expanded = <int>{};
    while (queue.isNotEmpty && _maps.length < 18) {
      final (source, depth) = queue.removeFirst();
      if (!expanded.add(source.id)) continue;
      for (final portal in _portals(source)) {
        if (_maps.length >= 18) break;
        final (x, y, direction) = portal;
        final input = source._state.copy()
          ..x = x
          ..y = y;
        final event = source.map.event(x, y) + 40;
        final outcome = game.navigation._simulate(
          input,
          event,
          allowedOpcodes: safeOpcodes,
          visualActors: source._actors,
        );
        if (!outcome.stable ||
            outcome.transfers != 1 ||
            !_roads.contains(outcome.state.mapId)) {
          continue;
        }
        final after = outcome.state;
        if (_key(after) == _key(input) &&
            after.x == input.x &&
            after.y == input.y) {
          continue;
        }
        final targetMap = game.data.maps[after.mapId];
        if (targetMap == null ||
            !targetMap.canWalk(after.x, after.y, player: true)) {
          continue;
        }
        final ox = source.x + x - after.x, oy = source.y + y - after.y;
        final worldX = source.x + x, worldY = source.y + y;
        final raw = ConnectedRegion(
          ox,
          oy,
          ox + targetMap.width,
          oy + targetMap.height,
        );
        final entry = raw.cut(direction, worldX, worldY, source: false);
        // 前沿也解析裁剪，走近后不再裁掉已经显示的半截道路。
        source.region = source.region.cut(
          direction,
          worldX,
          worldY,
          source: true,
        );
        if (depth >= 3) continue;
        var target = _maps
            .where((n) => n.x == ox && n.y == oy && n.routeKey == _key(after))
            .firstOrNull;
        if (target == null) {
          target =
              previous
                  .where(
                    (n) => n.x == ox && n.y == oy && n.routeKey == _key(after),
                  )
                  .firstOrNull ??
              ConnectedMap._(_nextId++, targetMap, after, ox, oy, entry: entry);
          target._actors = outcome.actors;
          _maps.add(target);
        }
        final (dx, dy) = GameEngine._delta(direction);
        _exits.add(
          ConnectedExit._(
            source,
            target,
            x - dx,
            y - dy,
            x,
            y,
            direction,
            event,
            after,
          ),
        );
        if (!expanded.contains(target.id)) queue.add((target, depth + 1));
      }
    }
    // 远处支路在离开视野前保留构图，换根展开不能替换眼前地形。
    // 保留图不加入_exits，行走仍只采用本次核验的原出口；缓存最多36段。
    final window = _view;
    if (window != null) {
      _visible.removeWhere(
        (n) =>
            !_maps.contains(n) &&
            (n.region.bounds.$3 < window.$1 - 2 ||
                n.region.bounds.$1 > window.$1 + window.$5 + 2 ||
                n.region.bounds.$4 < window.$2 - 2 ||
                n.region.bounds.$2 >
                    window.$2 + (window.$5 == 20 ? 12 : 6) + 2),
      );
    }
    _visible.addAll(_maps.where((n) => !_visible.contains(n)));
    for (final node in _maps) {
      node.region = node.region.covering(node.map, node.x, node.y);
    }
    while (_visible.length > 36) {
      final expired = _visible
          .where((n) => !_maps.contains(n) && !_history.contains(n))
          .firstOrNull;
      if (expired == null) break;
      _visible.remove(expired);
    }
    revision++;
  }

  /// 出口锚点固定选首格，横移不能使邻图跟着平移；真实落点仍由原事件决定。
  List<(int, int, int)> _portals(ConnectedMap node) {
    final groups = <(int, int), (int, int, int)>{};
    final map = node.map;
    for (var y = 3; y < map.height - 2; y++) {
      for (var x = 4; x < map.width - 4; x++) {
        final event = map.event(x, y);
        if (event == 0) continue;
        final directions = <int>[
          if (y == 3) 1,
          if (x == map.width - 5) 2,
          if (y == map.height - 3) 3,
          if (x == 4) 4,
        ];
        for (final direction in directions) {
          final (dx, dy) = GameEngine._delta(direction);
          if (!map.canWalk(x - dx, y - dy, player: true) ||
              map.event(x - dx, y - dy) != 0) {
            continue;
          }
          groups.putIfAbsent((event, direction), () => (x, y, direction));
        }
      }
    }
    return groups.values.toList();
  }

  ConnectedExit? prepareStep(int x, int y, int direction) {
    synchronize();
    final node = current;
    if (node == null) return null;
    return _exits
        .where(
          (e) =>
              identical(e.source, node) &&
              e.event == node.map.event(x, y) + 40 &&
              e.direction == direction,
        )
        .firstOrNull;
  }

  /// 原事件执行完后再核验，预览永远不能决定真正去哪里。
  bool finishStep(ConnectedExit edge) {
    final actual = game.navigation._capture();
    if (game.cursor?.running == true ||
        game.operation != null ||
        game.battle != null ||
        _key(actual) != _key(edge._expected) ||
        actual.x != edge._expected.x ||
        actual.y != edge._expected.y) {
      reset();
      return false;
    }
    final old = current;
    _history.removeWhere((n) => n.id == edge.target.id);
    if (old != null && !_history.contains(old)) _history.add(old);
    while (_history.length > 4) {
      _history.removeAt(0);
    }
    current = edge.target;
    _loadSeen = game.mapLoadRevision;
    current!._state = actual;
    if (_trail.isNotEmpty) {
      final arrived = _trail.first;
      final wx = current!.x + actual.x, wy = current!.y + actual.y;
      _trail[0] = _ConnectedFootstep(
        wx,
        wy,
        arrived.direction,
        arrived.step,
        dx: (arrived.x - wx).toDouble(),
        dy: (arrived.y - wy).toDouble(),
        started: game.ticks,
      );
      // 多通道汇入时镜头保持静止，由显示足迹短暂滑向原版真实落点。
      final v = _view;
      if (v != null) _view = (v.$1, v.$2, wx, wy, v.$5);
    }
    _planned = null;
    synchronize();
    return true;
  }

  /// 足迹使用连续世界格子，过图时伙伴可仍在上一段桥上，不瞬移到新图排队。
  void recordPlayerStep() {
    final node = current, p = game.player;
    if (node == null || p == null || game.map?.id != node.map.id) return;
    final roster = game.players.map((a) => a.index).join(',');
    if (_roster != roster) {
      _roster = roster;
      _trail.clear();
    }
    final point = _ConnectedFootstep(
      node.x + p.x,
      node.y + p.y,
      p.direction,
      p.step,
    );
    if (_trail.isNotEmpty &&
        _trail.first.x == point.x &&
        _trail.first.y == point.y) {
      return;
    }
    if (_trail.isNotEmpty &&
        (_trail.first.x - point.x).abs() + (_trail.first.y - point.y).abs() >
            1) {
      _trail.clear();
    }
    if (_trail.isEmpty) {
      for (final pose in game.partyFollow.followers.toList().reversed) {
        _trail.insert(
          0,
          _ConnectedFootstep(
            node.x + pose.x,
            node.y + pose.y,
            pose.direction,
            pose.step,
          ),
        );
      }
    }
    for (final step in _trail) {
      step.started = game.ticks;
    }
    _trail.insert(0, point);
    if (_trail.length > game.players.length) {
      _trail.removeRange(game.players.length, _trail.length);
    }
  }

  List<PartyMapPose> get actors {
    final node = current, p = game.player;
    if (node == null || p == null) return const [];
    final seen = <(int, int, int, int)>{};
    final poses = <PartyMapPose>[
      for (final instance in visiblePriority)
        for (final npc in instance._actors.values)
          if ((identical(instance, current) ||
                  instance.region.contains(
                    instance.x + npc.x,
                    instance.y + npc.y,
                  ) ||
                  instance.region.contains(
                    instance.x + npc.x + 1,
                    instance.y + npc.y,
                  ) ||
                  instance.region.contains(
                    instance.x + npc.x,
                    instance.y + npc.y + 1,
                  )) &&
              seen.add((
                instance.x + npc.x,
                instance.y + npc.y,
                npc.type,
                npc.index,
              )))
            PartyMapPose(
              npc,
              instance.x + npc.x,
              instance.y + npc.y,
              npc.direction,
              npc.step,
            ),
      for (var i = 1; i < math.min(_trail.length, game.players.length); i++)
        if (!game.partyFollow._hasStoryActor(game.players[i]))
          PartyMapPose(
            game.players[i],
            _trail[i].x,
            _trail[i].y,
            _trail[i].direction,
            _trail[i].step,
            order: -i,
          ),
      PartyMapPose(
        p,
        node.x + p.x,
        node.y + p.y,
        p.direction,
        p.step,
        order: 1,
      ),
    ];
    poses.sort(
      (a, b) => a.y != b.y ? a.y.compareTo(b.y) : a.order.compareTo(b.order),
    );
    return poses;
  }

  /// 多通道汇入只调整显示，三次40ms游戏步内完成，倍速沿用游戏时钟。
  (double, double) actorOffset(GameActor actor) {
    final i = game.players.indexOf(actor);
    if (i < 0 || i >= _trail.length) return (0, 0);
    final step = _trail[i];
    final left = (1 - (game.ticks - step.started) / 3).clamp(0.0, 1.0);
    return (step.dx * left, step.dy * left);
  }

  bool get animating => _trail.any(
    (s) => (s.dx != 0 || s.dy != 0) && game.ticks - s.started <= 3,
  );

  ConnectedView? view(bool wide) {
    final node = current, p = game.player;
    if (node == null || p == null || _maps.isEmpty) return null;
    final columns = wide ? 20 : 10, rows = wide ? 12 : 6;
    final left = _maps.map((n) => n.region.bounds.$1).reduce(math.min);
    final top = _maps.map((n) => n.region.bounds.$2).reduce(math.min);
    final right = _maps.map((n) => n.region.bounds.$3).reduce(math.max);
    final bottom = _maps.map((n) => n.region.bounds.$4).reduce(math.max);
    final px = node.x + p.x, py = node.y + p.y;
    var x = (px - columns ~/ 2)
        .clamp(left, math.max(left, right - columns))
        .toInt();
    var y = (py - rows ~/ 2).clamp(top, math.max(top, bottom - rows)).toInt();
    final previous = _view;
    if (previous != null && previous.$5 == columns) {
      final dx = (px - previous.$3).abs(), dy = (py - previous.$4).abs();
      x = x.clamp(previous.$1 - dx, previous.$1 + dx).toInt();
      y = y.clamp(previous.$2 - dy, previous.$2 + dy).toInt();
    }
    _view = (x, y, px, py, columns);
    return ConnectedView(x, y, columns, rows, wide ? 32 : 64);
  }

  /// 邻图点击只接受当前已验证的连接，按原出口逐段走，不能直接改坐标传送。
  bool walkToWorld(int x, int y) {
    synchronize();
    if (current == null) return false;
    final target = _visibleMapAt(x, y);
    if (target != null &&
        !target.map.canWalk(x - target.x, y - target.y, player: true)) {
      _click = null;
      return game.walkTo(x - current!.x, y - current!.y, nearest: true);
    }
    if (target == null) {
      _click = null;
      return game.walkTo(x - current!.x, y - current!.y, nearest: true);
    }
    _click = (x, y);
    _clickIdentity = (target.x, target.y, target.routeKey);
    tick();
    return _click != null ||
        game.route.isNotEmpty ||
        game.player!.x == x - current!.x && game.player!.y == y - current!.y;
  }

  void tick() {
    if (animating) revision++;
    final click = _click, node = current, p = game.player;
    if (click == null ||
        node == null ||
        p == null ||
        game.screen != 'play' ||
        game.cursor?.running == true ||
        game.operation != null ||
        game.battle != null ||
        game.menus.isNotEmpty ||
        game.route.isNotEmpty) {
      return;
    }
    final target = _visibleMapAt(click.$1, click.$2);
    if (target == null ||
        _clickIdentity != (target.x, target.y, target.routeKey)) {
      cancelClick();
      return;
    }
    if (identical(target, node)) {
      _click = null;
      game.walkTo(click.$1 - node.x, click.$2 - node.y, nearest: true);
      return;
    }
    final queue = Queue<(ConnectedMap, ConnectedExit?)>()..add((node, null));
    final seen = <int>{};
    ConnectedExit? leg;
    while (queue.isNotEmpty) {
      final (here, first) = queue.removeFirst();
      if (!seen.add(here.id)) continue;
      if (identical(here, target)) {
        leg = first;
        break;
      }
      for (final edge in _exits.where((e) => identical(e.source, here))) {
        queue.add((edge.target, first ?? edge));
      }
    }
    if (leg == null) {
      _click = null;
      return;
    }
    if (p.x == leg.anchorX && p.y == leg.anchorY) {
      game.key(
        [GameKey.up, GameKey.right, GameKey.down, GameKey.left][leg.direction -
            1],
        automatic: true,
      );
    } else if (!game.walkTo(leg.anchorX, leg.anchorY)) {
      _click = null;
    }
  }
}

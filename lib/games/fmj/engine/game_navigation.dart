part of 'game_engine.dart';

/// 修复旧导航把玩家误送出愚人居后的入口封闭。只为未完成的卡片支线开放
/// 返回，所有人物对白、交还卡片、奖励和原入口坐标仍走正常脚本。
bool _allowYurenReturn(
  GameScript script,
  GameCommand command,
  Set<int> flags,
) =>
    script.id == '2:50' &&
    command.address == 224 &&
    command.opcode == 11 &&
    command.arg(0) == 254 &&
    flags.contains(254) &&
    ((flags.contains(2008) && !flags.contains(2301) && !flags.contains(263)) ||
        (flags.contains(2010) && !flags.contains(2302)) ||
        (flags.contains(2009) &&
            !flags.contains(2303) &&
            !flags.contains(261)));

final class GameGoal {
  const GameGoal(
    this.label,
    this.scriptId,
    this.event, {
    this.hint = '到达后与人物或机关正常交互。',
    this.done = false,
    this.ready = true,
    this.continuation,
  });
  final String label, scriptId, hint;
  final int event;
  final bool done, ready;

  /// 到达入口只完成一段路线；玩家处理开门选择后继续前往房内的真实目标。
  final GameGoal? continuation;
}

/// 后台规划禁止持有 UI 排版器。路由解释不会绘制文字，此实现只用于类型隔离。
final class _NavigationTextLayout implements SystemTextLayout {
  const _NavigationTextLayout();
  @override
  TextPage fit(String text, int start, int width, int height) =>
      TextPage('', start);
}

final class _NavigationRequest {
  const _NavigationRequest(
    this.maps,
    this.scripts,
    this.inventory,
    this.state,
    this.goal,
    this.reply,
  );
  final Map<String, GameMap> maps;
  final Map<String, GameScript> scripts;
  final Map<String, int> inventory;
  final _NavState state;
  final GameGoal goal;
  final SendPort reply;
}

/// 顶层入口只接收纯数据，不捕获会话、图片、回调或 Flutter 原生资源。
Future<void> _planNavigation(_NavigationRequest request) async {
  try {
    final game = GameEngine._navigation(
      GameData.navigation(request.maps, request.scripts),
    )..inventory.addAll(request.inventory);
    request.reply.send(
      await game.navigation._route(request.state, request.goal, 0),
    );
  } catch (error) {
    request.reply.send('后台寻路失败：$error');
  }
}

/// 所有完成、失败和取消路径均关闭端口；取消也会结束等待及后台计算。
final class _NavigationWorker {
  final port = ReceivePort();
  final result = Completer<_NavLeg?>();
  Isolate? isolate;
  StreamSubscription<dynamic>? subscription;
  bool closed = false;
  void close() {
    if (closed) return;
    closed = true;
    isolate?.kill(priority: Isolate.immediate);
    subscription?.cancel();
    port.close();
    if (!result.isCompleted) result.complete(null);
  }
}

/// 仅供路由解释的独立副本，不保存 GameActor 引用或可变的游戏集合。
final class _NavState {
  _NavState(
    this.mapId,
    this.scriptId,
    this.x,
    this.y,
    this.flags,
    this.variables,
    this.npcs,
    this.moving,
  );
  String mapId, scriptId;
  int x, y;
  final Set<int> flags, moving;
  final List<int> variables;
  final Map<int, (int, int)> npcs;
  _NavState copy() => _NavState(
    mapId,
    scriptId,
    x,
    y,
    Set.of(flags),
    List.of(variables),
    Map.of(npcs),
    Set.of(moving),
  );
  String get key {
    final sorted = flags.toList()..sort();
    final ids = npcs.keys.toList()..sort();
    return '$mapId/$scriptId/$x/$y/${sorted.join(',')}/${variables.join(',')}/${ids.map((id) => '$id:${npcs[id]}').join(',')}';
  }
}

final class _NavLeg {
  const _NavLeg(
    this.anchorX,
    this.anchorY,
    this.x,
    this.y,
    this.event, {
    this.destination = false,
    this.boundary = false,
    this.blockedBy,
    this.score = 0,
  });
  final int anchorX, anchorY, x, y, event;
  final bool destination, boundary;
  final int? blockedBy;
  final int score;
  _NavLeg ranked(int value) => _NavLeg(
    anchorX,
    anchorY,
    x,
    y,
    event,
    destination: destination,
    boundary: boundary,
    blockedBy: blockedBy,
    score: value,
  );
}

final class _NavNode {
  const _NavNode(this.state, this.first, this.cost);
  final _NavState state;
  final _NavLeg? first;
  final int cost;
}

final class _NavOutcome {
  const _NavOutcome(this.state, this.stable, this.visited);
  final _NavState state;
  final bool stable;

  /// 某些入场脚本立即转入战斗/过场脚本。保留经过的入口，不能只看最终脚本。
  final Set<String> visited;
}

final class _NavFlood {
  const _NavFlood(this.map, this.distances, this.parents, this.exits);
  final GameMap map;
  final List<int> distances, parents;
  final Map<int, _NavLeg> exits;
}

final class _NavBoundary {
  const _NavBoundary(this.node, this.input, this.exit, this.cost);
  final _NavNode node;
  final _NavState input;
  final _NavLeg exit;
  final int cost;
  _NavLeg get leg =>
      node.first ??
      _NavLeg(
        exit.anchorX,
        exit.anchorY,
        exit.x,
        exit.y,
        exit.event,
        boundary: true,
      );
}

/// 路由只解释副本；执行阶段使用与手动操作一致的方向键和确认事件。
///
/// 对白、选择、战斗、奖励和物品消耗都保留在真实状态机中。规划遇到对白出口时，
/// 只读预测出口后的地理连接，实际走到该入口后仍由玩家阅读、选择和战斗。
final class GameNavigation {
  GameNavigation(this.game);
  final GameEngine game;
  GameGoal? active;
  _NavLeg? _leg;
  bool planning = false;
  int generation = 0, waitTicks = 0, _blockedTicks = 0;
  final Map<String, Set<int>> _transferCache = {};
  final Map<(String, String), int> _hopCache = {};
  _NavigationWorker? _worker;
  static const barriers = {
    13,
    20,
    28,
    31,
    34,
    39,
    44,
    45,
    47,
    57,
    58,
    61,
    62,
    64,
    65,
    66,
    68,
    69,
    72,
    77,
  };

  GameGoal get mainGoal {
    final f = game.flags, script = game.cursor?.script.id ?? '';
    GameGoal goal(String label, String id, int event, [String? hint]) =>
        GameGoal(label, id, event, hint: hint ?? '沿已开放的道路前往，剧情分支由你选择。');
    if (f.contains(1)) return goal('见师父，领取任务', '2:2', 9);
    if (!f.contains(19)) {
      for (var i = 0; i < 8; i++) {
        if (!f.contains(11 + i)) {
          return goal('完成护灯试炼 ${i + 1}', '2:${19 + i}', 1);
        }
      }
      return goal('取伏魔剑', '2:18', 1);
    }
    final stages = <(int, String, String, int)>[
      (21, '把伏魔剑交给师父', '2:2', 9),
      (202, '拜访忘忧村村长', '3:9', 1),
      (203, '调查村南瘴气林', '4:1', 42),
      (204, '向猎户问路', '4:2', 1),
      (208, '向鲁斧借芦藤甲', '5:13', 1),
      (209, '进入李府，处理门卫', '5:1', 1),
      (210, '击败李虎，夺回芦藤甲', '5:15', 1),
    ];
    for (final s in stages) {
      if (!f.contains(s.$1)) return goal(s.$2, s.$3, s.$4);
    }
    if (!f.contains(215) && (!f.contains(2000) || !f.contains(2001))) {
      return goal('装备芦藤雌甲与雄甲', script, 0, '分别让小梅与清风装备对应护甲，再进入瘴气林。');
    }
    if (!f.contains(215)) return goal('到蛇窟深处除妖', '4:8', 43);
    if (!f.contains(216) && script.startsWith('4:')) {
      return goal('找到蛇窟出口，赶回忘忧村', '4:9', 42);
    }
    final middle = <(int, String, String, int)>[
      (216, '回三清宫复命', '2:2', 9),
      (217, '邀请小梅再次同行', '3:11', 1),
      (218, '建业追捕小偷，结识袁姑娘', '7:14', 0),
      (219, '赶往钟山，与袁姑娘会合', '6:13', 0),
      (220, '解救钟山道院', '8:3', 0),
      (221, '进入霸王钟洞，守护宝钟', '8:10', 0),
      (224, '向钟山师叔报告失钟', '8:2', 0),
      (225, '向建业掌柜打听袁姑娘', '7:2', 45),
      (226, '向白水镇客栈打听失童案', '9:5', 43),
    ];
    for (final s in middle) {
      if (!f.contains(s.$1)) return goal(s.$2, s.$3, s.$4);
    }
    if (!f.contains(228) && !f.contains(227)) return goal('询问老宅守卫', '9:1', 1);
    if (!f.contains(227)) return goal('说服白水镇长', '9:4', 1);
    if (!f.contains(229)) return goal('请门口镇长让守卫放行', '9:1', 3);
    if (!f.contains(230) && !f.contains(232)) {
      return goal('查看老宅主房，寻找井口声音', '9:11', 1);
    }
    if (!f.contains(232)) return goal('进入老宅井下，寻找袁姑娘', '9:13', 45);
    if (!f.contains(231)) {
      final stones = game.npcs.keys.where((n) => n >= 1 && n <= 8).toList()
        ..sort();
      return goal(
        '处理摄魂阵的石头',
        '9:13',
        script == '9:13' && stones.isNotEmpty ? stones.first : 0,
      );
    }
    final late = <(int, String, String, int)>[
      (233, '与赤血对峙', '9:13', 45),
      (234, '返回白水镇报告救人结果', '9:1', 0),
      (235, '询问南北村的预言', '10:1', 5),
      (236, '拜访周处', '10:2', 42),
      (238, '进入南山寻找白虎', '12:3', 1),
      (239, '返回南北村，查看受伤村民', '10:1', 6),
      (240, '向周处求取无忧丹', '10:2', 42),
      (241, '救治受腥风伤害的村民', '10:1', 6),
      (
        245,
        '北海追查苍龙',
        '13:2',
        !f.contains(243)
            ? 1
            : !f.contains(244)
            ? 2
            : 43,
      ),
      (246, '回周处庙领取酬谢', '10:2', 42),
      (247, '向酆都居民打听鬼事', '11:1', 1),
    ];
    for (final s in late) {
      if (!f.contains(s.$1)) return goal(s.$2, s.$3, s.$4);
    }
    if (!f.contains(248)) {
      return script == '11:10'
          ? goal('夜访酆都，寻找白无常', '11:10', 1)
          : goal('向客栈掌柜打听并住店', '11:4', 43);
    }
    for (final s in <(int, String, String, int)>[
      (249, '前往城隍庙，寻找鬼王', '11:10', 51),
      (250, '向鬼王追查霸王钟', '11:10', 2),
      (251, '通过鹤鸣山洞口守卫', '14:8', 43),
      (252, '面对鹤鸣山天道', '14:8', 1),
    ]) {
      if (!f.contains(s.$1)) return goal(s.$2, s.$3, s.$4);
    }
    if (!f.contains(253)) {
      return goal(
        '寻找玄武：${!f.contains(1100) ? '查看洞中文字' : '触发机关'}',
        '14:9',
        !f.contains(1100)
            ? 22
            : game.variables[1] == 1
            ? 3
            : game.variables[1] == 2
            ? 4
            : game.variables[1] == 3
            ? 5
            : 2,
      );
    }
    if (!f.contains(254)) return goal('深入天师陵墓', '14:11', 1);
    if (!f.contains(259) && !f.contains(2002)) {
      return goal('装备天心灯，准备回山', script, 0, '天心灯需要装备生效，四象精魄归位后再触发阵心。');
    }
    if (!f.contains(259)) {
      return goal(
        '返回三清山，破解四象阵',
        '2:32',
        !f.contains(255)
            ? 7
            : !f.contains(256)
            ? 3
            : !f.contains(257)
            ? 5
            : !f.contains(258)
            ? 1
            : 9,
      );
    }
    if (!f.contains(260)) return goal('进入无机洞面对师父', '1:5', 45);
    return goal('回伏魔洞，将混元金斗正位', '2:18', 17);
  }

  List<GameGoal> get sideGoals {
    final f = game.flags, rows = <GameGoal>[];
    void add(
      String label,
      String script,
      int event,
      bool done,
      bool ready,
      String hint,
    ) {
      rows.add(
        GameGoal(
          label,
          script,
          event,
          done: done,
          ready: ready && !done,
          hint: hint,
        ),
      );
    }

    add(
      '情书：接受老孟托付',
      '3:5',
      1,
      f.contains(201),
      f.contains(202) && !f.contains(216),
      '收信后前往建业。',
    );
    add(
      '寻女：向东东打听蔡婆婆',
      '3:4',
      1,
      f.contains(205),
      f.contains(202) && !f.contains(216),
      '先取得蔡婆婆闭门不出的线索。',
    );
    add(
      '寻女：向阿霞打听小画家',
      '3:7',
      1,
      f.contains(206),
      f.contains(205) && (!f.contains(216) || f.contains(205)),
      '线索开放蔡婆婆家入口。',
    );
    add(
      '寻女：接受蔡婆婆委托',
      '3:8',
      1,
      f.contains(207),
      f.contains(206) && (!f.contains(216) || f.contains(205)),
      '了解小画家被李虎掳走的经过。',
    );
    add(
      '李府：决定老王去留',
      '5:18',
      1,
      f.contains(211) || f.contains(213),
      f.contains(210) && !f.contains(215),
      '放走与处置是互斥分支，由你决定。',
    );
    add(
      '寻女：救出东厢房的小画家',
      game.cursor?.script.id == '5:16' ? '5:16' : '5:1',
      game.cursor?.script.id == '5:16' ? 1 : 56,
      f.contains(214),
      f.contains(210) &&
          f.contains(207) &&
          !f.contains(215) &&
          !f.contains(2335) &&
          (game.cursor?.script.id == '5:16' ||
              (game.inventory['14:4'] ?? 0) > 0),
      '用金色钥匙打开东厢房。',
    );
    add(
      '老王妻子：打听李府密道',
      '5:2',
      1,
      f.contains(212),
      f.contains(211) && !f.contains(215) && !f.contains(213),
      '放走老王后，他的妻子会告知密道。',
    );
    final vault = [
      65,
      66,
      67,
      68,
      69,
      70,
    ].where((id) => !f.contains(id)).toList();
    add(
      '李府密道：探索宝库六处宝藏',
      '5:21',
      vault.isEmpty ? 2 : vault.first - 63,
      vault.isEmpty,
      f.contains(212) && !f.contains(215),
      '沿真实密道取宝，已完成 ${6 - vault.length}/6。',
    );
    add(
      '寻女：回蔡婆婆家领取答谢',
      '3:8',
      1,
      f.contains(222),
      f.contains(214) && !f.contains(216),
      '救人后回村领取七星灯。',
    );
    add(
      '情书：向建业阿军交信',
      '7:9',
      1,
      f.contains(264),
      f.contains(201) &&
          f.contains(224) &&
          !f.contains(255) &&
          (game.inventory['14:3'] ?? 0) > 0,
      '钟山失钟、建业开放后交信，获得三把万能钥匙。',
    );
    add(
      '建业钱袋：决定归还或留下',
      '7:1',
      21,
      f.contains(1117) || f.contains(1118),
      f.contains(218) && f.contains(224) && !f.contains(255),
      '去留由你决定。',
    );
    final locks = [
      ('白水镇：取得虫子卡片', '9:1', 21, 1077, 229, 2330, 0),
      ('南北村：紫瞳魔灯', '10:1', 21, 1114, 234, 2331, 252),
      ('酆都客栈：取得小鬼卡片', '11:4', 21, 1095, 247, 2332, 0),
      ('鹤鸣山洞：取得不点卡片', '14:9', 21, 1099, 252, 2333, 0),
      ('观星亭：开启后期宝箱', '2:33', 1, 1104, 260, 2334, 0),
    ];
    final remainingKeys = game.inventory['14:2'] ?? 0;
    final reservedCardKeys = const [
      (1077, 2330),
      (1095, 2332),
      (1099, 2333),
    ].where((card) => !f.contains(card.$1) && !f.contains(card.$2)).length;
    for (final lock in locks) {
      final isCard = const {1077, 1095, 1099}.contains(lock.$4);
      add(
        lock.$1,
        lock.$2,
        lock.$3,
        f.contains(lock.$4),
        f.contains(lock.$5) &&
            !f.contains(lock.$6) &&
            !f.contains(lock.$7) &&
            remainingKeys > 0 &&
            (isCard || remainingKeys > reservedCardKeys),
        isCard
            ? '消耗一把万能钥匙取得任务卡片，当前剩余 $remainingKeys 把。'
            : '先为未取得的任务卡片保留 $reservedCardKeys 把钥匙，再开启可选宝箱。',
      );
    }
    add(
      '愚人居：通宵虫的卡片与衣服',
      '2:52',
      30,
      f.contains(2301) || f.contains(263),
      f.contains(254) && f.contains(2008),
      '按原分支归还卡片或换衣服。',
    );
    add(
      '愚人居：不点点的隐藏商店',
      '2:52',
      31,
      f.contains(2302),
      f.contains(254) && f.contains(2010) && (game.inventory['14:7'] ?? 0) > 0,
      '交出卡片后进入原商店。',
    );
    add(
      '愚人居：南方小鬼的绝世武功',
      '2:52',
      32,
      f.contains(2303) || f.contains(261),
      f.contains(254) && f.contains(2009) && (game.inventory['14:6'] ?? 0) > 0,
      '归还小鬼卡片学习武功。',
    );
    add(
      '伏魔洞：护剑神再比试',
      '2:18',
      17,
      f.contains(2314) || game.ended,
      f.contains(260),
      '免战或欠扁由你决定。',
    );
    return rows;
  }

  GameGoal get nextGoal {
    if (game.preferences['storyScope'] != 'complete') return mainGoal;
    final available = sideGoals.where((g) => g.ready).toList();
    // 洞内先取任务卡片，再继续玄武机关。钥匙是真实库存条件，与取得钥匙的
    // 送信标志无关；已开箱、已取卡或主动取消者不重复推荐、不重复发奖励。
    if (game.cursor?.script.id == '14:9') {
      final card = available
          .where((g) => g.scriptId == '14:9' && g.event == 21)
          .firstOrNull;
      if (card != null) return card;
    }
    return available.firstOrNull ?? mainGoal;
  }

  _NavState _capture() => _NavState(
    game.map?.id ?? '',
    game.cursor?.script.id ?? '',
    game.player?.x ?? 0,
    game.player?.y ?? 0,
    Set.of(game.flags),
    List.of(game.variables),
    game.npcs.map((id, n) => MapEntry(id, (n.x, n.y))),
    game.npcs.entries
        .where((e) => const {1, 2, 3}.contains(e.value.state))
        .map((e) => e.key)
        .toSet(),
  );

  void cancel() {
    _worker?.close();
    _worker = null;
    generation++;
    active = null;
    _leg = null;
    planning = false;
    waitTicks = 0;
    _blockedTicks = 0;
    game.route.clear();
  }

  Future<void> startGoal([GameGoal? goal]) async {
    if (game.player == null ||
        game.screen != 'play' ||
        game.cursor?.running == true ||
        game.operation != null ||
        game.battle != null ||
        game.menus.isNotEmpty) {
      game.notice = '先完成当前剧情、菜单或战斗';
      return;
    }
    cancel();
    final selected = goal ?? nextGoal;
    active = selected.scriptId == '5:1' && selected.event == 56
        ? GameGoal(
            selected.label,
            selected.scriptId,
            selected.event,
            hint: selected.hint,
            continuation: GameGoal(selected.label, '5:16', 1),
          )
        : selected;
    await _plan();
  }

  Future<void> _plan() async {
    final goal = active;
    if (goal == null || planning) return;
    planning = true;
    final request = generation;
    try {
      final worker = _NavigationWorker();
      _worker = worker;
      worker.subscription = worker.port.listen((message) {
        if (worker.result.isCompleted) return;
        if (message is String) {
          worker.result.completeError(StateError(message));
        } else if (message is List) {
          worker.result.completeError(
            StateError('后台寻路异常：${message.firstOrNull}'),
          );
        } else {
          worker.result.complete(message as _NavLeg?);
        }
      });
      // 先建立结果监听，避免子隔离区快速完成或取消时遗失返回值。
      final future = worker.result.future;
      try {
        final isolate = await Isolate.spawn(
          _planNavigation,
          _NavigationRequest(
            game.data.maps,
            game.data.scripts,
            Map.of(game.inventory),
            _capture(),
            goal,
            worker.port.sendPort,
          ),
          onError: worker.port.sendPort,
          onExit: worker.port.sendPort,
          errorsAreFatal: true,
        );
        worker.isolate = isolate;
        if (worker.closed) isolate.kill(priority: Isolate.immediate);
      } catch (error) {
        if (!worker.result.isCompleted) worker.result.completeError(error);
      }
      final result = await future;
      worker.close();
      if (identical(_worker, worker)) _worker = null;
      if (request != generation) return;
      if (result == null) {
        active = null;
        game.notice = '当前道路或剧情条件未开放：${goal.label}';
        return;
      }
      _leg = result;
      game.notice = result.blockedBy == null
          ? '正在前往：${goal.label}'
          : '前方人物暂时挡路，正在等待或绕行';
      if (!game.walkTo(result.anchorX, result.anchorY)) {
        _leg = null;
        waitTicks = 12;
      }
    } catch (error) {
      if (request == generation) {
        active = null;
        game.notice = '寻路失败：$error';
      }
    } finally {
      if (request == generation) {
        _worker?.close();
        _worker = null;
      }
      // 旧请求结束不能解除新请求的 planning 状态。
      if (request == generation) planning = false;
    }
  }

  void tick() {
    if (active == null || planning || game.route.isNotEmpty) return;
    if (waitTicks > 0) {
      waitTicks--;
      return;
    }
    final next = _leg, player = game.player;
    if (next == null ||
        player == null ||
        player.x != next.anchorX ||
        player.y != next.anchorY) {
      _leg = null;
      _plan();
      return;
    }
    if (next.blockedBy != null) {
      _leg = null;
      waitTicks = 12;
      final blocker = game.npcs[next.blockedBy];
      if (blocker != null && const {1, 2, 3}.contains(blocker.state)) {
        // 活动人物会回来，等待并按新位置重算；不能为追人强行穿越地图出口。
        _blockedTicks = 0;
        return;
      }
      if (++_blockedTicks >= 20) {
        active = null;
        game.notice = '前方人物挡路，请等待让路或手动交互后再次前往';
      }
      return;
    }
    _blockedTicks = 0;
    if (next.destination && next.event == 0) {
      game.notice = active?.hint ?? '';
      active = null;
      _leg = null;
      return;
    }
    // 行走中 NPC 可能移位；绝不对旧坐标上的其他人执行确认。
    if (next.event <= 40) {
      final npc = game.npcs[next.event];
      if (npc == null || npc.x != next.x || npc.y != next.y) {
        _leg = null;
        _plan();
        return;
      }
    }
    final direction = next.x > player.x
        ? 2
        : next.x < player.x
        ? 4
        : next.y > player.y
        ? 3
        : 1;
    if (next.event == 255) {
      game.triggerEvent(255);
    } else if (next.event > 40) {
      // 地图事件应与正常走入出口一致，不能只触发事件而遗漏原位置变化。
      game.key(
        [GameKey.up, GameKey.right, GameKey.down, GameKey.left][direction - 1],
        automatic: true,
      );
    } else {
      player.direction = direction;
      game.interact();
    }
    if (next.destination) {
      final follow = active?.continuation;
      game.notice = follow == null
          ? '已到达：${active?.label ?? ''}'
          : '开门后继续前往：${follow.label}';
      active = follow;
    }
    _leg = null;
    waitTicks = 3;
  }

  /// 本图点击寻路也必须避开尚未处理的事件；跨图事件由路线执行器单独触发。
  bool isPassiveEvent(int event) => _passive(_capture(), event);
  bool _passive(_NavState state, int event) {
    final script = game.data.scripts[state.scriptId];
    if (script == null ||
        event < 1 ||
        event > script.events.length ||
        script.events[event - 1] == 0) {
      return true;
    }
    final result = _simulate(state, event);
    return result.stable && result.state.key == state.key;
  }

  /// 即使只读预览对白，也不跨越选择、战斗、奖励或物品消耗。
  _NavOutcome _simulate(_NavState input, int event, {bool preview = false}) {
    final state = input.copy();
    final visited = <String>{state.scriptId};
    var script = game.data.scripts[state.scriptId];
    if (script == null) return _NavOutcome(state, false, visited);
    int? pointer = event == 0
        ? 0
        : event <= script.events.length
        ? script.addresses[script.events[event - 1]]
        : null;
    for (var budget = 0; budget < 500; budget++) {
      if (pointer == null ||
          pointer < 0 ||
          pointer >= script!.commands.length) {
        return _NavOutcome(state, false, visited);
      }
      final command = script.commands[pointer];
      int n(int i) => command.arg(i);
      int value(int i) =>
          i >= 0 && i < state.variables.length ? state.variables[i] : 0;
      if (barriers.contains(command.opcode) &&
          !(preview && {13, 47, 61, 69}.contains(command.opcode))) {
        return _NavOutcome(state, false, visited);
      }
      int? jump;
      switch (command.opcode) {
        case 9:
          return _NavOutcome(state, true, visited);
        case 1:
          state.mapId = '${n(0)}:${n(1)}';
          state.x = n(2) + 4;
          state.y = n(3) + 3;
        case 10:
          jump = n(0);
        case 11:
          if (state.flags.contains(n(0)) &&
              !_allowYurenReturn(script, command, state.flags)) {
            jump = n(1);
          }
        case 12:
          if (n(0) >= 0 && n(0) < 240) state.variables[n(0)] = n(1);
        case 21:
          if (value(n(0)) == n(1)) jump = n(2);
        case 22:
          if (n(0) >= 0 && n(0) < 240) state.variables[n(0)] += n(1);
        case 23:
          if (n(0) >= 0 && n(0) < 240) state.variables[n(0)] -= n(1);
        case 26:
          state.flags.add(n(0));
        case 27:
          state.flags.remove(n(0));
        case 3:
        case 33:
          state.npcs.remove(n(0));
          state.moving.remove(n(0));
        case 52:
          state.npcs.clear();
          state.moving.clear();
        case 32:
        case 38:
          state.npcs[n(0)] = (n(2), n(3));
        case 46:
          if (const {1, 2, 3}.contains(n(1))) {
            state.moving.add(n(0));
          } else {
            state.moving.remove(n(0));
          }
        case 6:
          if (state.npcs.containsKey(n(0))) state.npcs[n(0)] = (n(1), n(2));
        case 67:
          if (value(n(0)) > value(n(1))) {
            jump = n(2);
          } else if (value(n(0)) < value(n(1))) {
            jump = n(3);
          }
        case 76:
          if (n(1) >= 0 && n(1) < 240) state.variables[n(1)] = value(n(0));
        case 14:
          state.scriptId = '${n(0)}:${n(1)}';
          visited.add(state.scriptId);
          state.npcs.clear();
          state.moving.clear();
          state.variables.fillRange(200, 240, 0);
          script = game.data.scripts[state.scriptId];
          if (script == null) return _NavOutcome(state, false, visited);
          pointer = 0;
          continue;
      }
      pointer = jump == null ? pointer + 1 : script.addresses[jump];
    }
    return _NavOutcome(state, false, visited);
  }

  _NavFlood? _flood(_NavState state, {bool allowEvents = false}) {
    final map = game.data.maps[state.mapId];
    if (map == null ||
        state.x < 0 ||
        state.y < 0 ||
        state.x >= map.width ||
        state.y >= map.height) {
      return null;
    }
    final distances = List<int>.filled(map.cells.length, -1),
        parents = List<int>.filled(map.cells.length, -1),
        exits = <int, _NavLeg>{},
        passive = <int, bool>{},
        occupied = state.npcs.values.toSet();
    final start = state.y * map.width + state.x,
        queue = Queue<int>()..add(start);
    distances[start] = 0;
    while (queue.isNotEmpty) {
      final at = queue.removeFirst(), x = at % map.width, y = at ~/ map.width;
      for (final direction in [1, 2, 3, 4]) {
        final (dx, dy) = GameEngine._delta(direction);
        final nx = x + dx, ny = y + dy;
        if (nx < 0 || ny < 0 || nx >= map.width || ny >= map.height) continue;
        final event = map.event(nx, ny) + 40, next = ny * map.width + nx;
        if (event > 40) {
          exits.putIfAbsent(event, () => _NavLeg(x, y, nx, ny, event));
        }
        if (distances[next] >= 0 ||
            !map.canWalk(nx, ny, player: true) ||
            occupied.contains((nx, ny))) {
          continue;
        }
        if (!allowEvents &&
            event > 40 &&
            !passive.putIfAbsent(event, () => _passive(state, event))) {
          continue;
        }
        distances[next] = distances[at] + 1;
        parents[next] = at;
        queue.add(next);
      }
    }
    return _NavFlood(map, distances, parents, exits);
  }

  _NavLeg? _approach(
    _NavState state,
    _NavFlood flood,
    int event, {
    bool destination = false,
  }) {
    final map = flood.map;
    final points = event <= 40
        ? [if (state.npcs[event] != null) state.npcs[event]!]
        : [
            for (var i = 0; i < map.cells.length; i++)
              if (map.cells[i] >> 8 == event - 40)
                (i % map.width, i ~/ map.width),
          ];
    _NavLeg? result;
    var best = 2147483647;
    for (final point in points) {
      for (final direction in [1, 2, 3, 4]) {
        final (dx, dy) = GameEngine._delta(direction);
        final x = point.$1 - dx, y = point.$2 - dy;
        if (x < 0 || y < 0 || x >= map.width || y >= map.height) continue;
        final distance = flood.distances[y * map.width + x];
        if (distance >= 0 && distance < best) {
          best = distance;
          result = _NavLeg(
            x,
            y,
            point.$1,
            point.$2,
            event,
            destination: destination,
          );
        }
      }
    }
    return result;
  }

  /// NPC 楼梯和引路石才是道路，普通路人、商人、宝箱不能成为自动交互出口。
  Set<int> _transfers(GameScript script) =>
      _transferCache.putIfAbsent(script.id, () {
        final result = <int>{};
        for (var event = 1; event <= script.events.length; event++) {
          if (event > 40 && event != 255) continue;
          final first = script.addresses[script.events[event - 1]];
          if (first == null) continue;
          final pending = <int>[first], checked = <int>{};
          while (pending.isNotEmpty && checked.length < 400) {
            final at = pending.removeLast();
            if (at < 0 || at >= script.commands.length || !checked.add(at)) {
              continue;
            }
            final command = script.commands[at];
            if ({9, 20, 68}.contains(command.opcode)) continue;
            if ({1, 14, 66}.contains(command.opcode)) result.add(event);
            void branch(int address) {
              final p = script.addresses[address];
              if (p != null) pending.add(p);
            }

            switch (command.opcode) {
              case 10:
                branch(command.arg(0));
                continue;
              case 11:
                branch(command.arg(1));
              case 21:
                branch(command.arg(2));
              case 31:
                branch(command.arg(0));
              case 39:
                for (final address in command.args.skip(13)) {
                  branch(address);
                }
                continue;
            }
            pending.add(at + 1);
          }
        }
        return result;
      });

  int _hops(String from, String to) =>
      _hopCache.putIfAbsent((from, to), () => _computeHops(from, to));

  int _computeHops(String from, String to) {
    final queue = <(String, int)>[(from, 0)], seen = <String>{from};
    for (var i = 0; i < queue.length; i++) {
      final (id, distance) = queue[i];
      if (id == to) return distance;
      final script = game.data.scripts[id];
      if (script == null) continue;
      for (final command in script.commands) {
        if (command.opcode == 14 || command.opcode == 66) {
          final target = '${command.arg(0)}:${command.arg(1)}';
          if (seen.add(target)) queue.add((target, distance + 1));
        }
      }
    }
    return 1000000;
  }

  Future<_NavLeg?> _route(
    _NavState initial,
    GameGoal goal,
    int request, {
    bool allowBoundary = true,
    bool dynamicProbe = false,
  }) async {
    final pending = <_NavNode>[_NavNode(initial, null, 0)],
        seen = <String>{},
        scheduled = <String>{initial.key},
        frontier = <_NavBoundary>[];
    _NavLeg? obstruction;
    for (var budget = 0; pending.isNotEmpty && budget < 4096; budget++) {
      if (budget % 8 == 0) {
        await Future<void>.delayed(Duration.zero);
        if (request != generation) return null;
      }
      // 优先朝目标地区展开，避免无关迷阵消耗跨区域任务的搜索预算。
      pending.sort(
        (a, b) => (a.cost + 32 * _hops(a.state.scriptId, goal.scriptId))
            .compareTo(b.cost + 32 * _hops(b.state.scriptId, goal.scriptId)),
      );
      final node = pending.removeAt(0), state = node.state;
      if (!seen.add(state.key)) continue;
      final flood = _flood(state), script = game.data.scripts[state.scriptId];
      if (flood == null || script == null) continue;
      final map = flood.map;
      if (state.scriptId == goal.scriptId) {
        if (goal.event == 0) {
          return (node.first ??
                  _NavLeg(
                    state.x,
                    state.y,
                    state.x,
                    state.y,
                    0,
                    destination: true,
                  ))
              .ranked(node.cost);
        }
        final arrival = _approach(state, flood, goal.event, destination: true);
        if (arrival != null) {
          return (node.first ?? arrival).ranked(
            node.cost +
                flood.distances[arrival.anchorY * map.width + arrival.anchorX],
          );
        }
        if (goal.event <= 40 && state.moving.contains(goal.event)) {
          // 目标人物暂时进入了边缘或被其他人物挡住。它仍在本图，地图出口不能
          // 当成接近人物的绕行路径，否则愚人居的单向出口会把整个支线锁死。
          return (node.first ??
                  _NavLeg(
                    state.x,
                    state.y,
                    state.x,
                    state.y,
                    goal.event,
                    blockedBy: goal.event,
                  ))
              .ranked(node.cost);
        }
        final relaxed = state.copy()..npcs.clear();
        final open = _flood(relaxed, allowEvents: true);
        final target = open == null ? null : _approach(state, open, goal.event);
        if (open != null && target != null) {
          final path = <int>[];
          var at = target.anchorY * map.width + target.anchorX;
          while (at >= 0) {
            path.add(at);
            at = open.parents[at];
          }
          for (final cell in path.reversed) {
            final x = cell % map.width, y = cell ~/ map.width;
            final blocker = state.npcs.entries
                .where((e) => e.value == (x, y))
                .firstOrNull;
            if (blocker != null) {
              final near = _approach(state, flood, blocker.key);
              if (near != null) {
                final stop =
                    node.first ??
                    _NavLeg(
                      near.anchorX,
                      near.anchorY,
                      near.x,
                      near.y,
                      near.event,
                      blockedBy: blocker.key,
                    );
                if (!state.moving.contains(blocker.key)) return stop;
                obstruction ??= stop;
              }
              break;
            }
            final event = map.event(x, y) + 40;
            if (allowBoundary && event > 40 && flood.distances[cell] < 0) {
              final near = _approach(state, flood, event);
              if (near != null) {
                return node.first ??
                    _NavLeg(
                      near.anchorX,
                      near.anchorY,
                      near.x,
                      near.y,
                      event,
                      boundary: true,
                    );
              }
              break;
            }
          }
        }
      }
      final exits = Map<int, _NavLeg>.of(flood.exits),
          transfers = _transfers(script);
      for (final id in state.npcs.keys.where(transfers.contains)) {
        final exit = _approach(state, flood, id);
        if (exit != null) exits[id] = exit;
      }
      if ((game.inventory['13:1'] ?? 0) > 0 && transfers.contains(255)) {
        exits[255] = _NavLeg(state.x, state.y, state.x, state.y, 255);
      }
      for (final exit in exits.values) {
        final input = state.copy()
          ..x = exit.anchorX
          ..y = exit.anchorY;
        final result = _simulate(input, exit.event),
            cost =
                node.cost +
                math
                    .max(
                      0,
                      flood.distances[exit.anchorY * map.width + exit.anchorX],
                    )
                    .toInt() +
                1;
        if (goal.event == 0 && result.visited.contains(goal.scriptId)) {
          // 路线的最后一步就是触发入场剧情。无需假设剧情结束后仍停留在同一
          // 脚本；真实对白、战斗和自动切图继续由游戏引擎执行。
          return (node.first ??
                  _NavLeg(
                    exit.anchorX,
                    exit.anchorY,
                    exit.x,
                    exit.y,
                    exit.event,
                    destination: true,
                  ))
              .ranked(cost);
        }
        if (!result.stable) {
          frontier.add(_NavBoundary(node, input, exit, cost));
          continue;
        }
        if (result.state.key != input.key && scheduled.add(result.state.key)) {
          pending.add(_NavNode(result.state, node.first ?? exit, cost));
        }
      }
    }
    if (allowBoundary) {
      _NavBoundary? closest;
      var score = 1000000000;
      final initialHops = _hops(initial.scriptId, goal.scriptId);
      for (var i = 0; i < frontier.length; i++) {
        if (i % 8 == 0) {
          await Future<void>.delayed(Duration.zero);
          if (request != generation) return null;
        }
        final candidate = frontier[i],
            preview = _simulate(
              candidate.input,
              candidate.exit.event,
              preview: true,
            );
        if (goal.event == 0 && preview.visited.contains(goal.scriptId)) {
          final exit = candidate.exit;
          return (candidate.node.first ??
                  _NavLeg(
                    exit.anchorX,
                    exit.anchorY,
                    exit.x,
                    exit.y,
                    exit.event,
                    destination: true,
                  ))
              .ranked(candidate.cost);
        }
        if (preview.state.scriptId == candidate.input.scriptId &&
            preview.state.mapId == candidate.input.mapId) {
          continue;
        }
        var value = 1000000000;
        if (preview.state.scriptId == goal.scriptId) {
          value = candidate.cost;
        } else if (preview.stable) {
          final onward = await _route(
            preview.state,
            goal,
            request,
            allowBoundary: false,
            dynamicProbe: true,
          );
          if (onward != null) value = candidate.cost + onward.score;
        }
        if (value == 1000000000) {
          final hops = _hops(preview.state.scriptId, goal.scriptId);
          if (hops < initialHops) value = 100000 + hops * 1000 + candidate.cost;
        }
        if (value < score) {
          closest = candidate;
          score = value;
        }
      }
      if (closest != null) return closest.leg.ranked(score);
    }
    if (obstruction != null) return obstruction;
    if (!dynamicProbe && initial.moving.isNotEmpty) {
      final relaxed = initial.copy();
      relaxed.npcs.removeWhere((id, _) => initial.moving.contains(id));
      relaxed.moving.clear();
      if (await _route(
            relaxed,
            goal,
            request,
            allowBoundary: allowBoundary,
            dynamicProbe: true,
          ) !=
          null) {
        final flood = _flood(initial);
        if (flood != null) {
          final approaches =
              initial.moving
                  .map((id) => _approach(initial, flood, id))
                  .whereType<_NavLeg>()
                  .toList()
                ..sort(
                  (a, b) => flood
                      .distances[a.anchorY * flood.map.width + a.anchorX]
                      .compareTo(
                        flood.distances[b.anchorY * flood.map.width +
                            b.anchorX],
                      ),
                );
          if (approaches.isNotEmpty) {
            final a = approaches.first;
            return _NavLeg(
              a.anchorX,
              a.anchorY,
              a.x,
              a.y,
              a.event,
              blockedBy: a.event,
            );
          }
        }
      }
    }
    return null;
  }
}

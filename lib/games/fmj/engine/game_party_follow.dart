part of 'game_engine.dart';

/// 地图绘制快照。坐标和朝向独立于剧情角色，伙伴显示不会改写存档中的人物位置。
final class PartyMapPose {
  const PartyMapPose(
    this.actor,
    this.x,
    this.y,
    this.direction,
    this.step, {
    this.order = 0,
  });

  factory PartyMapPose.actual(GameActor actor, {int order = 0}) => PartyMapPose(
    actor,
    actor.x,
    actor.y,
    actor.direction,
    actor.step,
    order: order,
  );

  final GameActor actor;
  final int x, y, direction, step, order;
}

/// A版紧凑纵队：每名伙伴落后领队一格，拐弯复用领队真实走过的路径。
///
/// 仅保存当前队伍长度的行走足迹，不额外寻路、不消耗随机数、不加入NPC碰撞。
/// 轨迹不写入存档；跨图、读档、换领队和成员变化时在新地点重新排列。
/// 所有更新由游戏所在isolate的移动、绘制入口执行，Painter只读取快照。
final class GamePartyFollow {
  GamePartyFollow(this.game);
  final GameEngine game;
  final List<(int, int, int, int)> _trail = [];
  final List<GameActor> _members = [];
  GameMap? _map;
  GameActor? _leader;
  int revision = 0;

  void reset() {
    _trail.clear();
    _members.clear();
    _map = null;
    _leader = null;
    revision++;
  }

  /// 剧情可直接更换地图、成员或人物坐标，在统一绘制入口接住这些变化。
  void synchronize() {
    final map = game.map, leader = game.player;
    if (map == null || leader == null || game.screen != 'play') {
      if (_map != null || _members.isNotEmpty || _trail.isNotEmpty) reset();
      return;
    }
    final changed =
        _members.length != game.players.length ||
        _members.asMap().entries.any(
          (entry) => !identical(entry.value, game.players[entry.key]),
        );
    if (!identical(_map, map) ||
        !identical(_leader, leader) ||
        changed ||
        _trail.isEmpty ||
        _trail.first.$1 != leader.x ||
        _trail.first.$2 != leader.y) {
      _seed(map, leader);
    }
  }

  void beforeMove(GameActor actor) {
    if (identical(actor, game.player)) synchronize();
  }

  /// 只在领队实际移动成功后压入足迹，撞墙或仅转身不会让队友额外走一步。
  void afterMove(GameActor actor) {
    if (!identical(actor, game.player)) return;
    if (_trail.isEmpty ||
        !identical(_map, game.map) ||
        !identical(_leader, actor) ||
        (actor.x - _trail.first.$1).abs() + (actor.y - _trail.first.$2).abs() !=
            1) {
      synchronize();
      return;
    }
    _trail.insert(0, (actor.x, actor.y, actor.direction, actor.step));
    if (_trail.length > game.players.length) {
      _trail.removeRange(game.players.length, _trail.length);
    }
    revision++;
  }

  void _seed(GameMap map, GameActor leader) {
    _map = map;
    _leader = leader;
    _members
      ..clear()
      ..addAll(game.players);
    _trail
      ..clear()
      ..add((leader.x, leader.y, leader.direction, leader.step));
    final back = _opposite(leader.direction);
    for (var index = 1; index < _members.length; index++) {
      final previous = _trail.last;
      (int, int, int, int)? next;
      // 优先排在身后。门口空间不足时选相邻可走格，不能把伙伴排进墙或NPC。
      for (final direction in {back, 1, 2, 3, 4}) {
        final (dx, dy) = GameEngine._delta(direction);
        final x = previous.$1 + dx, y = previous.$2 + dy;
        if (x < 0 || y < 0 || x >= map.width || y >= map.height) continue;
        if (!map.canWalk(x, y, player: true) || game._npcAt(x, y) != null) {
          continue;
        }
        if (_trail.any((point) => point.$1 == x && point.$2 == y)) continue;
        next = (x, y, _opposite(direction), (leader.step - index) % 4);
        break;
      }
      // 狭窄落脚点没有空位时暂时收队，走出一两步后自然展开，不穿墙补位置。
      if (next == null) break;
      _trail.add(next);
    }
    revision++;
  }

  static int _opposite(int direction) => switch (direction) {
    1 => 3,
    2 => 4,
    3 => 1,
    _ => 2,
  };

  /// 同一身份在剧情中已由NPC单独摆位时使用剧情站位，避免出现两个小梅/袁萍芷。
  bool _hasStoryActor(GameActor actor) => game.npcs.values.any(
    (npc) =>
        npc.type == 2 &&
        (actor.name.isNotEmpty && npc.name == actor.name ||
            actor.index == 2 && npc.index == 6 ||
            actor.index == 3 && npc.index == 7),
  );

  Iterable<PartyMapPose> get followers sync* {
    if (game.screen != 'play' ||
        game.battle != null ||
        game.operation?.movie != null ||
        game.operation?.kind == 'credits') {
      return;
    }
    final count = math.min(_trail.length, game.players.length);
    for (var index = 1; index < count; index++) {
      final actor = game.players[index];
      if (_hasStoryActor(actor)) continue;
      final point = _trail[index];
      yield PartyMapPose(
        actor,
        point.$1,
        point.$2,
        point.$3,
        point.$4,
        order: -index,
      );
    }
  }

  /// 黑白、彩色画面共用同一纵队与前后遮挡顺序；重叠收队时领队最后绘制。
  List<PartyMapPose> get worldActors =>
      [
        for (final actor in game.npcs.values) PartyMapPose.actual(actor),
        ...followers,
        if (game.player case final leader?)
          PartyMapPose.actual(leader, order: 1),
      ]..sort((a, b) {
        final depth = a.y.compareTo(b.y);
        return depth != 0 ? depth : a.order.compareTo(b.order);
      });
}

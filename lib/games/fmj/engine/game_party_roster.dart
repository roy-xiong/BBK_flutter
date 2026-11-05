part of 'game_engine.dart';

/// 离队角色保存在会话自己的小型名册中，最多三名真实角色；没有UI或平台资源。
/// 剧情入队恢复原实例数据，离队转存完整数据，只有真正开始新游戏才清空名册。
final class GamePartyRoster {
  GamePartyRoster(this.game);
  final GameEngine game;
  final Map<int, GameActor> _reserve = {};

  void reset() => _reserve.clear();

  /// 返回独立副本，选关和存档准备不能通过引用提前改写当前进度。
  Map<int, GameActor> copyReserve() => {
    for (final e in _reserve.entries)
      e.key: GameActor.fromJson(e.value.toJson()),
  };
  Map<String, dynamic> snapshot() => {
    for (final e in _reserve.entries) '${e.key}': e.value.toJson(),
  };

  /// 快照先验证，后由引擎统一替换；未知身份、重复/不完整数据均不能污染当前队伍。
  Map<int, GameActor> decode(Object? raw) {
    if (raw == null) return {};
    if (raw is! Map || raw.length > 3) throw const FormatException('离队名册无效');
    final result = <int, GameActor>{};
    try {
      for (final e in raw.entries) {
        final id = int.tryParse('${e.key}'), value = e.value;
        if (id == null ||
            id < 1 ||
            id > 3 ||
            value is! Map ||
            value['type'] != 1 ||
            value['index'] != id ||
            result.containsKey(id)) {
          throw const FormatException('离队角色身份无效');
        }
        for (final key in [
          'level',
          'maxHp',
          'hp',
          'maxMp',
          'mp',
          'attack',
          'defense',
          'speed',
          'spirit',
          'luck',
          'exp',
        ]) {
          if (value[key] is! int) throw const FormatException('离队角色属性无效');
        }
        final actor = GameActor.fromJson(Map<String, dynamic>.from(value));
        if (game.data.record(3, 1, id) == null ||
            actor.equipment.whereType<String>().any(
              (id) => game.goods(id) == null,
            )) {
          throw const FormatException('离队角色资源无效');
        }
        actor.synchronizeLearnedMagic(game.data);
        result[id] = actor;
      }
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('离队名册格式无效');
    }
    return result;
  }

  void restoreReserve(Map<int, GameActor> next) {
    _reserve
      ..clear()
      ..addAll(next);
  }

  GameActor? get departedYuan => _reserve[3];
  void retainYuan(GameActor? actor) {
    if (actor == null) {
      _reserve.remove(3);
    } else {
      _reserve[3] = actor;
    }
  }

  /// 所有普通离队指令统一转存；重复移除不会覆盖原来保存的数据。
  void depart(int id) {
    final actor = game._player(id);
    if (actor == null) return;
    _reserve[id] = GameActor.fromJson(actor.toJson());
    game.players.removeWhere((p) => p.index == id);
    game.partyFollow.reset();
  }

  /// 先查当前队员，再取离队数据，最后才从ROM首次创建；防止同名双人和重复加成。
  GameActor? join(int id, int x, int y) {
    final current = game._player(id);
    if (current != null) return current;
    if (game.players.length >= 3) return null;
    final actor = _reserve.remove(id) ?? GameActor.load(game.data, 1, id);
    if (actor == null) return null;
    actor
      ..x = x
      ..y = y;
    actor.synchronizeLearnedMagic(game.data);
    game.players.add(actor);
    game.ringBlade.synchronizePlayers();
    game.partyFollow.reset();
    return actor;
  }

  /// 选关不出场的角色保留培养结果，但穿戴物已退到背包，缓存不能再持有第二份。
  /// 用正式卸装增量撤回属性/免疫；库存由调用者一次性退回，避免“重复恢复装备”。
  GameActor stageReserveWithoutEquipment(GameActor source) {
    final actor = GameActor.fromJson(source.toJson());
    for (var slot = 0; slot < actor.equipment.length; slot++) {
      final id = actor.equipment[slot];
      if (id == null) continue;
      actor.equipment[slot] = null;
      final r = game.goods(id);
      if (r != null) game._equipmentDelta(actor, r, -1);
    }
    return actor;
  }
}

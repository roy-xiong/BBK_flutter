part of 'game_engine.dart';

/// 起死回生丹的扩展资源与离队人物备份。备份属于单个游戏会话，随存档读写，
/// 不保留Widget、图片或回调；正常服用、剧情复活分别只消耗一颗。
final class GameResurrectionPill {
  GameResurrectionPill(this.game);
  final GameEngine game;
  static const id = '11:16';
  static const collectedFlag = 2391, revivedFlag = 2392;
  static const story = '14:8', choiceAddress = 9020, rejoinAddress = 9040;
  static const prompt = '是否使用起死回生丹，复活袁萍芷？\n消耗：起死回生丹 ×1';
  GameActor? _departed;
  GameRecord? _record;

  GameRecord get record {
    game.data.customImages.putIfAbsent(
      '9:11:16',
      () => GameImage(16, 16, [
        GameBitmap.monochrome([
          0,
          0,
          0,
          2016,
          4088,
          8188,
          16380,
          8184,
          8184,
          4088,
          4080,
          2016,
          992,
          0,
          0,
          0,
        ]),
      ], 32),
    );
    return _record ??= GameRecord.custom(
      game.data,
      {
        0: 11,
        1: 16,
        2: 134,
        3: 0,
        4: 0,
        5: 16,
        18: 1000000,
        20: 1000000,
        22: 50,
        23: 50,
        24: 0,
        25: 0,
        26: 1,
        27: 0,
        28: 0,
        29: 0,
        132: 0,
      },
      {6: '起死回生丹', 30: '珍贵的还元灵丹，可售一百万钱。服用后气血、真气上限永久各加50，并按新上限回满。'},
    );
  }

  void reset() {
    _departed = null;
  }

  Map<String, dynamic>? snapshot() => _departed?.toJson();

  /// 在原剧情移除袁萍芷之前复制实际人物，保留仙药成长、经验、法术、装备和加成。
  void rememberDeparture() {
    final actor = game._player(3);
    if (actor != null) _departed = GameActor.fromJson(actor.toJson());
  }

  /// 必须在restore提交新会话前完成校验，坏备份不能使有效存档只恢复一半。
  GameActor? decode(Object? raw) {
    if (raw == null) return null;
    if (raw is! Map || raw['type'] != 1 || raw['index'] != 3) {
      throw const FormatException('袁萍芷离队备份无效');
    }
    try {
      final actor = GameActor.fromJson(Map<String, dynamic>.from(raw));
      if (actor.equipment.whereType<String>().any(
        (id) => game.goods(id) == null,
      )) {
        throw const FormatException('袁萍芷备份装备无效');
      }
      return actor;
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('袁萍芷离队备份格式无效');
    }
  }

  void restoreDeparted(GameActor? actor) {
    _departed = actor;
  }

  /// 剧情消费由57指令完成。本函数只在指定的复活入队指令调用，拒绝重复入队。
  /// 老档没有离队备份时，以真实人物资源和当前队伍等级恢复，不改动其他成员。
  bool rejoin(int x, int y) {
    if (game.players.length >= 3 || game._player(3) != null) return false;
    final original = _departed;
    final actor = original == null
        ? GameActor.load(game.data, 1, 3)
        : GameActor.fromJson(original.toJson());
    if (actor == null) return false;
    if (original == null) {
      final level = game.players.fold<int>(
        actor.level,
        (v, p) => math.max(v, p.level),
      );
      actor.levelUp(game.data, level);
    }
    actor
      ..x = x
      ..y = y
      ..direction = 3
      ..step = 0;
    game.players.add(actor);
    game.ringBlade.synchronizePlayers();
    actor
      ..hp = actor.maxHp
      ..mp = actor.maxMp;
    actor.clearStatus(15);
    actor.modifiers.clear();
    _departed = null;
    game.partyFollow.reset();
    return true;
  }

  /// 普通服用先永久提高双上限，再按新上限回满；剧情复活不走这条成长分支。
  void applyMedicine(GameActor actor) {
    actor.maxHp += 50;
    actor.maxMp += 50;
    actor.hp = actor.maxHp;
    actor.mp = actor.maxMp;
  }
}

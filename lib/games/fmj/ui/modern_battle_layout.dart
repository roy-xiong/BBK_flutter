import 'dart:math' as math;
import 'dart:ui';
import '../engine/game_actor.dart';
import '../engine/game_engine.dart';

/// 将原战斗动作映射至敌左我右的舞台；原版坐标、命中和逐帧时序保持不变。
final class ModernBattleLayout {
  const ModernBattleLayout(this.battle);
  final GameBattle battle;
  static const players = [Offset(458, 248), Offset(518, 225), Offset(566, 200)];
  static const enemies = [Offset(235, 236), Offset(285, 196), Offset(325, 252)];

  Offset resting(GameActor actor) {
    final team = actor.type == 1
        ? battle.game.players
        : battle.presentationEnemies;
    final index = math.max(0, team.indexOf(actor)).clamp(0, 2);
    return (actor.type == 1 ? players : enemies)[index];
  }

  Offset point(GameActor actor) {
    final base = resting(actor), origin = battle.presentationOrigins[actor];
    if (origin == null) return base;
    final movement = Offset(
      (actor.combatX - origin.$1).toDouble(),
      (actor.combatY - origin.$2).toDouble(),
    );
    final action = battle.current;
    if (movement.distanceSquared < .01 || action == null) return base;
    if (action.kind == 'flee' && identical(action.actor, actor)) {
      return base + Offset(0, movement.dy * 2.2);
    }
    final isAttacker =
        identical(action.actor, actor) ||
        action.cooperativeOrigins.containsKey(actor);
    if (isAttacker && action.kind == 'coop') {
      const formation = [Offset(384, 248), Offset(432, 232), Offset(480, 216)];
      final index = math.max(0, battle.game.players.indexOf(actor)).clamp(0, 2);
      return Offset.lerp(
            base,
            formation[index],
            (action.frame / 5).clamp(0.0, 1.0),
          ) ??
          base;
    }
    final target = action.targets.firstOrNull;
    final destination = target == null
        ? null
        : battle.presentationOrigins[target];
    if (isAttacker &&
        target != null &&
        destination != null &&
        action.kind == 'attack') {
      final vector = Offset(
        (destination.$1 - origin.$1).toDouble(),
        (destination.$2 - origin.$2).toDouble(),
      );
      if (vector.distanceSquared > 0) {
        final progress =
            ((movement.dx * vector.dx + movement.dy * vector.dy) /
                    vector.distanceSquared)
                .clamp(0.0, 1.0);
        final end = resting(target) + Offset(actor.type == 1 ? 62 : -62, 8);
        return Offset.lerp(base, end, progress) ?? base;
      }
    }
    // 法术蓄力和受击的轻微位移直接保留；不将抖动误判成跨场冲锋。
    return base +
        Offset(
          movement.dx.clamp(-4.0, 4.0) * 1.7,
          movement.dy.clamp(-4.0, 4.0) * 1.7,
        );
  }

  Offset raisePoint(BattleRaise raise) {
    final actor = raise.actor;
    if (actor != null) return point(actor) + Offset(0, -86 + raise.dy * 1.4);
    GameActor? nearest;
    var distance = double.infinity;
    for (final entry in battle.presentationOrigins.entries) {
      if (entry.key.type == 3 &&
          !battle.presentationEnemies.contains(entry.key)) {
        continue;
      }
      final dx = entry.value.$1 - raise.x, dy = entry.value.$2 - raise.y;
      final candidate = (dx * dx + dy * dy).toDouble();
      if (candidate < distance) {
        nearest = entry.key;
        distance = candidate;
      }
    }
    return (nearest == null ? const Offset(320, 190) : resting(nearest)) +
        Offset(0, -86 + raise.dy * 1.4);
  }
}

import 'package:flutter/material.dart';
import '../engine/game_engine.dart';
import '../../../ui/core/game_typography.dart';
import 'party_resource_color.dart';

/// 审核通过的敌方气血列表。只读真实战斗角色，不改变血量、伤害或敌人可见状态。
/// presentationEnemies在开战时固定，排除隐藏占位并保留已击败行，避免战斗中跳位。
final class ModernEnemyHealth extends StatelessWidget {
  const ModernEnemyHealth({
    super.key,
    required this.battle,
    required this.sceneWidth,
  });
  final GameBattle battle;
  final double sceneWidth;

  @override
  Widget build(BuildContext context) {
    final enemies = battle.presentationEnemies;
    if (enemies.isEmpty || !sceneWidth.isFinite || sceneWidth <= 0) {
      return const SizedBox.shrink();
    }
    final small = sceneWidth < 500;
    final scale = sceneWidth / (small ? 390 : 960);
    final font = (small ? 10.0 : 16.0) * scale;
    TextStyle text(double size, Color color) => TextStyle(
      inherit: false,
      fontFamily: GameTypography.family,
      fontWeight: FontWeight.w400,
      fontSize: size,
      color: color,
      height: 1.2,
      letterSpacing: 0,
      wordSpacing: 0,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return IgnorePointer(
      child: Container(
        key: const ValueKey('enemy-health-panel'),
        width: (small ? 129.0 : 260.0) * scale,
        padding: EdgeInsets.symmetric(
          horizontal: (small ? 7.0 : 11.0) * scale,
          vertical: (small ? 5.0 : 8.0) * scale,
        ),
        decoration: BoxDecoration(
          // 用户确认敌我信息背景均为45%不透明度；前景文字、头像和血条不整体淡化。
          color: const Color(0x73162e2d),
          border: Border.all(
            color: const Color(0xffbc9f65),
            width: (small ? .7 : 1.0) * scale,
          ),
          borderRadius: BorderRadius.circular((small ? 6.0 : 10.0) * scale),
          boxShadow: [
            BoxShadow(
              color: const Color(0x44000000),
              blurRadius: 7 * scale,
              offset: Offset(0, 2 * scale),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < enemies.length; i++) ...[
              if (i > 0) SizedBox(height: (small ? 5.0 : 9.0) * scale),
              Builder(
                builder: (context) {
                  final actor = enemies[i];
                  final maximum = actor.maxHp > 0 ? actor.maxHp : 0;
                  final current = actor.hp.clamp(0, maximum);
                  final dead = current == 0;
                  final ratio = maximum == 0 ? 0.0 : current / maximum;
                  final color = dead
                      ? const Color(0xff7f8d8d)
                      : partyResourceColor(current, maximum);
                  final selected =
                      battle.targetKind.isNotEmpty &&
                      battle.targetKind != 'help' &&
                      battle.targetKind != 'item' &&
                      identical(
                        battle.targets.elementAtOrNull(battle.targetIndex),
                        actor,
                      );
                  return Semantics(
                    label:
                        '${actor.name}，气血$current，共$maximum${dead ? '，已击败' : ''}',
                    child: Column(
                      key: ValueKey('enemy-health-row-$i'),
                      children: [
                        Row(
                          children: [
                            Container(
                              width: (small ? 13.0 : 19.0) * scale,
                              height: (small ? 13.0 : 19.0) * scale,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: selected
                                    ? const Color(0xffd6bb79)
                                    : const Color(0xff2a4945),
                              ),
                              child: Text(
                                '${i + 1}',
                                style: text(
                                  font - 2 * scale,
                                  selected
                                      ? const Color(0xff193431)
                                      : const Color(0xffd6bb79),
                                ),
                              ),
                            ),
                            SizedBox(width: (small ? 4.0 : 7.0) * scale),
                            Expanded(
                              child: Text(
                                actor.name,
                                maxLines: 1,
                                style: text(
                                  font,
                                  dead
                                      ? const Color(0xff8a9d9b)
                                      : const Color(0xfff1e6ca),
                                ),
                              ),
                            ),
                            Text(
                              '$current/$maximum',
                              maxLines: 1,
                              style: text(font - scale, color),
                            ),
                          ],
                        ),
                        SizedBox(height: (small ? 3.0 : 5.0) * scale),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(3 * scale),
                          child: Stack(
                            children: [
                              Container(
                                height: (small ? 4.0 : 6.0) * scale,
                                color: const Color(0xff3b4c4c),
                              ),
                              FractionallySizedBox(
                                widthFactor: ratio,
                                child: Container(
                                  height: (small ? 4.0 : 6.0) * scale,
                                  color: color,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

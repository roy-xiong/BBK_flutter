import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../engine/game_actor.dart';
import '../engine/game_engine.dart';
import 'game_view_model.dart';
import 'modern_art.dart';
import 'modern_scene.dart';

const _ink = Color(0xff183431),
    _gold = Color(0xffd6bb79),
    _paper = Color(0xfff1e6ca);

/// 敌左我右的战斗面板。菱形指令仍转发原四方向与确认键，结果由原战斗状态机计算。
final class ModernBattleHud extends StatelessWidget {
  const ModernBattleHud({
    super.key,
    required this.model,
    required this.battle,
    required this.art,
  });
  final GameViewModel model;
  final GameBattle battle;
  final ModernArt? art;

  void _command(GameKey direction) => model.action((game) {
    if (!identical(game.battle, battle) ||
        battle.phase != 'select' ||
        battle.targetKind.isNotEmpty ||
        game.operation != null ||
        game.menus.isNotEmpty) {
      return;
    }
    if (direction == GameKey.right && battle.game.players.length <= 1) return;
    game.press(direction);
    game.press(GameKey.confirm);
  });

  @override
  Widget build(BuildContext context) => FittedBox(
    fit: BoxFit.contain,
    alignment: Alignment.bottomCenter,
    child: SizedBox(
      width: 640,
      height: 384,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 120,
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xf2223f38), Color(0xff122d2a)],
                ),
                border: Border(top: BorderSide(color: _gold, width: 1.4)),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
                child: Column(
                  children: [
                    SizedBox(
                      height: 17,
                      child: Row(
                        children: [
                          Text(
                            '第 ${battle.round + 1} 回合',
                            style: const TextStyle(
                              color: _gold,
                              fontSize: 13,
                              height: 1,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            battle.game.operation != null
                                ? ''
                                : battle.phase == 'perform' &&
                                      battle.current != null
                                ? '${battle.current?.actor.name ?? ''} · ${_actionName()}'
                                : battle.phase == 'select'
                                ? '${battle.selectedPlayer?.name ?? ''} · ${battle.targetKind.isEmpty ? '请选择指令' : '选择目标'}'
                                : '',
                            style: const TextStyle(
                              color: _paper,
                              fontSize: 13,
                              height: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 3),
                    Expanded(
                      child: Row(
                        children: [
                          for (var i = 0; i < 3; i++) ...[
                            if (i > 0) const SizedBox(width: 8),
                            Expanded(
                              child: i >= battle.game.players.length
                                  ? const SizedBox.shrink()
                                  : _PartyCard(
                                      actor: battle.game.players[i],
                                      active:
                                          battle.phase == 'select' &&
                                          identical(
                                            battle.selectedPlayer,
                                            battle.game.players[i],
                                          ),
                                      art: art,
                                    ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (battle.phase == 'select' &&
              battle.targetKind.isEmpty &&
              battle.game.operation == null &&
              battle.game.menus.isEmpty)
            Positioned(
              left: 16,
              bottom: 124,
              child: SizedBox(
                width: 138,
                height: 132,
                child: Stack(
                  children: [
                    _commandButton(48, 7, GameKey.up, '攻', '攻击', 1),
                    _commandButton(14, 41, GameKey.left, '术', '法术', 2),
                    _commandButton(82, 41, GameKey.right, '合', '合击', 4),
                    _commandButton(48, 75, GameKey.down, '策', '策略', 3),
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
  );

  String _actionName() {
    final action = battle.current;
    if (action == null) return '';
    final resource = action.resource;
    if (resource != null &&
        ['magic', 'help', 'self', 'coop'].contains(action.kind)) {
      return battle.game.magicName(resource);
    }
    if (resource != null && ['item', 'throw'].contains(action.kind)) {
      return battle.game.goodsName(resource);
    }
    return switch (action.kind) {
      'attack' => '攻击',
      'defend' => '防御',
      'flee' => '逃跑',
      'coop' => '合击',
      'item' => '使用物品',
      'throw' => '投掷',
      _ => '施法',
    };
  }

  Widget _commandButton(
    double x,
    double y,
    GameKey direction,
    String glyph,
    String label,
    int icon,
  ) => Positioned(
    left: x,
    top: y,
    width: 44,
    height: 44,
    child: Transform.rotate(
      angle: math.pi / 4,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: direction == GameKey.right && battle.game.players.length <= 1
              ? null
              : () => _command(direction),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: battle.icon == icon
                    ? [const Color(0xff526847), _ink]
                    : [const Color(0xf0344c40), const Color(0xff182d29)],
              ),
              border: Border.all(
                color: battle.icon == icon
                    ? const Color(0xfff0da9c)
                    : _gold.withValues(alpha: .65),
                width: battle.icon == icon ? 2 : 1,
              ),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black38,
                  offset: Offset(2, 3),
                  blurRadius: 5,
                ),
              ],
            ),
            child: Transform.rotate(
              angle: -math.pi / 4,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    glyph,
                    style: TextStyle(
                      fontSize: 21,
                      height: 1,
                      color: icon == 4 && battle.game.players.length <= 1
                          ? Colors.white38
                          : _paper,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    style: const TextStyle(fontSize: 10, color: _gold),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

final class _PartyCard extends StatelessWidget {
  const _PartyCard({
    required this.actor,
    required this.active,
    required this.art,
  });
  final GameActor actor;
  final bool active;
  final ModernArt? art;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: active ? const Color(0xff3b5140) : const Color(0xff203d35),
      border: Border.all(
        color: active ? _gold : const Color(0xff60715a),
        width: active ? 1.5 : .7,
      ),
      borderRadius: BorderRadius.circular(3),
    ),
    child: Padding(
      padding: const EdgeInsets.all(5),
      child: Row(
        children: [
          SizedBox(
            width: 49,
            height: 60,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: CustomPaint(
                painter: PortraitPainter(actor.index, actor.name, art),
              ),
            ),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  actor.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 19,
                    height: 1.05,
                    color: actor.alive ? _paper : const Color(0xffa1aaa2),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                _bar('气血', actor.hp, actor.maxHp, const Color(0xff8bb57a)),
                const SizedBox(height: 4),
                _bar('真气', actor.mp, actor.maxMp, const Color(0xff78b9bd)),
              ],
            ),
          ),
        ],
      ),
    ),
  );
  Widget _bar(String label, int current, int max, Color color) => Column(
    children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 14, height: 1, color: _paper),
          ),
          Text(
            '${math.max(0, current)}/$max',
            style: const TextStyle(
              fontSize: 15,
              height: 1,
              color: _paper,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
      const SizedBox(height: 1),
      ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: LinearProgressIndicator(
          value: (current / math.max(1, max)).clamp(0.0, 1.0),
          minHeight: 3,
          color: color,
          backgroundColor: Colors.black38,
        ),
      ),
    ],
  );
}

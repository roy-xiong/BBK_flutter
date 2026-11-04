import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'game_view_model.dart';
import '../engine/game_engine.dart';

/// 标题页直接反映原状态机的选择位置；键盘、鼠标与触屏使用同一份选中状态。
/// 紧凑布局适应手机游戏区，不新增定时器或独立的焦点状态副本。
final class ModernTitleMenu extends StatelessWidget {
  const ModernTitleMenu({super.key, required this.model});
  final GameViewModel model;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final game = model.engine;
      if (game == null) return const SizedBox.shrink();
      final compact = bounds.maxHeight < 280;
      bool active() =>
          identical(game, model.engine) &&
          game.menus.isEmpty &&
          (game.screen == 'intro' || game.screen == 'title');
      void select(int index) {
        if (active() && game.titleSelection != index) {
          model.action((g) => g.titleSelection = index);
        }
      }

      void choose(int index) {
        if (!active()) return;
        model.action((g) {
          g.titleSelection = index;
          if (index == 0) {
            g.startNewGame();
          } else {
            g.openSaveMenu(load: true);
          }
        });
      }

      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '伏 魔 记',
                style: TextStyle(
                  color: const Color(0xffece3cb),
                  fontSize: compact ? 28 : 44,
                  letterSpacing: 8,
                  fontWeight: FontWeight.w700,
                  shadows: const [
                    Shadow(
                      color: Colors.black,
                      blurRadius: 12,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '一剑入尘世 · 再续旧时缘',
                style: TextStyle(
                  color: const Color(0xffd8b875),
                  fontSize: compact ? 10 : 12,
                  letterSpacing: compact ? 1 : 3,
                ),
              ),
              SizedBox(height: compact ? 12 : 24),
              for (var index = 0; index < 2; index++) ...[
                if (index > 0) const SizedBox(height: 8),
                SizedBox(
                  width: math.min(
                    compact ? 220 : 264,
                    math.max(0, bounds.maxWidth - 24),
                  ),
                  height: compact ? 36 : 48,
                  child: Semantics(
                    button: true,
                    selected: game.titleSelection == index,
                    label: index == 0 ? '新的故事' : '继续故事',
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      onEnter: (_) => select(index),
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => choose(index),
                        child: DecoratedBox(
                          key: ValueKey(
                            'fmj-title-${game.titleSelection == index ? 'selected' : 'unselected'}-$index',
                          ),
                          decoration: BoxDecoration(
                            color: game.titleSelection == index
                                ? const Color(0xffe5c680)
                                : const Color(0xf21a302d),
                            borderRadius: BorderRadius.circular(7),
                            border: Border.all(
                              color: game.titleSelection == index
                                  ? const Color(0xffffe1a1)
                                  : const Color(0xff8b8468),
                              width: game.titleSelection == index ? 2 : 1,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 22,
                                  child: game.titleSelection == index
                                      ? const Icon(
                                          Icons.chevron_right,
                                          color: Color(0xff172622),
                                          size: 23,
                                        )
                                      : null,
                                ),
                                Expanded(
                                  child: Text(
                                    index == 0 ? '新的故事' : '继续故事',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: game.titleSelection == index
                                          ? const Color(0xff172622)
                                          : const Color(0xffece3cb),
                                      fontSize: compact ? 14 : 16,
                                      fontWeight: game.titleSelection == index
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                      letterSpacing: 2,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 22),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
}

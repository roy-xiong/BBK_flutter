import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'dart:async';
import 'modern_scene.dart';
import 'modern_art.dart';
import 'modern_battle_hud.dart';
import 'dialogue_presentation.dart';
import '../engine/game_engine.dart';
import '../engine/game_actor.dart';
import 'game_view_model.dart';
import 'goods_icon.dart';

const _gold = Color(0xffd8b875), _paper = Color(0xffece3cb);

/// 场景与信息栏使用独立布局区域，显示地点与角色信息时不覆盖地图像素。
final class ModernGameView extends StatelessWidget {
  const ModernGameView({super.key, required this.model});
  final GameViewModel model;

  /// 高度只取决于窗口宽度；战斗、菜单及队伍人数变化不能挤动地图或操作区。
  /// 固定预留地点栏和三名队员的单行摘要，GamePage 复用同一尺寸计算。
  static double informationHeight(double width) => width < 960 ? 56 : 64;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final game = model.engine;
      if (game == null) return const SizedBox.shrink();
      final infoHeight = math.min(
        informationHeight(constraints.maxWidth),
        math.max(0.0, constraints.maxHeight - 64),
      );
      return Column(
        children: [
          Expanded(
            child: SizedBox.expand(
              key: const ValueKey('modern-scene-region'),
              child: _ModernSceneView(model: model),
            ),
          ),
          SizedBox(
            height: infoHeight,
            width: double.infinity,
            child: _WorldInformation(game: game),
          ),
        ],
      );
    },
  );
}

/// 只读状态摘要；剧情与战斗继续由原会话驱动，不额外覆盖或修改场景。
final class _WorldInformation extends StatelessWidget {
  const _WorldInformation({required this.game});
  final GameEngine game;
  @override
  Widget build(BuildContext context) {
    final battle = game.battle;
    final location = game.sceneName.isNotEmpty
        ? game.sceneName
        : game.map?.name ?? '伏魔记';
    return DecoratedBox(
      key: const ValueKey('world-information-band'),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xff203e38), Color(0xff132c2b)],
        ),
        border: Border(top: BorderSide(color: Color(0xff997e4f))),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final members = game.players;
          final font = constraints.maxWidth < 960 ? 10.5 : 12.0;
          Widget line(String text, {Color color = _paper}) => FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              text,
              maxLines: 1,
              style: TextStyle(
                color: color,
                fontSize: font,
                fontWeight: FontWeight.w400,
                height: 1,
              ),
            ),
          );
          Widget member(GameActor p) {
            final chain = game.data.record(12, 2, p.index);
            final maxLevel = chain?.byte(2) ?? p.level;
            final next = p.level < maxLevel
                ? chain?.word(4 + (p.level - 1) * 20 + 14)
                : null;
            final experience = next == null
                ? '经验 ${p.exp}（满级）'
                : '经验 ${p.exp}/$next';
            return KeyedSubtree(
              key: ValueKey('world-member-${p.index}'),
              child: line(
                '${p.name}  Lv.${p.level}   气血 ${p.hp}/${p.maxHp}   '
                '魔法 ${p.mp}/${p.maxMp}   $experience',
              ),
            );
          }

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.place_outlined, size: 13, color: _gold),
                    const SizedBox(width: 4),
                    Expanded(child: line(location, color: _gold)),
                    if (battle != null) line('战斗 · 第 ${battle.round + 1} 回合'),
                  ],
                ),
                // 留空的队员行同样占位，入队、离队、战斗和菜单均保持相同几何布局。
                for (var i = 0; i < 3; i++)
                  Expanded(
                    child: i < members.length
                        ? member(members[i])
                        : const SizedBox.expand(),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// 新版只消费同一会话的状态与输入命令；场景投影不参与碰撞或剧情判断。
final class _ModernSceneView extends StatelessWidget {
  const _ModernSceneView({required this.model});
  final GameViewModel model;
  @override
  Widget build(BuildContext context) {
    if (model.modernArt == null) unawaited(model.prepareModernArt());
    final game = model.engine;
    if (game == null) return const SizedBox.shrink();
    if (model.modernArt == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (model.modernArtError == null)
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2, color: _gold),
              ),
            const SizedBox(height: 12),
            Text(
              model.modernArtError == null ? '正在载入画面' : '画面载入失败，可切回经典继续游戏',
              style: const TextStyle(color: _paper, fontSize: 12),
            ),
          ],
        ),
      );
    }
    final op = game.operation, battle = game.battle;
    final menu = game.menus.isEmpty ? null : game.menus.last;
    final targetEntries =
        battle?.targets
            .asMap()
            .entries
            .where(
              (e) =>
                  e.value.visible &&
                  (e.value.alive ||
                      battle.targetKind == 'help' ||
                      battle.targetKind == 'item'),
            )
            .toList() ??
        [];
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 260;
        return ClipRect(
          child: Stack(
            fit: StackFit.expand,
            children: [
              RepaintBoundary(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (details) =>
                      model.tapMap(details.localPosition, constraints.biggest),
                  child: CustomPaint(
                    painter: ModernScenePainter(
                      game,
                      model.modernArt,
                      revision: model.sceneRevision,
                      textStyle: DefaultTextStyle.of(context).style,
                    ),
                  ),
                ),
              ),
              if (battle != null)
                Positioned.fill(
                  child: ModernBattleHud(
                    model: model,
                    battle: battle,
                    art: model.modernArt,
                  ),
                ),
              if (game.screen == 'intro' || game.screen == 'title')
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        '伏 魔 记',
                        style: TextStyle(
                          color: _paper,
                          fontSize: 44,
                          letterSpacing: 8,
                          fontWeight: FontWeight.w700,
                          shadows: [
                            Shadow(
                              color: Colors.black,
                              blurRadius: 12,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        '一剑入尘世 · 再续旧时缘',
                        style: TextStyle(
                          color: _gold,
                          fontSize: 12,
                          letterSpacing: 3,
                        ),
                      ),
                      const SizedBox(height: 24),
                      _MenuButton(
                        '新的故事',
                        () => model.action((g) {
                          if (g.screen == 'intro' || g.screen == 'title') {
                            g.startNewGame();
                          }
                        }),
                      ),
                      const SizedBox(height: 8),
                      _MenuButton(
                        '继续故事',
                        () => model.action((g) {
                          if ((g.screen == 'intro' || g.screen == 'title') &&
                              g.menus.isEmpty) {
                            g.openSaveMenu(load: true);
                          }
                        }),
                      ),
                    ],
                  ),
                ),
              if (op != null && op.kind == 'dialogue')
                Positioned(
                  left: compact ? 8 : 14,
                  right: compact ? 8 : 14,
                  bottom: compact ? 8 : 14,
                  child: GestureDetector(
                    onTap: () => model.press(GameKey.confirm),
                    child: _Dialogue(
                      game: game,
                      compact: compact,
                      art: model.modernArt,
                      scale: (constraints.maxWidth / 640).clamp(1.0, 1.6),
                    ),
                  ),
                ),
              if (op != null && (op.kind == 'message' || op.kind == 'timed'))
                Center(
                  child: GestureDetector(
                    onTap: () => model.press(GameKey.confirm),
                    child: _Plaque(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          op.text,
                          style: const TextStyle(color: _paper, fontSize: 15),
                        ),
                      ),
                    ),
                  ),
                ),
              if (op != null && (op.kind == 'choice' || op.kind == 'menu'))
                Center(
                  child: _ChoicePanel(
                    title: '请作选择',
                    maxHeight: constraints.maxHeight * .8,
                    items: op.options,
                    selected: op.selected,
                    onTap: (i) =>
                        model.action((g) => g.choose(i, expected: op)),
                  ),
                ),
              if (menu != null)
                Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: constraints.maxWidth * .85,
                      maxHeight: constraints.maxHeight * .9,
                    ),
                    child: _NativeMenu(
                      game: game,
                      menu: menu,
                      model: model,
                      scale: (constraints.maxWidth / 640).clamp(1.0, 1.6),
                      maxHeight: constraints.maxHeight * .9,
                    ),
                  ),
                ),
              if (battle != null &&
                  battle.phase == 'select' &&
                  battle.targetKind.isNotEmpty &&
                  menu == null &&
                  op == null)
                Center(
                  child: _ChoicePanel(
                    title: '选择目标',
                    maxHeight: constraints.maxHeight * .65,
                    items: targetEntries.map((e) => e.value.name).toList(),
                    selected: targetEntries.indexWhere(
                      (e) => e.key == battle.targetIndex,
                    ),
                    onTap: (i) => model.action((g) {
                      if (!identical(g.battle, battle) ||
                          battle.phase != 'select' ||
                          battle.targetKind.isEmpty ||
                          i < 0 ||
                          i >= targetEntries.length ||
                          g.operation != null ||
                          g.menus.isNotEmpty) {
                        return;
                      }
                      final entry = targetEntries[i];
                      if (!identical(
                        battle.targets.elementAtOrNull(entry.key),
                        entry.value,
                      )) {
                        return;
                      }
                      battle.targetIndex = entry.key;
                      battle.key(GameKey.confirm, false);
                    }),
                  ),
                ),
              if (battle != null && battle.phase == 'win')
                Center(
                  child: _Plaque(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            '战斗胜利',
                            style: TextStyle(color: _gold, fontSize: 23),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '获得经验 ${battle.totalExp} · 金钱 ${battle.totalMoney}',
                            style: const TextStyle(color: _paper),
                          ),
                          if (battle.victoryShown.length > 2) ...[
                            const SizedBox(height: 7),
                            Text(
                              battle.victoryShown.last.kind == 'learn'
                                  ? '${battle.victoryShown.last.text}领悟 ${battle.victoryShown.last.detail}'
                                  : battle.victoryShown.last.text,
                              style: const TextStyle(
                                color: _gold,
                                fontSize: 12,
                              ),
                            ),
                            if (battle.victoryShown.last.kind == 'level')
                              Text(
                                [
                                  for (
                                    var i = 0;
                                    i < battle.victoryShown.last.rows.length;
                                    i++
                                  )
                                    '${['生命', '真气', '攻击', '防御', '身法', '灵力', '幸运'][i]} ${battle.victoryShown.last.rows[i].last}',
                                ].join('  '),
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: _paper,
                                  fontSize: 11,
                                ),
                              ),
                          ],
                          const SizedBox(height: 12),
                          _MenuButton(
                            '继续',
                            () => model.action((g) {
                              if (identical(g.battle, battle) &&
                                  battle.phase == 'win') {
                                g.press(GameKey.confirm);
                              }
                            }),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (op?.kind == 'credits')
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(30),
                    child: SingleChildScrollView(
                      child: Text(
                        op?.text ?? '',
                        style: const TextStyle(
                          color: _paper,
                          height: 1.7,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

final class _Plaque extends StatelessWidget {
  const _Plaque({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xf2473c32), Color(0xfa252e2d), Color(0xfa162c2c)],
      ),
      border: Border.all(color: _gold.withValues(alpha: .7)),
      borderRadius: BorderRadius.circular(8),
      boxShadow: const [
        BoxShadow(color: Colors.black38, blurRadius: 10, offset: Offset(0, 3)),
      ],
    ),
    child: Container(
      margin: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        border: Border.all(color: _gold.withValues(alpha: .2)),
        borderRadius: BorderRadius.circular(4),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: child,
    ),
  );
}

final class _MenuButton extends StatelessWidget {
  const _MenuButton(this.label, this.onTap);
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: _Plaque(
      child: Text(
        label,
        style: const TextStyle(color: _paper, fontSize: 13, letterSpacing: 2),
      ),
    ),
  );
}

final class _ChoicePanel extends StatelessWidget {
  const _ChoicePanel({
    required this.title,
    required this.items,
    required this.selected,
    required this.onTap,
    this.maxHeight = 280,
  });
  final double maxHeight;
  final String title;
  final List<String> items;
  final int selected;
  final ValueChanged<int> onTap;
  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(maxHeight: maxHeight),
    child: _Plaque(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: const TextStyle(color: _gold, fontSize: 12)),
            const SizedBox(height: 7),
            for (var i = 0; i < items.length; i++)
              InkWell(
                onTap: () => onTap(i),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
                  child: Text(
                    '${i == selected ? '◆  ' : '    '}${items[i]}',
                    style: TextStyle(
                      color: i == selected ? _gold : _paper,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

final class _Dialogue extends StatelessWidget {
  const _Dialogue({
    required this.game,
    required this.compact,
    required this.art,
    this.scale = 1,
  });
  final double scale;
  final ModernArt? art;
  final GameEngine game;
  final bool compact;
  @override
  Widget build(BuildContext context) {
    final op = game.operation;
    if (op == null) return const SizedBox.shrink();
    final head = op.args.isNotEmpty ? op.args.first : 0;
    final dialogue = DialoguePresentation.from(game, op);
    final actor = dialogue.speaker;
    final text = dialogue.text;
    return _Plaque(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (head >= 1 && head <= 3)
            SizedBox(
              width: (compact ? 62 : 82) * scale,
              height: (compact ? 78 : 108) * scale,
              child: CustomPaint(
                painter: PortraitPainter(head, actor ?? '', art),
              ),
            ),
          if (head >= 1 && head <= 3) const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (actor != null) ...[
                  Text(
                    actor,
                    style: const TextStyle(
                      color: _gold,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 7),
                ],
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: (compact ? 72 : 116) * scale,
                  ),
                  child: SingleChildScrollView(
                    child: Text(
                      text,
                      style: TextStyle(
                        color: _paper,
                        fontSize: (compact ? 12 : 14) * scale,
                        height: 1.5,
                      ),
                    ),
                  ),
                ),
                const Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    '轻触继续  ▾',
                    style: TextStyle(color: _gold, fontSize: 10),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 新版只消费原菜单对象和回调，完整展示原属性、物品说明、数量和价格。
final class _NativeMenu extends StatefulWidget {
  const _NativeMenu({
    required this.game,
    required this.menu,
    required this.model,
    this.scale = 1,
    required this.maxHeight,
  });
  final GameEngine game;
  final GameMenu menu;
  final GameViewModel model;
  final double scale;
  final double maxHeight;
  @override
  State<_NativeMenu> createState() => _NativeMenuState();
}

final class _NativeMenuState extends State<_NativeMenu> {
  final ScrollController _scroll = ScrollController(),
      _details = ScrollController();
  GameMenu? _observed;
  int _selected = -1, _page = 0, _revision = -1;
  bool get _detailed => ['inventory', 'magic'].contains(widget.menu.kind);
  bool get _compact => widget.maxHeight < 200;
  double get _titleHeight => (_compact ? 24 : 28) * widget.scale;

  /// 每行高度由菜单实际可用高度决定；主菜单四项完整可见，长列表继续滚动。
  double get _extent {
    if (widget.menu.kind == 'state') return 152.0 * widget.scale;
    // 与下方标题、金钱和外框的实际高度保持一致，不能借缩短状态栏隐藏菜单溢出。
    final header =
        _titleHeight +
        18 +
        (widget.menu.kind == 'main' ? 14.4 * widget.scale + 4 : 0);
    final count = widget.menu.kind == 'equipment'
        ? 8
        : widget.menu.items.length;
    final visibleRows = widget.menu.kind == 'main' ? 4 : count.clamp(1, 5);
    return ((widget.maxHeight - header) / visibleRows).clamp(
      18.0,
      42.0 * widget.scale,
    );
  }

  /// 保持按键选中项可见；SELECT/START 只滚动物品说明，不能滚走选中物品后误用。
  void _reveal() {
    final menu = widget.menu;
    final changed =
        !identical(_observed, menu) ||
        _selected != menu.selected ||
        _revision != menu.revision;
    final pageDelta = menu.page - _page;
    if (!changed && pageDelta == 0) return;
    _observed = menu;
    _selected = menu.selected;
    _page = menu.page;
    _revision = menu.revision;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (changed &&
          _scroll.hasClients &&
          _scroll.position.hasContentDimensions) {
        _scroll.jumpTo(
          (menu.selected * _extent).clamp(
            0.0,
            _scroll.position.maxScrollExtent,
          ),
        );
      }
      if (_detailed &&
          _details.hasClients &&
          _details.position.hasContentDimensions) {
        _details.jumpTo(
          (changed ? 0.0 : _details.offset + pageDelta * widget.scale).clamp(
            0.0,
            _details.position.maxScrollExtent,
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    _details.dispose();
    super.dispose();
  }

  String _state(GameActor p) {
    final chain = widget.game.data.record(12, 2, p.index);
    final next = chain != null && p.level <= chain.byte(2)
        ? chain.word(4 + (p.level - 1) * 20 + 14)
        : 0;
    final immunity = [
      for (final bit in [(8, '毒'), (4, '乱'), (2, '封'), (1, '眠')])
        if (p.immunity & bit.$1 != 0) bit.$2,
    ].join('、');
    final status = [
      for (final bit in [(8, '毒'), (4, '乱'), (2, '封'), (1, '眠')])
        if (p.status & bit.$1 != 0) bit.$2,
    ].join('、');
    return '${p.name}  Lv.${p.level}\n生命 ${p.hp}/${p.maxHp}  真气 ${p.mp}/${p.maxMp}\n攻击 ${p.attack}  防御 ${p.defense}\n身法 ${p.speed}  灵力 ${p.spirit}  幸运 ${p.luck}\n经验 ${p.exp}/$next\n免疫 ${immunity.isEmpty ? '无' : immunity}\n状态 ${status.isEmpty ? '正常' : status}';
  }

  @override
  Widget build(BuildContext context) {
    if (widget.menu.purchase != null) {
      return _PurchasePanel(
        game: widget.game,
        menu: widget.menu,
        model: widget.model,
      );
    }
    _reveal();
    final game = widget.game, menu = widget.menu, scale = widget.scale;
    final actor = game.players.elementAtOrNull(menu.actor);
    const slots = ['装饰', '装饰', '护腕', '脚蹬', '手持', '身穿', '肩披', '头戴'];
    final List<String> items;
    if (menu.kind == 'state') {
      items = game.players.map(_state).toList();
    } else if (menu.kind == 'equipment' && actor != null) {
      items = List.generate(8, (i) {
        final id = actor.equipment[i];
        return '${slots[i]}  ${id == null ? '未装备' : game.goodsName(id)}';
      });
    } else if (menu.kind == 'save' || menu.kind == 'load') {
      items = List.generate(
        3,
        (i) => '档位 ${i + 1}  ${game.saves[i]?['scene'] ?? '空档位'}',
      );
    } else {
      items = menu.items;
    }
    final title = switch (menu.kind) {
      'main' => '主菜单',
      'properties' => '属性',
      'goods' => '物品',
      'actors' => '选择人物',
      'state' => '人物状态',
      'equipment' => '${actor?.name ?? ''} · 穿戴',
      'equipment-action' => '穿戴操作',
      'magic' => '魔法',
      'inventory' => switch (menu.mode) {
        'buy' => '购买物品',
        'sell' => '出售物品',
        'equip' => '选择装备',
        'throw' => '选择投掷物',
        _ => '使用物品',
      },
      'save' => '存储进度',
      'load' => '读入进度',
      'system' => '系统',
      'battle-misc' => '战斗策略',
      'battle-goods' => '战斗物品',
      _ => '菜单',
    };
    // 菜单位于游戏画布的 ColoredBox 之上，需要自己的 Material 承接选中底色和水波纹。
    Widget list() => Material(
      type: MaterialType.transparency,
      child: ListView.builder(
        controller: _scroll,
        shrinkWrap: true,
        itemExtent: _extent,
        itemCount: items.length,
        itemBuilder: (context, i) {
          final expectedId = menu.ids.elementAtOrNull(i);
          final goodsId = menu.kind == 'inventory'
              ? expectedId
              : menu.kind == 'equipment'
              ? actor?.equipment.elementAtOrNull(i)
              : null;
          return ListTile(
            dense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 8 * scale),
            minVerticalPadding: 0,
            minTileHeight: _extent,
            visualDensity: VisualDensity.compact,
            selected: i == menu.selected,
            selectedTileColor: _gold.withValues(alpha: .14),
            leading: menu.kind == 'state' && i < game.players.length
                ? SizedBox(
                    width: 44 * scale,
                    height: 56 * scale,
                    child: CustomPaint(
                      painter: PortraitPainter(
                        game.players[i].index,
                        game.players[i].name,
                        widget.model.modernArt,
                      ),
                    ),
                  )
                : goodsId == null
                ? null
                : GoodsIcon(
                    key: ValueKey('menu-goods-$goodsId'),
                    id: goodsId,
                    art: widget.model.modernArt,
                    size: math.min(_extent - 2, 32 * scale),
                  ),
            minLeadingWidth: goodsId == null ? null : 20,
            horizontalTitleGap: 5 * scale,
            title: Text(
              items[i],
              maxLines: menu.kind == 'state' ? 7 : 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: _paper,
                fontSize: 13 * scale,
                height: 1.25,
              ),
            ),
            onTap: () => widget.model.action((g) {
              g.selectMenu(menu, i, expectedId: expectedId);
            }),
          );
        },
      ),
    );
    Widget body() {
      if (!_detailed) return list();
      final id = menu.ids.elementAtOrNull(menu.selected);
      final record = id == null
          ? null
          : menu.kind == 'magic'
          ? game.magic(id)
          : game.goods(id);
      final description = record == null
          ? ''
          : record.text(menu.kind == 'magic' ? 26 : 30);
      final meta = record == null
          ? ''
          : menu.kind == 'magic'
          ? '耗真气：${record.byte(4)}'
          : '价格：${menu.mode == 'buy' ? record.word(18) : record.word(20)}\n${menu.mode == 'buy' ? '金钱：${game.money}' : '数量：${game.inventory[id] ?? 0}'}';
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(flex: 2, child: list()),
          VerticalDivider(
            width: 14 * scale,
            color: _gold.withValues(alpha: .35),
          ),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (id != null && menu.kind == 'inventory') ...[
                      GoodsIcon(
                        id: id,
                        art: widget.model.modernArt,
                        size: (_compact ? 24 : 30) * scale,
                      ),
                      SizedBox(width: 5 * scale),
                    ],
                    Expanded(
                      child: Text(
                        id == null
                            ? ''
                            : menu.kind == 'magic'
                            ? game.magicName(id)
                            : game.goodsName(id),
                        style: TextStyle(
                          color: _gold,
                          fontSize: 13 * scale,
                          fontWeight: FontWeight.w600,
                          height: 1.2,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: (_compact ? 3 : 4) * scale),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _compact ? meta.replaceAll('\n', '  ') : meta,
                    style: TextStyle(
                      color: _paper,
                      fontSize: 10.5 * scale,
                      height: 1.25,
                    ),
                  ),
                ),
                SizedBox(height: (_compact ? 3 : 5) * scale),
                Expanded(
                  child: SingleChildScrollView(
                    controller: _details,
                    child: Text(
                      description,
                      style: TextStyle(
                        color: const Color(0xffcec6ac),
                        fontSize: 12 * scale,
                        height: 1.3,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return _Plaque(
      child: SizedBox(
        width: (_detailed ? 400 : 320) * scale,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _gold,
                      letterSpacing: 1,
                      fontSize: 14 * scale,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  constraints: BoxConstraints.tightFor(
                    width: 28 * scale,
                    height: _titleHeight,
                  ),
                  padding: EdgeInsets.zero,
                  onPressed: () => widget.model.action((g) {
                    if (identical(g.menus.lastOrNull, menu)) {
                      g.press(GameKey.cancel);
                    }
                  }),
                  icon: Icon(Icons.close, size: 18 * scale, color: _paper),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            if (menu.kind == 'main')
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '金钱：${game.money}',
                    style: TextStyle(
                      color: _paper,
                      fontSize: 12 * scale,
                      height: 1.2,
                    ),
                  ),
                ),
              ),
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  menu.kind == 'magic' ? '没有法术' : '没有物品',
                  style: TextStyle(color: _paper, fontSize: 13 * scale),
                ),
              )
            else
              Flexible(child: body()),
          ],
        ),
      ),
    );
  }
}

/// 使用同一引擎购买会话；关闭、B键和取消均不扣钱，触屏确认与A键共用提交入口。
final class _PurchasePanel extends StatelessWidget {
  const _PurchasePanel({
    required this.game,
    required this.menu,
    required this.model,
  });
  final GameEngine game;
  final GameMenu menu;
  final GameViewModel model;

  @override
  Widget build(BuildContext context) {
    final purchase = menu.purchase;
    if (purchase == null) return const SizedBox.shrink();
    final verb = purchase.selling ? '出售' : '购买';
    void cancel() => model.action((g) => g.selectMenu(menu, 1));
    return Material(
      type: MaterialType.transparency,
      child: _Plaque(
        child: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '$verb数量',
                      style: const TextStyle(color: _gold, fontSize: 16),
                    ),
                  ),
                  SizedBox.square(
                    dimension: 28,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      tooltip: '取消$verb',
                      onPressed: cancel,
                      icon: const Icon(Icons.close, size: 20, color: _paper),
                    ),
                  ),
                ],
              ),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          GoodsIcon(
                            id: purchase.id,
                            art: model.modernArt,
                            size: 32,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              game.goodsName(purchase.id),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: _paper,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          Text(
                            '已有 ${game.inventory[purchase.id] ?? 0}',
                            style: const TextStyle(color: _paper, fontSize: 11),
                          ),
                        ],
                      ),
                      Wrap(
                        spacing: 16,
                        runSpacing: 2,
                        children: [
                          Text(
                            '单价：${purchase.unitPrice}',
                            style: const TextStyle(color: _paper, fontSize: 12),
                          ),
                          Text(
                            '总价：${purchase.total}',
                            style: const TextStyle(color: _gold, fontSize: 12),
                          ),
                          Text(
                            '${purchase.selling ? '出售后金钱' : '剩余金钱'}：${game.money + (purchase.selling ? purchase.total : -purchase.total)}',
                            style: const TextStyle(color: _paper, fontSize: 12),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(
                height: 36,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      tooltip: '减少$verb数量',
                      padding: EdgeInsets.zero,
                      onPressed: purchase.quantity == 0
                          ? null
                          : () => model.action(
                              (g) => g.changePurchaseQuantity(menu, -1),
                            ),
                      icon: const Icon(Icons.remove, size: 22, color: _paper),
                    ),
                    SizedBox(
                      width: 66,
                      child: Text(
                        '${purchase.quantity}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: _gold, fontSize: 21),
                      ),
                    ),
                    IconButton(
                      tooltip: '增加$verb数量',
                      padding: EdgeInsets.zero,
                      onPressed: purchase.quantity >= purchase.limit
                          ? null
                          : () => model.action(
                              (g) => g.changePurchaseQuantity(menu, 1),
                            ),
                      icon: const Icon(Icons.add, size: 22, color: _paper),
                    ),
                    Text(
                      ' / ${purchase.limit}',
                      style: const TextStyle(color: _paper, fontSize: 11),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 32,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(onPressed: cancel, child: const Text('取消')),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: purchase.quantity == 0
                          ? null
                          : () => model.action((g) => g.selectMenu(menu, 0)),
                      child: Text('确认$verb'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../domain/models/game_battle.dart';
import '../../../../domain/use_cases/strategy_commands.dart';
import '../../../../engine/core/native_game_session.dart';
import '../../../../engine/rendering/cartoon_assets.dart';
import '../../../../engine/rendering/cartoon_scene_art.dart';
import '../view_models/game_view_model.dart';

/// 与游戏画布分开的信息卡，窄屏放下方、宽屏放右侧，文字使用系统组件排版。
final class CartoonStatusPanel extends StatelessWidget {
  const CartoonStatusPanel({
    super.key,
    required this.viewModel,
    this.compact = false,
  });
  final GameViewModel viewModel;
  final bool compact;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: viewModel.sceneRevision,
    builder: (context, _) {
      final session = viewModel.session,
          assets = viewModel.cartoonAssets,
          world = session?.world;
      if (session == null || assets == null || world == null) {
        return const SizedBox.shrink();
      }
      final battle = session.activeBattle;
      final cityId = session.renderer.selectedCity(world);
      final city = cityId == null ? null : world.city(cityId);
      final slot = battle?.unitAt(battle.focusX, battle.focusY);
      final visible =
          slot != null && !(slot >= 10 && battle!.units[slot].state == 7);
      final person = visible
          ? battle!.people[slot]
          : city?.satrapId != null && city!.satrapId > 0
          ? city.satrapId - 1
          : world.playerRulerIndex;
      final p = person == null ? null : world.person(person);
      final friendly = battle != null
          ? slot == null || slot < 10
          : city == null || city.belong == (world.playerRulerIndex ?? -1) + 1;
      final color = friendly ? CartoonSceneArt.red : CartoonSceneArt.blue;
      final title = battle != null
          ? (visible
                ? session.resources.personName(world.period, person ?? -1)
                : '战场情报')
          : cityId == null
          ? '山河形势'
          : session.resources.cityName(cityId);
      final items = <String>[
        if (battle != null) ...[
          if (visible)
            '${friendly ? '我军' : '敌军'} · ${session.resources.text(64, 17 + StrategyTypes.type(session, person))}',
          if (visible) '兵力  ${p?.arms ?? 0}',
          if (visible)
            '生命 ${battle.units[slot].hp}   技力 ${battle.units[slot].mp}',
          '我军粮草  ${battle.playerFood}',
          '第 ${battle.day} 日',
        ] else if (city != null) ...[
          '人口  ${city.population}',
          '钱粮  ${city.money} / ${city.food}',
          '驻将  ${world.personsInCity(cityId!, belong: city.belong).length}',
          '民忠  ${city.peopleDevotion}',
        ] else ...[
          '${world.year}年 ${world.month}月',
          '点击城池查看信息',
        ],
      ];
      final face = person == null
          ? const SizedBox.shrink()
          : AspectRatio(
              aspectRatio: .8,
              child: CustomPaint(
                painter: _PortraitPainter(assets, world.period, person),
              ),
            );
      final words = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: compact ? 18 : 23,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
          const SizedBox(height: 8),
          for (final text in items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Text(
                text,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: compact ? 13 : 16,
                  color: const Color(0xff273940),
                ),
              ),
            ),
        ],
      );
      return Container(
        margin: const EdgeInsets.all(8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xffeee8d7),
          border: Border.all(color: color.withValues(alpha: .6)),
          borderRadius: BorderRadius.circular(14),
        ),
        child: compact
            ? Row(
                children: [
                  SizedBox(width: 72, height: 96, child: face),
                  const SizedBox(width: 12),
                  Expanded(child: words),
                ],
              )
            : SingleChildScrollView(
                child: Column(
                  children: [
                    SizedBox(height: 205, child: face),
                    const SizedBox(height: 16),
                    words,
                  ],
                ),
              ),
      );
    },
  );
}

/// 装备生效后的兵种，信息卡与战场使用同一规则入口。
abstract final class StrategyTypes {
  static int type(NativeGameSession session, int? person) {
    final world = session.world,
        p = person == null ? null : session.world?.person(person);
    if (world == null || p == null) return 0;
    return StrategyCommands(session.resources).armType(world, p);
  }
}

final class _PortraitPainter extends CustomPainter {
  const _PortraitPainter(this.assets, this.period, this.person);
  final CartoonAssets assets;
  final int period, person;
  @override
  void paint(Canvas canvas, Size size) => assets.portrait(
    canvas,
    Offset.zero & size,
    period: period,
    person: person,
  );
  @override
  bool shouldRepaint(_PortraitPainter old) =>
      old.period != period ||
      old.person != person ||
      !identical(old.assets, assets);
}

/// 左上角战场形势卡。收起时让出视野，只显示规则允许获知的位置与兵力。
final class CartoonBattleOverview extends StatefulWidget {
  const CartoonBattleOverview({super.key, required this.viewModel});
  final GameViewModel viewModel;
  @override
  State<CartoonBattleOverview> createState() => _OverviewState();
}

class _OverviewState extends State<CartoonBattleOverview> {
  bool expanded = false;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.viewModel.sceneRevision,
    builder: (context, _) {
      final session = widget.viewModel.session,
          battle = session?.activeBattle,
          world = session?.world;
      if (session?.scene != NativeScene.battle ||
          battle == null ||
          world == null) {
        return const SizedBox.shrink();
      }
      var count = 0, arms = 0;
      for (var i = 10; i < 20; i++) {
        final unit = battle.units[i], person = battle.people[i];
        if (person == null || unit.state == 8 || unit.state == 7) continue;
        count++;
        arms += world.person(person)?.arms ?? 0;
      }
      return Material(
        color: const Color(0xeb14292f),
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              onTap: () => setState(() => expanded = !expanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '敌军示意',
                        style: TextStyle(
                          color: const Color(0xff88d5dc),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Icon(
                      expanded ? Icons.expand_less : Icons.expand_more,
                      size: 18,
                      color: const Color(0xffeee8d7),
                    ),
                  ],
                ),
              ),
            ),
            if (expanded) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 7),
                child: AspectRatio(
                  aspectRatio: 1.7,
                  child: CustomPaint(
                    painter: _OverviewPainter(
                      battle,
                      widget.viewModel.sceneRevision.value,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(6),
                child: Text(
                  '$count 将 · $arms 兵',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xffe5ddc8),
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    },
  );
}

final class _OverviewPainter extends CustomPainter {
  const _OverviewPainter(this.battle, this.revision);
  final GameBattle battle;
  final int revision;
  @override
  void paint(Canvas canvas, Size size) {
    if (battle.width <= 0 || battle.height <= 0) return;
    final sx = size.width / battle.width, sy = size.height / battle.height;
    final paint = Paint()..isAntiAlias = false;
    for (var y = 0; y < battle.height; y++) {
      for (var x = 0; x < battle.width; x++) {
        final t = battle.terrain(x, y);
        paint.color = t == 7
            ? const Color(0xff75a9ae)
            : t == 2 || t == 3
            ? const Color(0xff617b62)
            : const Color(0xffaab18a);
        canvas.drawRect(Rect.fromLTWH(x * sx, y * sy, sx + .1, sy + .1), paint);
      }
    }
    paint.isAntiAlias = true;
    for (var i = 0; i < 20; i++) {
      final unit = battle.units[i];
      if (unit.state == 8 ||
          battle.people[i] == null ||
          (i >= 10 && unit.state == 7)) {
        continue;
      }
      final at = Offset((unit.x + .5) * sx, (unit.y + .5) * sy);
      paint.color = i < 10 ? CartoonSceneArt.red : CartoonSceneArt.blue;
      if (i < 10) {
        canvas.drawCircle(at, 2, paint);
      } else {
        canvas.drawPath(
          Path()
            ..moveTo(at.dx, at.dy - 2.5)
            ..lineTo(at.dx + 2.2, at.dy + 2)
            ..lineTo(at.dx - 2.2, at.dy + 2)
            ..close(),
          paint,
        );
      }
    }
    paint
      ..color = const Color(0xffead8a3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = .8;
    canvas.drawRect(
      Rect.fromLTWH(
        battle.viewX * sx,
        battle.viewY * sy,
        math.min(15, battle.width - battle.viewX) * sx,
        math.min(8, battle.height - battle.viewY) * sy,
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(_OverviewPainter old) =>
      old.revision != revision || !identical(old.battle, battle);
}

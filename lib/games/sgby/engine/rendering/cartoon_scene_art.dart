import 'dart:math' as math;
import 'dart:ui' as ui;

import '../core/baye_movie_player.dart';
import 'game_art.dart';
import 'defeat_art.dart';

/// 手绘场景的语义化插画。只消费当前原生状态和动画帧，不修改规则或随机数。
///
/// 插画全部绘制在调用方给定的原版区域内；颜色、动作相位、异常状态和通知
/// 类型均显式传入，避免将不同的资源统一替换成无法辨认的占位圆圈。
final class CartoonSceneArt {
  CartoonSceneArt(this.art, {this.terrain = 0});
  final GameArt art;
  final int terrain;
  ui.Canvas get canvas => art.canvas;
  static const red = ui.Color(0xffb44337), blue = ui.Color(0xff237985);

  /// 原版fight.h天气顺序：晴、阴、风、雨、冰雹。底栏与大图共用此映射。
  void weather(ui.Rect rect, int type, {bool card = false}) {
    const names = ['晴天', '阴天', '大风', '雨天', '冰雹'];
    final value = type.clamp(0, 4);
    if (card) {
      art.panel(rect);
      canvas.save();
      canvas.clipRRect(
        ui.RRect.fromRectAndRadius(rect, const ui.Radius.circular(3)),
      );
      canvas.drawRect(
        rect.deflate(1),
        ui.Paint()
          ..shader = ui.Gradient.linear(rect.topCenter, rect.bottomCenter, [
            value == 0
                ? const ui.Color(0xffbce9f4)
                : const ui.Color(0xffccd9e3),
            art.paper,
          ]),
      );
      for (var i = 0; i < 5; i++) {
        art.mountain(
          rect.left + rect.width * (.1 + i * .22),
          rect.bottom - 5,
          rect.height / 80,
          i,
        );
      }
      canvas.restore();
      weather(
        ui.Rect.fromLTWH(rect.center.dx - 12, rect.top + 5, 24, 24),
        value,
      );
      art.text(
        names[value],
        ui.Rect.fromLTWH(rect.left, rect.top + 32, rect.width, 18),
        size: 13,
        bold: true,
        align: ui.TextAlign.center,
      );
      return;
    }
    if (art.assets?.sprite(
          canvas,
          'icon/${const ['sun', 'cloud', 'wind', 'rain', 'hail'][value]}',
          rect,
        ) ==
        true) {
      return;
    }
    canvas.save();
    canvas.translate(rect.left, rect.top);
    canvas.scale(rect.width / 24, rect.height / 24);
    if (value == 0) {
      for (var ray = 0; ray < 8; ray++) {
        final a = ray * math.pi / 4;
        canvas.drawLine(
          ui.Offset(12 + math.cos(a) * 8, 12 + math.sin(a) * 8),
          ui.Offset(12 + math.cos(a) * 10, 12 + math.sin(a) * 10),
          art.paint(art.gold, stroke: 1.5),
        );
      }
      canvas.drawCircle(const ui.Offset(12, 12), 5, art.paint(art.gold));
    } else if (value == 2 || value == 4) {
      for (var i = 0; i < 3; i++) {
        final y = 7 + i * 5.0;
        final wind = ui.Path()
          ..moveTo(3 + i % 2 * 3, y)
          ..lineTo(17, y);
        if (value == 2) wind.cubicTo(24, y, 22, y - 6, 19, y - 3);
        canvas.drawPath(
          wind,
          art.paint(blue.withValues(alpha: .8), stroke: 1.6),
        );
      }
    } else {
      canvas.drawCircle(const ui.Offset(9, 11), 5, art.paint(art.paper));
      canvas.drawCircle(const ui.Offset(14, 8), 6, art.paint(art.paper));
      canvas.drawCircle(const ui.Offset(19, 12), 4, art.paint(art.paper));
      art.rounded(const ui.Rect.fromLTWH(4, 11, 19, 5), art.paper, radius: 2);
      canvas.drawLine(
        const ui.Offset(5, 16),
        const ui.Offset(21, 16),
        art.paint(blue.withValues(alpha: .65), stroke: 1),
      );
      if (value == 3) {
        for (var i = 0; i < 3; i++) {
          canvas.drawLine(
            ui.Offset(7 + i * 6, 18),
            ui.Offset(5 + i * 6, 22),
            art.paint(blue, stroke: 1.3),
          );
        }
      } else if (value == 4) {
        for (var i = 0; i < 4; i++) {
          canvas.drawCircle(
            ui.Offset(5 + i * 5, 19 + i % 2 * 2),
            1.3,
            art.paint(blue.withValues(alpha: .8)),
          );
        }
      }
    }
    canvas.restore();
  }

  /// 袋装粮草与稻穗，避免底栏资源图标被误认为城池或高亮区域。
  void supplies(ui.Rect rect) {
    if (art.assets?.sprite(canvas, 'icon/supplies', rect) == true) return;
    canvas.save();
    canvas.translate(rect.left, rect.top);
    canvas.scale(rect.width / 16, rect.height / 16);
    canvas.drawPath(
      ui.Path()
        ..moveTo(5, 4)
        ..lineTo(11, 4)
        ..cubicTo(11, 7, 17, 15, 8, 15)
        ..cubicTo(-1, 15, 5, 7, 5, 4),
      art.paint(const ui.Color(0xffd8b878)),
    );
    canvas.drawLine(
      const ui.Offset(5, 4),
      const ui.Offset(11, 4),
      art.paint(art.outline, stroke: 1),
    );
    canvas.drawLine(
      const ui.Offset(8, 7),
      const ui.Offset(8, 13),
      art.paint(art.paper, stroke: .7),
    );
    for (var i = 0; i < 3; i++) {
      canvas.drawOval(
        ui.Rect.fromLTWH(6, 7 + i * 1.5, 2, 1),
        art.paint(art.paper),
      );
      canvas.drawOval(
        ui.Rect.fromLTWH(8, 7 + i * 1.5, 2, 1),
        art.paint(art.paper),
      );
    }
    canvas.restore();
  }

  /// 交锋、开战、大捷、兵败四类战争插画，始终为下方原版通知文字留出区域。
  void battleNote(
    ui.Rect rect,
    int kind, {
    bool friendly = true,
    bool? opponentFriendly,
  }) {
    final who = friendly ? red : blue,
        opponent = (opponentFriendly ?? !friendly) ? red : blue;
    canvas.save();
    canvas.clipRect(rect);
    if (art.assets?.sprite(
          canvas,
          'scene/${kind < 2
              ? 'field'
              : kind == 2
              ? 'victory'
              : 'defeat'}${kind >= 2 && !friendly ? '/enemy' : ''}',
          rect,
        ) !=
        true) {
      art.rounded(rect, art.land);
    }
    final ground = rect.top + rect.height * .77;
    canvas.drawOval(
      ui.Rect.fromLTWH(rect.left + 3, ground - 3, rect.width - 6, 10),
      art.paint(art.forest.withValues(alpha: .15)),
    );
    if (kind < 2) {
      art.soldier(ui.Rect.fromLTWH(rect.left + 7, ground - 29, 30, 32), 1, who);
      canvas.save();
      canvas.translate(rect.right - 7, ground - 29);
      canvas.scale(-1, 1);
      art.soldier(
        const ui.Rect.fromLTWH(0, 0, 30, 32),
        kind == 0 ? 0 : 4,
        opponent,
      );
      canvas.restore();
      final p = rect.center;
      if (art.assets?.sprite(
            canvas,
            'effect/impact',
            ui.Rect.fromCenter(center: p, width: 19, height: 19),
          ) !=
          true) {
        canvas.drawCircle(p, 5, art.paint(art.gold));
      }
    } else {
      // 布景已包含真正的城楼或败退营地，不再往半空叠一座缩小城池。
      // 胜负仍以原报告语义与系统文字表达，玩家能完整看见场景中的地面和城门。
      art.text(
        kind == 2 ? '捷' : '退',
        ui.Rect.fromLTWH(rect.center.dx - 10, rect.top + 1, 20, 17),
        size: 15,
        bold: true,
        color: kind == 2 ? who : art.outline,
        align: ui.TextAlign.center,
      );
      if (kind == 2) {
        for (var i = 0; i < 10; i++) {
          canvas.drawCircle(
            ui.Offset(rect.left + 5 + i * 8, rect.top + 12 + i % 3 * 9),
            1,
            art.paint(i.isEven ? art.gold : red),
          );
        }
      } else {
        for (var i = 0; i < 3; i++) {
          canvas.drawLine(
            ui.Offset(rect.left + 5 + i * 7, rect.top + 15),
            ui.Offset(rect.left + 1 + i * 7, rect.top + 24),
            art.paint(blue.withValues(alpha: .4), stroke: .8),
          );
        }
      }
    }
    canvas.restore();
  }

  /// 独立交战舞台，使用原130×64区域，原版伤害数字继续叠加在舞台内。
  void arena(
    ui.Rect rect, {
    int source = 1,
    int target = 1,
    double phase = 0,
    bool sourceFriendly = true,
    bool targetFriendly = false,
  }) {
    art.panel(rect);
    canvas.save();
    canvas.clipRRect(
      ui.RRect.fromRectAndRadius(rect.deflate(1), const ui.Radius.circular(2)),
    );
    final scene = terrain == 7 || source == 3 || target == 3
        ? 'river'
        : terrain == 3
        ? 'forest'
        : terrain == 5 || terrain == 6
        ? 'siege'
        : 'field';
    if (art.assets?.sprite(canvas, 'scene/$scene', rect.deflate(1)) != true) {
      canvas.drawRect(
        rect.deflate(1),
        ui.Paint()
          ..shader = ui.Gradient.linear(rect.topCenter, rect.bottomCenter, [
            const ui.Color(0xffd3edf1),
            art.land,
          ]),
      );
    }
    final move = math.sin(phase * math.pi) * 8;
    final pose = phase < .25
        ? 'windup'
        : phase < .70
        ? 'attack'
        : 'idle';
    art.soldier(
      ui.Rect.fromLTWH(rect.left + 13 + move, rect.top + 17, 33, 35),
      source.clamp(0, 5),
      sourceFriendly ? red : blue,
      frame: (phase * 8).floor() % 2,
      pose: pose,
    );
    canvas.save();
    canvas.translate(rect.right - 13 - move, rect.top + 17);
    canvas.scale(-1, 1);
    art.soldier(
      const ui.Rect.fromLTWH(0, 0, 33, 35),
      target.clamp(0, 5),
      targetFriendly ? red : blue,
      frame: (phase * 8).floor() % 2,
      pose: phase > .4 && phase < .8 ? 'hit' : 'idle',
    );
    canvas.restore();
    if (phase > .25 && phase < .85) {
      final center = rect.center;
      final span = 21 + math.sin(phase * math.pi) * 10;
      if (art.assets?.sprite(
            canvas,
            'effect/impact',
            ui.Rect.fromCenter(center: center, width: span, height: span),
            opacity: math.sin(((phase - .25) / .6).clamp(0.0, 1.0) * math.pi),
          ) !=
          true) {
        for (var i = 0; i < 7; i++) {
          final a = i * math.pi * 2 / 7 + phase;
          canvas.drawLine(
            center + ui.Offset(math.cos(a) * 3, math.sin(a) * 3),
            center + ui.Offset(math.cos(a) * 11, math.sin(a) * 11),
            art.paint(art.gold, stroke: 1.4),
          );
        }
      }
    }
    canvas.restore();
  }

  /// 以原资源帧号驱动动作；动画关闭、暂停、倍速继续由原播放器负责。
  void movie(BayeMovieVisual visual, ui.Rect arenaRect) {
    final phase =
        ((visual.frame - visual.first) /
                math.max(1, visual.last - visual.first))
            .clamp(0.0, 1.0);
    if (visual.effect == 'defeat') {
      DefeatArt(art).paint(
        foot: ui.Offset(visual.x + 8.0, visual.y + 15.0),
        type: visual.sourceType ?? 1,
        friendly: visual.sourceFriendly,
        phase: phase,
        water: terrain == 7,
      );
      return;
    }
    if (visual.effect == 'level') {
      final at = ui.Offset(visual.x + 8.0, visual.y + 8.0);
      if (art.assets?.sprite(
            canvas,
            'effect/level',
            ui.Rect.fromCenter(
              center: at,
              width: 14 + phase * 12,
              height: 18 + phase * 14,
            ),
            opacity: 1 - phase * .8,
          ) ==
          true) {
        return;
      }
      canvas.drawCircle(
        at,
        4 + phase * 8,
        art.paint(art.gold.withValues(alpha: 1 - phase * .8), stroke: 1),
      );
      return;
    }
    if (visual.sourceType != null) {
      arena(
        arenaRect,
        source: visual.sourceType!,
        target: visual.targetType ?? 1,
        phase: phase,
        sourceFriendly: visual.sourceFriendly,
        targetFriendly: visual.targetFriendly,
      );
    } else if (visual.resource == 27) {
      final center = ui.Offset(visual.x + 8.0, visual.y + 8.0);
      canvas.drawCircle(center, 4 + phase * 5, art.paint(art.gold, stroke: 1));
      return;
    } else {
      final rect = arenaRect;
      art.panel(rect);
      if (art.assets?.sprite(
            canvas,
            'scene/${terrain == 7
                ? 'river'
                : terrain == 3
                ? 'forest'
                : 'field'}',
            rect.deflate(1),
          ) !=
          true) {
        art.rounded(rect.deflate(1), const ui.Color(0xffe9e6f4));
      }
      art.soldier(
        ui.Rect.fromLTWH(rect.left + 9, rect.top + 20, 28, 30),
        visual.sourceType ?? 5,
        visual.sourceFriendly ? red : blue,
      );
      final center = ui.Offset(rect.center.dx + 15, rect.center.dy + 2);
      // 原版consdef.h：35火、36水、37滚木/礌石、38撞击，不能按编号相邻合并。
      final effect = switch (visual.resource) {
        35 => 'effect/fire',
        36 => 'effect/water',
        37 => visual.label.contains('木') ? 'effect/log' : 'effect/rock',
        38 => 'effect/impact',
        41 => 'unit/${visual.sourceFriendly ? 'friendly' : 'enemy'}/1/stride',
        42 => 'effect/rock',
        43 => 'effect/trap',
        _ => 'effect/mist',
      };
      final color = visual.resource == 35
          ? const ui.Color(0xffe4764c)
          : visual.resource == 36
          ? const ui.Color(0xff4c92b7)
          : const ui.Color(0xff8c79c4);
      final span = 27 + math.sin(phase * math.pi) * 20;
      if (visual.resource == 42) {
        // 石阵按原帧逐步显现石块，石头位置只属于表现层，不创建战场障碍。
        for (var i = 0; i < 5; i++) {
          final angle = i * math.pi * 2 / 5;
          art.assets?.sprite(
            canvas,
            effect,
            ui.Rect.fromCenter(
              center:
                  center + ui.Offset(math.cos(angle) * 13, math.sin(angle) * 8),
              width: 12,
              height: 12,
            ),
            opacity: (.4 + phase * .6).clamp(0.0, 1.0),
          );
        }
      } else if (art.assets?.sprite(
            canvas,
            effect,
            ui.Rect.fromCenter(center: center, width: span, height: span),
            opacity: (.4 + math.sin(phase * math.pi) * .6).clamp(0.0, 1.0),
          ) !=
          true) {
        for (var i = 0; i < 3; i++) {
          canvas.drawCircle(
            center,
            5 + ((phase + i / 3) % 1) * 19,
            art.paint(color.withValues(alpha: .65 - i * .14), stroke: 1.1),
          );
        }
      }
    }
    if (visual.label.isNotEmpty) {
      art.rounded(
        ui.Rect.fromLTWH(
          arenaRect.left + 3,
          arenaRect.top + 2,
          arenaRect.width - 6,
          12,
        ),
        art.paper.withValues(alpha: .9),
        radius: 2,
      );
      art.text(
        visual.label,
        ui.Rect.fromLTWH(
          arenaRect.left + 4,
          arenaRect.top + 2,
          arenaRect.width - 8,
          12,
        ),
        size: 9,
        bold: true,
        align: ui.TextAlign.center,
      );
    }
  }

  /// 八种状态不再只靠同一个紫色圆环；标签与原单位状态一一对应。
  void status(ui.Rect rect, int state) {
    if (state <= 0 || state > 7) return;
    const names = ['', '乱', '禁', '定', '奇', '遁', '石', '隐'];
    const colors = [
      0xff2c5261,
      0xffd79d35,
      0xffa26bc6,
      0xff4a91bd,
      0xff8b74bb,
      0xff439672,
      0xff7a8590,
      0xff5a9c99,
    ];
    final color = ui.Color(colors[state]);
    final badge = ui.Rect.fromLTWH(rect.right - 6.5, rect.top - .2, 6.5, 6.5);
    art.rounded(badge, color, radius: 2);
    art.text(
      names[state],
      badge,
      size: 5.5,
      color: art.paper,
      bold: true,
      align: ui.TextAlign.center,
    );
  }
}

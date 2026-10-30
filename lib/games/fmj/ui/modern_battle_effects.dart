import 'dart:math' as math;
import 'dart:ui';
import '../data/game_data.dart';
import '../engine/game_engine.dart';
import 'modern_battle_layout.dart';
import 'modern_effect_shape.dart';

/// 彩色战斗以连续曲线、多层材质、流光和碎屑重绘原动画，原SRS仍决定时序与落点。
/// 绘制只读取动作和叠帧，不推进伤害、随机数或剧情；不为每一帧生成新纹理。
abstract final class ModernBattleEffects {
  static const _families = <int, String>{
    1: 'heal',
    2: 'blade',
    3: 'throw',
    4: 'seal',
    5: 'aura',
    6: 'claw',
    7: 'fire',
    8: 'palm',
    9: 'seal',
    10: 'blade',
    11: 'heal',
    12: 'blade',
    13: 'blade',
    14: 'seal',
    15: 'blade',
    16: 'curse',
    17: 'blade',
    18: 'blade',
    19: 'fire',
    20: 'threads',
    21: 'blade',
    22: 'blade',
    23: 'blade',
    24: 'blade',
    25: 'fire',
    26: 'fire',
    27: 'fire',
    28: 'thunder',
    29: 'dragon',
    30: 'earth',
    31: 'earth',
    32: 'wind',
    33: 'wind',
    34: 'sound',
    35: 'poison',
    36: 'poison',
    37: 'serpent',
    38: 'fire',
    39: 'dragon',
    40: 'spirit',
    41: 'swarm',
    42: 'swarm',
    43: 'ice',
    44: 'earth',
    45: 'blood',
    46: 'claw',
    47: 'bell',
    48: 'sound',
    49: 'seal',
    50: 'seal',
    51: 'seal',
    52: 'threads',
    53: 'aura',
    54: 'sound',
    55: 'moon',
    56: 'moon',
    57: 'threads',
    201: 'blade',
    202: 'blade',
    203: 'blade',
    204: 'phoenix',
    205: 'swarm',
    240: 'aura',
    241: 'seal',
    242: 'thunder',
    243: 'thunder',
    244: 'ice',
    245: 'spirit',
  };

  /// 包含全部68套战斗SRS及7种状态SRS；同原动画的招式保留自身配色与目标范围。
  static String visualFamily(String id) {
    final parts = id.split(':');
    final type = int.tryParse(parts.first), index = int.tryParse(parts.last);
    if (type == 1) {
      return const {
            240: 'blade',
            241: 'aura',
            242: 'wind',
            243: 'poison',
            244: 'spirit',
            245: 'seal',
            246: 'seal',
          }[index] ??
          'aura';
    }
    return _families[index] ?? 'aura';
  }

  static List<Color> _palette(String name, bool healing, String family) {
    if (healing || family == 'heal') {
      return const [Color(0xfff1ffde), Color(0xff7af1bc), Color(0xff239a94)];
    }
    if (RegExp('雷|电').hasMatch(name) || family == 'thunder') {
      return const [Color(0xfffff7ff), Color(0xffc8bdff), Color(0xff686dd9)];
    }
    if (RegExp('火|焰|朱雀|炎').hasMatch(name) ||
        const {'fire', 'dragon', 'phoenix'}.contains(family)) {
      return const [Color(0xfffff5c9), Color(0xffffb559), Color(0xffe84739)];
    }
    if (family == 'ice') {
      return const [Color(0xffefffff), Color(0xffa7eafa), Color(0xff5a98d4)];
    }
    if (family == 'poison' || family == 'serpent') {
      return const [Color(0xffe7ffd7), Color(0xff9cc777), Color(0xff76598c)];
    }
    if (family == 'blood' || family == 'claw' || family == 'spirit') {
      return const [Color(0xffffdecd), Color(0xffd86d74), Color(0xff754e88)];
    }
    if (family == 'wind' || family == 'threads') {
      return const [Color(0xffecfff4), Color(0xff90d8d2), Color(0xff477eab)];
    }
    return const [Color(0xfffff5dc), Color(0xffe6bf73), Color(0xffa26c45)];
  }

  static void draw(Canvas canvas, GameEngine game, ModernBattleLayout layout) {
    final battle = game.battle, action = game.battle?.current;
    if (battle == null) return;
    if (action != null) {
      if (action.kind == 'attack' &&
          action.targets.isNotEmpty &&
          action.frame >= 2 &&
          action.frame <= 4) {
        final point = layout.point(action.targets.first) + const Offset(0, -55);
        _strike(
          canvas,
          point,
          action.actor.type == 1 ? 1 : -1,
          action.frame / 5,
        );
      }
      if (action.stage == 1 && action.movie != null) {
        GameRecord? record;
        var name = action.kind, all = false;
        final resource = action.resource;
        if (resource != null) {
          final item = action.kind == 'item' || action.kind == 'throw';
          record = item ? game.goods(resource) : game.magic(resource);
          name = item ? game.goodsName(resource) : game.magicName(resource);
          all = item
              ? (record?.byte(28) ?? 0) & 16 != 0
              : (record?.byte(3) ?? 0) & 128 != 0;
        } else if (action.kind == 'coop') {
          final equipment = game.players.firstOrNull?.equipment.firstOrNull;
          final magic = equipment == null
              ? 0
              : game.goods(equipment)?.byte(28) ?? 0;
          record = magic > 0 ? game.magic('1:$magic') : null;
          name = record?.text(6) ?? '合击';
          all = (record?.byte(3) ?? 0) & 128 != 0;
        }
        final healing = action.targets.any(
          (target) => (action.changes[target] ?? 0) > 0,
        );
        final family = visualFamily(action.movie!.id);
        drawMovie(
          canvas,
          action.movie!,
          anchor: action.targets.isEmpty
              ? const Offset(320, 192)
              : layout.point(action.targets.first) + const Offset(0, -48),
          fullScreen: all,
          colors: _palette(name, healing, family),
        );
      }
      for (final raise in battle.visibleRaises) {
        if (raise.showing && raise.delta < 0 && raise.step < 2) {
          _impact(
            canvas,
            layout.raisePoint(raise) + const Offset(0, 18),
            raise.step.toDouble(),
          );
        }
      }
    }
    for (final raise in battle.visibleRaises) {
      if (!raise.showing && raise.movies.isNotEmpty) {
        final family = visualFamily(raise.movies.first.id);
        drawMovie(
          canvas,
          raise.movies.first,
          anchor: layout.raisePoint(raise) + const Offset(0, -32),
          colors: _palette('', raise.delta > 0, family),
        );
      }
    }
  }

  /// 每个活动叠帧使用原坐标和存活时间，形状用连续曲线重建并细化内部材质。
  static void drawMovie(
    Canvas canvas,
    GameMovie movie, {
    required Offset anchor,
    bool fullScreen = false,
    List<Color>? colors,
  }) {
    if (movie.headers.isEmpty) return;
    final first = movie.headers.first, family = visualFamily(movie.id);
    final palette = colors ?? _palette('', false, family);
    for (final item in movie.active) {
      final header = movie.headers[item[0]], index = header[4];
      if (index < 0 || index >= movie.bitmaps.length) continue;
      final bitmap = movie.bitmaps[index].frame(0);
      if (bitmap == null) continue;
      final shape = ModernEffectShape.of(bitmap);
      if (shape.bounds.isEmpty) continue;
      final full = fullScreen || bitmap.width == 160 && bitmap.height == 96;
      const scale = 4.0;
      final origin = full
          ? Offset(header[0] * scale, header[1] * scale)
          : anchor +
                Offset(
                  (header[0] - first[0] - bitmap.width / 2) * scale,
                  (header[1] - first[1] - bitmap.height / 2) * scale,
                );
      final age = header[2] <= 0
          ? 0.0
          : (1 - item[1] / header[2]).clamp(0.0, 1.0);
      final seed =
          (int.tryParse(movie.id.split(':').last) ?? 0) * 13 + item[0] * 7;
      canvas.save();
      canvas.translate(origin.dx, origin.dy);
      canvas.scale(scale);
      final bounds = shape.bounds, p = Paint()..isAntiAlias = true;
      canvas.drawPath(
        shape.path.shift(const Offset(.25, .45)),
        p
          ..color = palette.last.withValues(alpha: .45)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, .65),
      );
      canvas.drawPath(
        shape.path,
        p
          ..color = palette[1].withValues(alpha: .38)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.0),
      );
      p.maskFilter = null;
      p.shader = Gradient.linear(
        bounds.topLeft,
        bounds.bottomRight,
        [palette.first, palette[1], palette.last, palette[1]],
        const [0, .36, .78, 1],
      );
      canvas.drawPath(shape.path, p);
      p.shader = null;
      canvas.drawPath(
        shape.path,
        p
          ..style = PaintingStyle.stroke
          ..strokeWidth = .36
          ..color = palette.first.withValues(alpha: .85)
          ..strokeJoin = StrokeJoin.round,
      );
      p.style = PaintingStyle.fill;
      canvas.save();
      canvas.clipPath(shape.path);
      _surface(canvas, bounds, family, palette, age, seed);
      canvas.restore();
      _ornaments(canvas, shape, family, palette, age, seed);
      canvas.restore();
    }
  }

  static void _surface(
    Canvas canvas,
    Rect r,
    String family,
    List<Color> c,
    double age,
    int seed,
  ) {
    final p = Paint()
      ..isAntiAlias = true
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final flowing = const {
      'fire',
      'dragon',
      'phoenix',
      'wind',
      'poison',
      'spirit',
      'blood',
      'serpent',
    }.contains(family);
    for (var i = 0; i < 5; i++) {
      final t = (i + .5) / 5, x = r.left + r.width * t;
      final path = Path()
        ..moveTo(x, r.bottom + 2)
        ..cubicTo(
          x - r.width * .19,
          r.center.dy,
          x + r.width * .2,
          r.center.dy,
          x + math.sin(seed + i + age * 5) * r.width * .1,
          r.top - 2,
        );
      p
        ..color = c.first.withValues(alpha: flowing ? .24 : .35)
        ..strokeWidth = flowing ? .7 : .25;
      canvas.drawPath(path, p);
    }
    if (const {'blade', 'moon', 'throw', 'earth', 'ice'}.contains(family)) {
      final stripe = Path()
        ..moveTo(r.left - r.width * .2, r.bottom)
        ..lineTo(r.left + r.width * (.2 + age * .6), r.top)
        ..lineTo(r.left + r.width * (.35 + age * .6), r.top)
        ..lineTo(r.left + r.width * .15, r.bottom)
        ..close();
      canvas.drawPath(
        stripe,
        Paint()
          ..isAntiAlias = true
          ..color = c.first.withValues(alpha: .36),
      );
    }
    if (family == 'seal' ||
        family == 'aura' ||
        family == 'bell' ||
        family == 'sound') {
      final radius = math.min(r.width, r.height) * .36;
      p
        ..color = c.first.withValues(alpha: .6)
        ..strokeWidth = .3;
      canvas.drawCircle(r.center, radius, p);
      canvas.drawCircle(r.center, radius * .76, p);
      for (var i = 0; i < 8; i++) {
        final a = i * math.pi / 4 + seed * .11;
        final v = Offset(math.cos(a), math.sin(a));
        canvas.drawLine(
          r.center + v * radius * .83,
          r.center + v * radius * 1.12,
          p,
        );
      }
    }
  }

  static void _ornaments(
    Canvas canvas,
    ModernEffectShape shape,
    String family,
    List<Color> c,
    double age,
    int seed,
  ) {
    final r = shape.bounds, p = Paint()..isAntiAlias = true;
    final centers = shape.centers.isEmpty ? [r.center] : shape.centers;
    final fire = const {'fire', 'dragon', 'phoenix', 'blood'}.contains(family);
    for (var i = 0; i < math.min(centers.length, 12); i++) {
      final center = centers[i], a = (seed + i * 71) * .37 + age * 2;
      final shift = Offset(math.cos(a), math.sin(a)) * (1 + age * 2);
      final q = center + shift;
      if (family == 'thunder') {
        final bolt = Path()
          ..moveTo(q.dx - 3, q.dy - 4)
          ..lineTo(q.dx + .7, q.dy - 1)
          ..lineTo(q.dx - .4, q.dy + .5)
          ..lineTo(q.dx + 3, q.dy + 4);
        canvas.drawPath(
          bolt,
          p
            ..style = PaintingStyle.stroke
            ..strokeWidth = .38
            ..color = c.first
            ..strokeCap = StrokeCap.round,
        );
        p.style = PaintingStyle.fill;
      } else if (family == 'swarm') {
        final wing = Path()
          ..moveTo(q.dx, q.dy)
          ..cubicTo(q.dx - 3, q.dy - 4, q.dx - 4, q.dy + 1, q.dx, q.dy + 1)
          ..cubicTo(q.dx + 4, q.dy + 1, q.dx + 3, q.dy - 4, q.dx, q.dy)
          ..close();
        canvas.drawPath(wing, p..color = c.first.withValues(alpha: .75));
        canvas.drawOval(
          Rect.fromCenter(center: q, width: .55, height: 2),
          p..color = c.last,
        );
      } else if (fire) {
        final flame = Path()
          ..moveTo(q.dx, q.dy - 3 - age * 2)
          ..cubicTo(q.dx + 2, q.dy - 1, q.dx + 1.5, q.dy + 2, q.dx, q.dy + 2)
          ..cubicTo(
            q.dx - 1.8,
            q.dy + 1,
            q.dx - 1,
            q.dy - 1,
            q.dx,
            q.dy - 3 - age * 2,
          )
          ..close();
        canvas.drawPath(
          flame,
          p
            ..shader = Gradient.linear(
              q - const Offset(0, 3),
              q + const Offset(0, 2),
              [c.first, c[1].withValues(alpha: .3)],
            ),
        );
        p.shader = null;
      } else {
        final sparkle = Path()
          ..moveTo(q.dx, q.dy - 1.8)
          ..quadraticBezierTo(q.dx + .35, q.dy - .35, q.dx + 1.7, q.dy)
          ..quadraticBezierTo(q.dx + .35, q.dy + .35, q.dx, q.dy + 1.8)
          ..quadraticBezierTo(q.dx - .35, q.dy + .35, q.dx - 1.7, q.dy)
          ..quadraticBezierTo(q.dx - .35, q.dy - .35, q.dx, q.dy - 1.8)
          ..close();
        canvas.drawPath(sparkle, p..color = c.first.withValues(alpha: .72));
      }
    }
  }

  static void _strike(
    Canvas canvas,
    Offset center,
    int direction,
    double progress,
  ) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(direction.toDouble(), 1);
    final path = Path()
      ..moveTo(-38, -37)
      ..cubicTo(-8, -44, 37, -15, 44, 30)
      ..cubicTo(17, 3, -4, -19, -38, -37)
      ..close();
    final p = Paint()
      ..isAntiAlias = true
      ..shader = Gradient.linear(const Offset(-35, -35), const Offset(43, 30), [
        const Color(0x00e4e8ff),
        const Color(0xfff5f5df).withValues(alpha: progress),
        const Color(0xff83c9de),
      ]);
    canvas.drawPath(path, p);
    p.shader = null;
    canvas.drawPath(
      path,
      p
        ..style = PaintingStyle.stroke
        ..strokeWidth = .8
        ..color = const Color(0xfff6f3db).withValues(alpha: .8),
    );
    canvas.restore();
  }

  static void _impact(Canvas canvas, Offset point, double step) {
    final p = Paint()
      ..isAntiAlias = true
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1.1
      ..color = const Color(
        0xfffee5a7,
      ).withValues(alpha: step == 0 ? .85 : .45);
    for (var i = 0; i < 7; i++) {
      final a = i * math.pi * 2 / 7, v = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(
        point + v * (3 + step * 2),
        point + v * (9 + step * 5),
        p,
      );
    }
  }
}

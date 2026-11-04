import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../data/game_data.dart';
import '../engine/game_engine.dart';
import 'modern_art.dart';
import 'ending_calligraphy.dart';

/// 片尾沿用原1:4动画的生命期与倍速，只替换彩色绘制，不修改剧情指针或SRS帧。
/// 书法使用OFL矢量轮廓，纸纹、水墨、蝴蝶均由同一游戏时钟驱动，没有额外定时器。
abstract final class ModernEndingScene {
  static const bounds = Rect.fromLTWH(0, 0, 640, 384);
  static bool supports(GameEngine game) =>
      game.cursor?.script.id == '2:18' && game.operation?.movie?.id == '1:4';
  static double progress(GameMovie movie) {
    if (movie.headers.isEmpty || movie.active.isEmpty) return 1;
    final index = movie.active
        .map((a) => a[0])
        .reduce(math.max)
        .clamp(0, movie.headers.length - 1);
    final active = movie.active.firstWhere((a) => a[0] == index),
        header = movie.headers[index];
    var total = movie.headers.last[2], elapsed = header[2] - active[1];
    for (var i = 0; i < movie.headers.length - 1; i++) {
      total += movie.headers[i][3];
      if (i < index) elapsed += movie.headers[i][3];
    }
    return total <= 0 ? 1 : (elapsed / total).clamp(0.0, 1.0);
  }

  static double _during(double value, double start, double end) =>
      ((value - start) / (end - start)).clamp(0.0, 1.0);

  static bool draw(
    Canvas canvas,
    GameEngine game,
    ModernArt art, {
    Size viewport = const Size(640, 384),
  }) {
    if (!supports(game)) return false;
    final p = progress(game.operation!.movie!);
    final paint = Paint()..isAntiAlias = true;
    canvas.drawRect(bounds, paint..color = const Color(0xff122b28));
    final open = Curves.easeOut.transform(_during(p, 0, .12));
    canvas.drawRect(
      bounds,
      paint
        ..color = Color.lerp(
          const Color(0xff122b28),
          const Color(0xffe8dfc9),
          open,
        )!,
    );
    if (open > .1) {
      // 淡墨远山只放在下缘，保留书法留白；纹理固定，不随刷新抖动。
      for (var layer = 0; layer < 3; layer++) {
        final path = Path()..moveTo(0, 384);
        for (var x = 0; x <= 640; x += 16) {
          final y =
              336 +
              layer * 15 -
              math.sin(x * .011 + layer * 1.4) * 18 -
              math.sin(x * .023 + layer) * 6;
          path.lineTo(x.toDouble(), y);
        }
        path
          ..lineTo(640, 384)
          ..close();
        canvas.drawPath(
          path,
          paint
            ..color = Color.fromRGBO(72, 102, 89, (.05 + layer * .025) * open),
        );
      }
      paint
        ..color = Color.fromRGBO(128, 111, 78, .055 * open)
        ..strokeWidth = .5;
      for (var i = 0; i < 38; i++) {
        final y = 9.0 + i * 10;
        canvas.drawLine(
          Offset(0, y),
          Offset(640, y + math.sin(i * 1.3) * 1.6),
          paint,
        );
      }
    }
    final reveal = Curves.easeInOutCubic.transform(_during(p, .14, .64));
    if (reveal > 0) {
      final glyph = EndingCalligraphy.glyph, box = glyph.getBounds();
      const target = Rect.fromLTWH(205, 68, 230, 230);
      final scale =
          math.min(target.width / box.width, target.height / box.height) *
          (1.02 - .02 * reveal);
      canvas.save();
      canvas.clipRect(
        Rect.fromLTRB(180, 40, 460, target.top + target.height * reveal + 2),
      );
      canvas.translate(target.center.dx, target.center.dy + 3 * (1 - reveal));
      final sx = viewport.width / 640, sy = viewport.height / 384;
      canvas.scale(scale * math.min(1, sy / sx), scale * math.min(1, sx / sy));
      canvas.translate(-box.center.dx, -box.center.dy);
      canvas.drawPath(
        glyph,
        paint
          ..color = Color.fromRGBO(29, 51, 45, _during(p, .14, .34))
          ..style = PaintingStyle.fill,
      );
      canvas.restore();
    }
    final flight = _during(p, .12, .86),
        wing = .35 + .65 * math.sin(flight * math.pi * 9).abs();
    if (flight > 0 && flight < 1) {
      canvas.save();
      canvas.translate(
        90 + flight * 135,
        304 - math.sin(flight * math.pi) * 24,
      );
      canvas.scale(wing, 1);
      art.drawSprite(
        canvas,
        'opening:butterfly/0',
        const Rect.fromLTWH(-12, -8, 24, 16),
        paint
          ..color = Colors.white.withValues(
            alpha: math.sin(flight * math.pi) * .75,
          ),
      );
      canvas.restore();
    }
    return true;
  }
}

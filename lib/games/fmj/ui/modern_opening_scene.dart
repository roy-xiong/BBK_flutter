import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../engine/game_engine.dart';
import 'modern_art.dart';

/// 开场追蝶使用独立彩绘场景，仍由原SRS帧和驻留时长驱动，不添加计时器或改剧情。
abstract final class ModernOpeningScene {
  static bool supports(GameEngine game) =>
      game.cursor?.script.id == '1:1' &&
      const {'1:2', '1:3'}.contains(game.operation?.movie?.id);

  static bool draw(Canvas canvas, GameEngine game, ModernArt art) {
    if (!supports(game)) return false;
    final movie = game.operation?.movie,
        background = art.backgrounds['opening'];
    if (movie == null || background == null) return false;
    final paint = Paint()..filterQuality = FilterQuality.medium;
    canvas.drawImageRect(
      background,
      Rect.fromLTWH(
        0,
        0,
        background.width.toDouble(),
        background.height.toDouble(),
      ),
      const Rect.fromLTWH(0, 0, 640, 384),
      paint,
    );
    final index = movie.active.isEmpty
        ? 0
        : movie.active.map((a) => a[0]).reduce(math.max);
    final header = movie.headers.isEmpty
        ? null
        : movie.headers[index.clamp(0, movie.headers.length - 1)];
    final active = movie.active.where((a) => a[0] == index).firstOrNull;
    final within = header == null || active == null || header[3] <= 0
        ? 0.0
        : ((header[3] - active[2]) / header[3]).clamp(0.0, 1.0);
    final progress = ((index + within) / math.max(1, movie.headers.length))
        .clamp(0.0, 1.0);
    final chase = movie.id == '1:2';
    final hx = chase ? 64 + progress * 350 : 412.0;
    final hy = 266 + math.sin(progress * math.pi * 2) * 15;
    final frame = chase ? [0, 1, 2, 1][(game.ticks ~/ 2) % 4] : 0;
    final sprite = art.sprites['world:hero:1:2/$frame'];
    if (sprite != null) {
      const h = 126.0;
      final w = h * sprite.rect.width / sprite.rect.height;
      canvas.drawOval(
        Rect.fromCenter(center: Offset(hx + 30, hy + 5), width: 58, height: 11),
        paint..color = const Color(0x4424372c),
      );
      art.drawSprite(
        canvas,
        'world:hero:1:2/$frame',
        Rect.fromLTWH(hx, hy - h, w, h),
        paint..color = Colors.white,
      );
    }
    final bx = hx + 104 + math.sin(progress * math.pi * 7) * 24;
    final by = 154 + math.sin(progress * math.pi * 9) * 30;
    canvas.save();
    canvas.translate(bx, by);
    canvas.scale(.35 + .65 * math.sin(game.ticks * .6).abs(), 1);
    art.drawSprite(
      canvas,
      'opening:butterfly/0',
      const Rect.fromLTWH(-20, -13, 40, 26),
      paint..color = Colors.white,
    );
    canvas.restore();
    if (!chase) {
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, 640, 384),
        paint..color = Color.fromRGBO(13, 31, 30, (1 - progress) * .85),
      );
    }
    return true;
  }
}

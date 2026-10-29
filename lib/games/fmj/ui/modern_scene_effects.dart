import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../engine/game_engine.dart';
import 'modern_art.dart';
import 'modern_battle_effects.dart';

/// 剧情SRS的彩色叠加层。帧的出现、消失、落点均由原GameMovie驱动，不延长过场。
abstract final class ModernSceneEffects {
  static void draw(Canvas canvas, GameEngine game, ModernArt art) {
    final movie = game.operation?.movie;
    if (movie == null || movie.active.isEmpty) return;
    if (movie.id != '1:1') {
      ModernBattleEffects.drawMovie(
        canvas,
        movie,
        anchor: const Offset(320, 192),
        fullScreen: true,
      );
      return;
    }
    // 原落石是16×16的同一石块，49个SRS落点从上至下依次出现。
    // 复用场景已采用的岩石原画，保留每帧坐标及重叠，不能只推进经典像素缓冲。
    final paint = Paint()..filterQuality = FilterQuality.medium;
    for (final item in movie.active) {
      final header = movie.headers[item[0]];
      final x = header[0] * 4.0, y = header[1] * 4.0;
      final width = 48.0 + (item[0] % 3) * 5;
      canvas.drawOval(
        Rect.fromLTWH(x + 6, y + 52, width, 10),
        paint..color = const Color(0x4d1b211b),
      );
      paint.color = Colors.white;
      art.drawObject(
        canvas,
        'plant:rock/0',
        Rect.fromLTWH(x, y, width + 10, 64),
        paint,
      );
      final life = header[2] == 0 ? 0.0 : 1 - item[1] / header[2];
      for (var i = 0; i < 3; i++) {
        canvas.drawCircle(
          Offset(x + 14 + i * 17, y + 57 - life * 10),
          3 + life * (4 + i),
          paint
            ..color = Color.lerp(
              const Color(0x888d8970),
              Colors.transparent,
              math.max(0, life),
            )!,
        );
      }
    }
  }
}

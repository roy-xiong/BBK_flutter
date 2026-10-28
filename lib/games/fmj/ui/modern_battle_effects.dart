import 'dart:ui';
import 'package:flutter/material.dart' show Colors;
import '../data/game_data.dart';
import '../engine/game_engine.dart';
import 'modern_battle_layout.dart';

/// 将原SRS动画的当前叠帧直接投影到彩色战斗，而非把所有招式替换成统一光圈。
///
/// 只读取GameMovie.active，不在绘制中推进动画或伤害；原40ms帧驻留、叠帧、
/// 目标范围和倍速继续由引擎控制。弱键缓存像素轮廓，避免每帧生成GPU图片及内存堆积。
abstract final class ModernBattleEffects {
  static final _shapes = Expando<Path>();

  static Path _shape(GameBitmap bitmap) => _shapes[bitmap] ??= _trace(bitmap);

  static Path _trace(GameBitmap bitmap) {
    final path = Path();
    for (var y = 0; y < bitmap.height; y++) {
      var start = -1;
      for (var x = 0; x <= bitmap.width; x++) {
        final value = x < bitmap.width
            ? bitmap.pixels[y * bitmap.width + x]
            : 0;
        final ink = value >> 24 != 0 && value & 0x00ffffff == 0;
        if (ink && start < 0) start = x;
        if (!ink && start >= 0) {
          path.addRect(
            Rect.fromLTWH(
              start.toDouble(),
              y.toDouble(),
              (x - start).toDouble(),
              1,
            ),
          );
          start = -1;
        }
      }
    }
    return path;
  }

  static List<Color> _palette(String name, bool healing) {
    if (healing) {
      return const [Color(0xffe2ffdd), Color(0xff70e7ac), Color(0xff28a4a3)];
    }
    if (RegExp('雷|电|天罡|横刀').hasMatch(name)) {
      return const [Color(0xffffffed), Color(0xffd4b7ff), Color(0xff7b79ff)];
    }
    if (RegExp('火|焰|朱雀|炎').hasMatch(name)) {
      return const [Color(0xfffff3bd), Color(0xffffbd57), Color(0xffed5545)];
    }
    if (RegExp('水|冰|寒|霜').hasMatch(name)) {
      return const [Color(0xffedffff), Color(0xff95e8fb), Color(0xff6099dc)];
    }
    if (RegExp('毒|瘴|虫').hasMatch(name)) {
      return const [Color(0xffe6ffd6), Color(0xffb2d973), Color(0xff8d5cb3)];
    }
    return const [Color(0xfffff3ce), Color(0xffe4c273), Color(0xffbf794a)];
  }

  static void draw(Canvas canvas, GameEngine game, ModernBattleLayout layout) {
    final battle = game.battle, action = game.battle?.current;
    if (battle == null) return;
    if (action != null && action.stage == 1 && action.movie != null) {
      final record = action.resource == null
          ? null
          : game.magic(action.resource!);
      final all = (record?.byte(3) ?? 0) & 128 != 0;
      final name = action.resource == null
          ? action.kind
          : game.magicName(action.resource!);
      final healing = action.targets.any(
        (target) => (action.changes[target] ?? 0) > 0,
      );
      final anchor = action.targets.isEmpty
          ? const Offset(320, 192)
          : layout.point(action.targets.first) + const Offset(0, -48);
      drawMovie(
        canvas,
        action.movie!,
        anchor: anchor,
        fullScreen: all,
        colors: _palette(name, healing),
      );
    }
    for (final raise in battle.visibleRaises) {
      if (!raise.showing && raise.movies.isNotEmpty) {
        drawMovie(
          canvas,
          raise.movies.first,
          anchor: layout.raisePoint(raise) + const Offset(0, -32),
          colors: _palette('', raise.delta > 0),
        );
      }
    }
  }

  /// 每一个原叠帧保留位移和消失时机。幕布/全屏帧按160×96映射，单体帧锚定目标。
  static void drawMovie(
    Canvas canvas,
    GameMovie movie, {
    required Offset anchor,
    bool fullScreen = false,
    List<Color> colors = const [
      Color(0xfffff3ce),
      Color(0xffe4c273),
      Color(0xffbf794a),
    ],
  }) {
    if (movie.headers.isEmpty) return;
    final first = movie.headers.first;
    for (final item in movie.active) {
      final header = movie.headers[item[0]], index = header[4];
      if (index < 0 || index >= movie.bitmaps.length) continue;
      final bitmap = movie.bitmaps[index].frame(0);
      if (bitmap == null) continue;
      final full = fullScreen || bitmap.width == 160 && bitmap.height == 96;
      const scale = 4.0;
      final origin = full
          ? Offset(header[0] * scale, header[1] * scale)
          : anchor +
                Offset(
                  (header[0] - first[0] - bitmap.width / 2) * scale,
                  (header[1] - first[1] - bitmap.height / 2) * scale,
                );
      final bounds = Rect.fromLTWH(
        origin.dx,
        origin.dy,
        bitmap.width * scale,
        bitmap.height * scale,
      );
      canvas.save();
      canvas.translate(origin.dx, origin.dy);
      canvas.scale(scale);
      final shape = _shape(bitmap);
      final paint = Paint()..isAntiAlias = true;
      canvas.drawPath(
        shape,
        paint
          ..color = colors[1].withValues(alpha: .52)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.3),
      );
      paint.maskFilter = null;
      paint.shader = Gradient.linear(
        Offset.zero,
        Offset(bitmap.width.toDouble(), bitmap.height.toDouble()),
        colors,
        const [0, .5, 1],
      );
      canvas.drawPath(shape, paint);
      paint.shader = null;
      canvas.drawPath(
        shape,
        paint
          ..style = PaintingStyle.stroke
          ..strokeWidth = .18
          ..color = Colors.white.withValues(alpha: .7),
      );
      canvas.restore();
      // bounds用于限制后续扩展的光晕尺度；空/损坏帧静默跳过，不创建越界绘制区域。
      if (bounds.isEmpty) continue;
    }
  }
}

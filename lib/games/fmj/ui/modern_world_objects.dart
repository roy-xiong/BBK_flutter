import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../engine/game_actor.dart';
import '../engine/game_engine.dart';
import 'modern_art.dart';

/// 原机关的独立美术层。位置和显示状态始终由原 NPC 决定，图形不创建交互区域。
final class ModernWorldObjects {
  const ModernWorldObjects._();

  static bool draw(
    Canvas canvas,
    GameEngine game,
    GameActor actor,
    ModernArt art,
    Offset point,
    double tile,
    TextStyle? textStyle,
  ) {
    if (actor.type != 4) return false;
    final original = game.data.image(8, 4, actor.sprite);
    if (original == null) return false;
    final target = Rect.fromLTWH(
      point.dx,
      point.dy + tile - original.height * tile / 16,
      original.width * tile / 16,
      original.height * tile / 16,
    );
    final paint = Paint()..filterQuality = FilterQuality.medium;
    if (actor.sprite >= 1 && actor.sprite <= 3) {
      final drawn = art.drawSprite(
        canvas,
        'mechanism:gate:${actor.sprite}/0',
        target,
        paint,
      );
      return drawn;
    }
    if (actor.sprite == 40 && game.map?.id == '1:9') {
      // 原2:32事件为北玄武、西白虎、南朱雀、东苍龙。只换绘造型，不改变精魄
      // 消耗、触发条件、机关位置和碰撞；其他场景的同编号机关保持原有设计。
      final guardian = switch ((actor.x, actor.y)) {
        (11, 7) => 'tortoise',
        (7, 11) => 'tiger',
        (11, 15) => 'bird',
        (15, 11) => 'dragon',
        _ => null,
      };
      if (guardian != null &&
          art.drawObject(
            canvas,
            'review-v11:guardian-$guardian/0',
            Rect.fromLTWH(
              point.dx - tile * .5,
              point.dy - tile * 2.0,
              tile * 2,
              tile * 3.0,
            ),
            paint,
          )) {
        return true;
      }
    }
    if (actor.sprite == 8) {
      _sword(
        canvas,
        Rect.fromCenter(
          center: target.center,
          width: math.max(target.width, tile * 1.1),
          height: target.height,
        ),
      );
      return true;
    }
    if (actor.sprite == 11 && game.map?.id == '3:2') {
      return art.drawObject(
        canvas,
        'review-v14:cave-stairs/0',
        Rect.fromLTWH(
          point.dx - tile * .12,
          point.dy - tile * .35,
          tile * 1.25,
          tile * 1.35,
        ),
        paint,
      );
    }
    if (actor.sprite == 7) {
      // 原脚本击败护灯兽后先停止动画，再将步帧设为0；亮灯动画本身也会经过
      // 0帧，不能只读当前帧而让尚未通关的灯周期性熄灭。存档已保存这两个值。
      _lamp(canvas, target, lit: actor.state == 4 || actor.step % 4 != 0);
      return true;
    }
    if (actor.sprite == 9 || actor.sprite == 15) {
      final opened =
          original.frames.length > 1 && [0, 1, 2, 1][actor.step % 4] == 1;
      if (art.drawObject(
        canvas,
        'mechanism:chest-${opened ? 'open' : 'closed'}/0',
        target,
        paint,
      )) {
        return true;
      }
      _chest(canvas, target, opened: opened);
      return true;
    }
    if (const {24, 28, 36, 42}.contains(actor.sprite)) {
      // 蛇妖、蛟、天师魂魄与朱雀使用对应战斗身份的同一原画；只变显示大小，
      // 不再回退旧机关图，也不把袁萍芷的朱雀变身误画成其他鸟类。
      final h = actor.sprite == 42
          ? 2.5
          : actor.sprite == 36
          ? 2.2
          : 2.0;
      return art.drawObject(
        canvas,
        'mechanism:${actor.sprite}/0',
        Rect.fromLTWH(
          point.dx - tile * .65,
          point.dy + tile - tile * h,
          tile * 2.3,
          tile * h,
        ),
        paint,
      );
    }
    if (actor.sprite == 23) {
      return art.drawObject(canvas, 'mechanism:23/0', target, paint);
    }
    if (actor.sprite == 31) {
      final key =
          'world:tiandao:${actor.direction.clamp(1, 4)}/${[0, 1, 2, 1][actor.step % 4]}';
      return art.drawObject(
        canvas,
        key,
        Rect.fromLTWH(
          point.dx - tile * .4,
          point.dy - tile,
          tile * 1.8,
          tile * 2,
        ),
        paint,
      );
    }
    final phase = [0, 1, 2, 1][actor.step % 4];
    final key = art.sprites.containsKey('mechanism:${actor.sprite}/$phase')
        ? 'mechanism:${actor.sprite}/$phase'
        : 'mechanism:${actor.sprite}/0';
    return art.drawSprite(canvas, key, target, paint);
  }

  /// 无极乾坤剑：直身双刃、中央剑脊、青玉剑格和青铜剑台，不使用旧放大点阵。
  static void _sword(Canvas canvas, Rect rect) {
    canvas.save();
    canvas.translate(rect.left, rect.top);
    canvas.scale(rect.width / 100, rect.height / 320);
    final p = Paint()..isAntiAlias = true;
    canvas.drawOval(
      const Rect.fromLTWH(8, 300, 84, 15),
      p..color = const Color(0x55223732),
    );
    final base = Path()
      ..moveTo(15, 299)
      ..lineTo(85, 299)
      ..lineTo(94, 311)
      ..lineTo(6, 311)
      ..close();
    canvas.drawPath(base, p..color = const Color(0xff647b74));
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(22, 288, 56, 15),
        const Radius.circular(3),
      ),
      p..color = const Color(0xffb0bba4),
    );
    final blade = Path()
      ..moveTo(50, 7)
      ..lineTo(66, 53)
      ..lineTo(61, 216)
      ..lineTo(39, 216)
      ..lineTo(34, 53)
      ..close();
    canvas.drawPath(blade, p..color = const Color(0xffd5e6e5));
    canvas.drawPath(
      Path()
        ..moveTo(50, 7)
        ..lineTo(50, 216)
        ..lineTo(39, 216)
        ..lineTo(34, 53)
        ..close(),
      p..color = const Color(0xff7096a4),
    );
    canvas.drawLine(
      const Offset(50, 28),
      const Offset(50, 211),
      p
        ..color = const Color(0xfff2f3de)
        ..strokeWidth = 2,
    );
    for (var y = 94.0; y <= 164; y += 28) {
      canvas.drawPath(
        Path()
          ..moveTo(50, y - 5)
          ..lineTo(55, y)
          ..lineTo(50, y + 5)
          ..lineTo(45, y)
          ..close(),
        p
          ..color = const Color(0xffd8c48d)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4,
      );
    }
    p.style = PaintingStyle.fill;
    canvas.drawPath(
      Path()
        ..moveTo(13, 215)
        ..lineTo(35, 206)
        ..lineTo(65, 206)
        ..lineTo(87, 215)
        ..lineTo(82, 225)
        ..lineTo(60, 219)
        ..lineTo(40, 219)
        ..lineTo(18, 225)
        ..close(),
      p..color = const Color(0xffc5a35b),
    );
    canvas.drawPath(
      Path()
        ..moveTo(50, 202)
        ..lineTo(61, 214)
        ..lineTo(50, 228)
        ..lineTo(39, 214)
        ..close(),
      p..color = const Color(0xff347d72),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(43, 226, 14, 47),
        const Radius.circular(4),
      ),
      p..color = const Color(0xff315b58),
    );
    for (var y = 232.0; y < 268; y += 8) {
      canvas.drawLine(
        Offset(43, y),
        Offset(57, y - 3),
        p
          ..color = const Color(0xffc8b575)
          ..strokeWidth = 2,
      );
    }
    canvas.drawOval(
      const Rect.fromLTWH(38, 271, 24, 15),
      p..color = const Color(0xffc6a765),
    );
    canvas.drawOval(
      const Rect.fromLTWH(44, 274, 12, 9),
      p..color = const Color(0xff69ae96),
    );
    canvas.restore();
  }

  /// 宝箱只换外观；透明宝箱仍由原状态隐藏，拿取和开箱事件没有绘制层副本。
  static void _chest(Canvas canvas, Rect rect, {required bool opened}) {
    canvas.save();
    canvas.translate(rect.left, rect.top);
    canvas.scale(rect.width / 100, rect.height / 100);
    final p = Paint()..isAntiAlias = true;
    canvas.drawOval(
      const Rect.fromLTWH(5, 84, 90, 12),
      p..color = const Color(0x44222f29),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(7, 45, 86, 45),
        const Radius.circular(5),
      ),
      p..color = const Color(0xff65452d),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(7, 17, 86, 44),
        const Radius.circular(17),
      ),
      p..color = const Color(0xffa37743),
    );
    canvas.drawRect(
      const Rect.fromLTWH(7, 43, 86, 14),
      p..color = const Color(0xffbd9558),
    );
    for (final x in [22.0, 72.0]) {
      canvas.drawRect(
        Rect.fromLTWH(x, 20, 7, 69),
        p..color = const Color(0xffd1ad64),
      );
    }
    if (opened) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(9, 4, 82, 34),
          const Radius.circular(9),
        ),
        p..color = const Color(0xffa27642),
      );
      canvas.drawOval(
        const Rect.fromLTWH(10, 42, 80, 22),
        p..color = const Color(0xff302b24),
      );
      canvas.drawArc(
        const Rect.fromLTWH(10, 42, 80, 22),
        0,
        math.pi,
        false,
        p
          ..color = const Color(0xffd0a65f)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
      p.style = PaintingStyle.fill;
    }
    canvas.drawLine(
      const Offset(9, 61),
      const Offset(91, 61),
      p
        ..color = const Color(0xff3e3024)
        ..strokeWidth = 3,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(42, 48, 17, 23),
        const Radius.circular(3),
      ),
      p..color = const Color(0xffd9b66a),
    );
    canvas.drawCircle(
      const Offset(50, 57),
      3,
      p..color = const Color(0xff4d4431),
    );
    canvas.drawRect(
      const Rect.fromLTWH(48.5, 57, 3, 7),
      p..color = const Color(0xff4d4431),
    );
    canvas.restore();
  }

  /// 伏魔灯的灯座始终存在；熄灭后只保留暗色灯芯，不绘制火焰或绿色光团。
  static void _lamp(Canvas canvas, Rect rect, {required bool lit}) {
    canvas.save();
    canvas.translate(rect.left, rect.top);
    canvas.scale(rect.width / 100, rect.height / 100);
    final p = Paint()..isAntiAlias = true;
    canvas.drawOval(
      const Rect.fromLTWH(22, 83, 56, 13),
      p..color = const Color(0xff7a6c43),
    );
    canvas.drawRect(
      const Rect.fromLTWH(43, 61, 14, 25),
      p..color = const Color(0xffae9452),
    );
    canvas.drawOval(
      const Rect.fromLTWH(23, 51, 54, 18),
      p..color = const Color(0xffc4a65e),
    );
    if (!lit) {
      canvas.drawOval(
        const Rect.fromLTWH(29, 52, 42, 10),
        p..color = const Color(0xff413e32),
      );
      canvas.drawLine(
        const Offset(49, 55),
        const Offset(51, 49),
        p
          ..color = const Color(0xff292b29)
          ..strokeWidth = 2,
      );
      canvas.restore();
      return;
    }
    canvas.drawOval(
      const Rect.fromLTWH(32, 24, 36, 37),
      p..color = const Color(0xff428d70),
    );
    canvas.drawPath(
      Path()
        ..moveTo(50, 13)
        ..quadraticBezierTo(27, 41, 43, 51)
        ..quadraticBezierTo(62, 68, 65, 45)
        ..quadraticBezierTo(59, 29, 50, 13)
        ..close(),
      p..color = const Color(0xffa9d78e),
    );
    canvas.drawPath(
      Path()
        ..moveTo(51, 27)
        ..quadraticBezierTo(43, 46, 50, 50)
        ..quadraticBezierTo(61, 48, 51, 27)
        ..close(),
      p..color = const Color(0xffeff3b8),
    );
    canvas.restore();
  }
}

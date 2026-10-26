import 'dart:math' as math;
import 'dart:ui' as ui;
import 'cartoon_assets.dart';

/// 原生手绘美术工具：运行时与场景预览共用离线生成、会话缓存的PNG素材。
///
/// 绘制只使用确定性参数，不持有图片解码器、定时器或世界随机源。
final class GameArt {
  GameArt(this.canvas, {this.ink = false, this.assets});

  /// 仅离屏测试指定已加载的系统字体；正式应用保持 null，使用各平台字体回退。
  static String? previewFontFamily;
  final ui.Canvas canvas;
  final bool ink;
  final CartoonAssets? assets;
  ui.Color get water => ui.Color(ink ? 0xffc6d2cd : 0xff75a9ae);
  ui.Color get land => ui.Color(ink ? 0xffe9e5d6 : 0xffadb28a);
  ui.Color get forest => ui.Color(ink ? 0xff52635b : 0xff425f57);
  ui.Color get outline => ui.Color(ink ? 0xff38463f : 0xff273940);
  ui.Color get paper => ui.Color(ink ? 0xfff4efdf : 0xffeee8d7);
  ui.Color get gold => ui.Color(ink ? 0xffaa6d54 : 0xffb9a16d);
  ui.Paint paint(ui.Color color, {double? stroke}) => ui.Paint()
    ..color = color
    ..style = stroke == null ? ui.PaintingStyle.fill : ui.PaintingStyle.stroke
    ..strokeWidth = stroke ?? 1
    ..strokeJoin = ui.StrokeJoin.round
    ..strokeCap = ui.StrokeCap.round;
  void path(List<ui.Offset> points, ui.Color color, {double? stroke}) {
    if (points.isEmpty) return;
    final shape = ui.Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      shape.lineTo(point.dx, point.dy);
    }
    if (stroke == null) shape.close();
    canvas.drawPath(shape, paint(color, stroke: stroke));
  }

  void rounded(
    ui.Rect rect,
    ui.Color color, {
    double radius = 3,
    double? stroke,
  }) => canvas.drawRRect(
    ui.RRect.fromRectAndRadius(rect, ui.Radius.circular(radius)),
    paint(color, stroke: stroke),
  );
  void text(
    String value,
    ui.Rect rect, {
    double size = 10,
    ui.Color? color,
    bool bold = false,
    ui.TextAlign align = ui.TextAlign.left,
    String? fontFamily,
  }) {
    final builder =
        ui.ParagraphBuilder(
            ui.ParagraphStyle(
              fontSize: size,
              fontFamily:
                  previewFontFamily ?? fontFamily ?? (ink ? 'serif' : null),
              fontWeight: bold ? ui.FontWeight.w700 : ui.FontWeight.w500,
              textAlign: align,
              height: 1.05,
              maxLines: 1,
              ellipsis: '…',
            ),
          )
          ..pushStyle(ui.TextStyle(color: color ?? outline))
          ..addText(value);
    final paragraph = builder.build()
      ..layout(ui.ParagraphConstraints(width: math.max(1, rect.width)));
    // 同一控件内按行盒垂直居中，避免按钮文字依赖字体上边界而整体偏上。
    canvas.drawParagraph(
      paragraph,
      ui.Offset(
        rect.left,
        rect.top + math.max(0, (rect.height - paragraph.height) / 2),
      ),
    );
    paragraph.dispose();
  }

  void panel(ui.Rect rect, {ui.Color? color}) {
    rounded(rect.shift(const ui.Offset(0, 1)), const ui.Color(0x25384c58));
    rounded(rect, color ?? paper);
    if (!ink && color == null && assets != null) {
      canvas.save();
      canvas.clipRRect(
        ui.RRect.fromRectAndRadius(rect, const ui.Radius.circular(3)),
      );
      assets?.sprite(canvas, 'ui/paper', rect, opacity: .96);
      canvas.restore();
    }
    rounded(rect.deflate(.35), outline.withValues(alpha: .2), stroke: .65);
  }

  void mountain(double x, double y, double scale, int seed) {
    if (!ink &&
        assets?.sprite(
              canvas,
              'terrain/mountain',
              ui.Rect.fromLTWH(
                x - 17 * scale,
                y - 21 * scale,
                34 * scale,
                32 * scale,
              ),
            ) ==
            true) {
      return;
    }
    canvas.save();
    canvas.translate(x, y);
    canvas.scale(scale);
    if (ink) {
      final random = math.Random(seed + 731);
      for (var layer = 0; layer < 4; layer++) {
        final width = 15 - layer * 1.3, height = 17 - layer * 2.0;
        final ridge = ui.Path()
          ..moveTo(-width, 11)
          ..cubicTo(-width * .4, 6, -8, -height * .45, -2, -height)
          ..quadraticBezierTo(1, -height - 3, 3, -height * .6)
          ..cubicTo(6, -height * .4, 9, 5, width, 11)
          ..close();
        canvas.drawPath(
          ridge,
          paint(outline.withValues(alpha: .08 + layer * .1)),
        );
      }
      for (var i = 0; i < 24; i++) {
        final dx = random.nextDouble() * 17 - 8;
        final yy = random.nextDouble() * 15 - 5;
        canvas.drawPath(
          ui.Path()
            ..moveTo(dx, yy)
            ..quadraticBezierTo(dx - 1, yy + 2, dx + 2, yy + 5),
          paint(
            outline.withValues(alpha: .22),
            stroke: .25 + random.nextDouble() * .5,
          ),
        );
      }
      canvas.drawOval(
        const ui.Rect.fromLTWH(-17, 5, 35, 9),
        paint(paper.withValues(alpha: .34)),
      );
      canvas.restore();
      return;
    }
    final shape = ui.Path()
      ..moveTo(-12, 10)
      ..quadraticBezierTo(-5, 1, -1, -12)
      ..quadraticBezierTo(2, -17, 4, -9)
      ..quadraticBezierTo(9, 2, 16, 10)
      ..close();
    canvas.drawPath(
      shape,
      paint(ink ? const ui.Color(0xff89958b) : const ui.Color(0xff7caa8e)),
    );
    final shadow = ui.Path()
      ..moveTo(2, -14)
      ..quadraticBezierTo(4, 1, 16, 10)
      ..lineTo(0, 8)
      ..close();
    canvas.drawPath(
      shadow,
      paint(ink ? const ui.Color(0xff566a60) : const ui.Color(0xff558c76)),
    );
    path([
      const ui.Offset(-3, -5),
      const ui.Offset(1, -13),
      const ui.Offset(4, -8),
      const ui.Offset(2, -7),
      const ui.Offset(0, -9),
    ], paper);
    if (ink) {
      for (var i = 0; i < 9; i++) {
        final dx = ((seed * 17 + i * 23) % 29 - 14).toDouble();
        canvas.drawLine(
          ui.Offset(dx, 8),
          ui.Offset(dx * .35, -8 + i % 3),
          paint(outline.withValues(alpha: .15), stroke: .35),
        );
      }
    }
    canvas.restore();
  }

  void tree(double x, double y, double s) {
    if (!ink &&
        assets?.sprite(
              canvas,
              'terrain/tree',
              ui.Rect.fromLTWH(x - 7 * s, y - 12 * s, 14 * s, 19 * s),
            ) ==
            true) {
      return;
    }
    canvas.drawLine(
      ui.Offset(x, y),
      ui.Offset(x, y + 6 * s),
      paint(outline.withValues(alpha: .6), stroke: .7 * s),
    );
    for (var i = 0; i < 3; i++) {
      final dy = y - i * 2.7 * s;
      path([
        ui.Offset(x - 4 * s, dy + 2 * s),
        ui.Offset(x, dy - 4 * s),
        ui.Offset(x + 4 * s, dy + 2 * s),
      ], forest.withValues(alpha: .85 - i * .1));
    }
  }

  void fortress(ui.Rect rect, ui.Color flag, {bool capital = false}) {
    if (assets?.sprite(canvas, capital ? 'city/capital' : 'city/fort', rect) ==
        true) {
      path([
        ui.Offset(rect.left + rect.width * .81, rect.top + rect.height * .08),
        ui.Offset(rect.left + rect.width * .96, rect.top + rect.height * .12),
        ui.Offset(rect.left + rect.width * .9, rect.top + rect.height * .23),
        ui.Offset(rect.left + rect.width * .81, rect.top + rect.height * .19),
      ], flag);
      return;
    }
    canvas.save();
    canvas.translate(rect.left, rect.top);
    canvas.scale(rect.width / 30, rect.height / 28);
    canvas.drawOval(
      const ui.Rect.fromLTWH(0, 22, 30, 5),
      paint(const ui.Color(0x26436265)),
    );
    rounded(
      const ui.Rect.fromLTWH(3, 12, 24, 12),
      ink ? const ui.Color(0xffc6c6b2) : const ui.Color(0xffe7d8a7),
      radius: 1,
    );
    rounded(
      const ui.Rect.fromLTWH(5, 15, 20, 8),
      ink ? const ui.Color(0xffb4baac) : const ui.Color(0xffd1c48c),
      radius: 1,
    );
    for (var i = 0; i < 6; i++) {
      rounded(ui.Rect.fromLTWH(3 + i * 4, 10, 3, 4), paper, radius: .3);
    }
    final roof = ink ? const ui.Color(0xff616b60) : const ui.Color(0xffce6d45);
    rounded(const ui.Rect.fromLTWH(9, 5, 12, 9), paper, radius: 1);
    path([
      const ui.Offset(6, 7),
      const ui.Offset(15, 0),
      const ui.Offset(24, 7),
      const ui.Offset(20, 8),
      const ui.Offset(10, 8),
    ], roof);
    canvas.drawPath(
      ui.Path()
        ..moveTo(12, 24)
        ..lineTo(12, 18)
        ..arcToPoint(
          const ui.Offset(18, 18),
          radius: const ui.Radius.circular(3),
        )
        ..lineTo(18, 24)
        ..close(),
      paint(outline),
    );
    canvas.drawLine(
      const ui.Offset(25, 13),
      const ui.Offset(25, -3),
      paint(outline, stroke: .7),
    );
    path([
      const ui.Offset(25, -3),
      const ui.Offset(32, -1),
      const ui.Offset(31, 5),
      const ui.Offset(25, 3),
    ], flag);
    if (capital) {
      rounded(const ui.Rect.fromLTWH(14, 9, 2, 3), gold, radius: .5);
    }
    canvas.restore();
  }

  void portrait(
    ui.Rect rect, {
    int seed = 0,
    ui.Color? accent,
    int? period,
    int? person,
    String? identity,
  }) {
    if (assets?.portrait(
          canvas,
          rect,
          period: period,
          person: person,
          name: identity,
        ) ==
        true) {
      return;
    }
    canvas.save();
    canvas.clipRRect(
      ui.RRect.fromRectAndRadius(rect, const ui.Radius.circular(3)),
    );
    canvas.translate(rect.left, rect.top);
    canvas.scale(rect.width / 100, rect.height / 100);
    final color = ink
        ? outline.withValues(alpha: .65)
        : accent ??
              [
                const ui.Color(0xffdf6c51),
                const ui.Color(0xff4da39c),
                const ui.Color(0xff7b87c9),
                const ui.Color(0xffdcad45),
              ][seed % 4];
    rounded(
      const ui.Rect.fromLTWH(0, 0, 100, 100),
      color.withValues(alpha: .18),
    );
    canvas.drawCircle(
      const ui.Offset(50, 43),
      35,
      paint(gold.withValues(alpha: .15)),
    );
    rounded(const ui.Rect.fromLTWH(12, 73, 76, 44), outline, radius: 18);
    path([
      const ui.Offset(16, 81),
      const ui.Offset(40, 74),
      const ui.Offset(50, 89),
      const ui.Offset(61, 74),
      const ui.Offset(87, 82),
      const ui.Offset(81, 103),
      const ui.Offset(22, 103),
    ], color);
    for (var i = 0; i < 3; i++) {
      canvas.drawLine(
        ui.Offset(20, 86 + i * 7),
        ui.Offset(82, 86 + i * 7),
        paint(gold, stroke: 1.5),
      );
    }
    rounded(
      const ui.Rect.fromLTWH(36, 54, 28, 31),
      const ui.Color(0xffe7ab7a),
      radius: 10,
    );
    canvas.drawOval(
      const ui.Rect.fromLTWH(25, 23, 50, 53),
      paint(ink ? const ui.Color(0xffd3c6a7) : const ui.Color(0xffffd6a0)),
    );
    final hat = ui.Path()
      ..moveTo(22, 42)
      ..quadraticBezierTo(18, 5, 50, 7)
      ..quadraticBezierTo(81, 7, 79, 42)
      ..lineTo(68, 37)
      ..lineTo(65, 20)
      ..quadraticBezierTo(49, 27, 34, 21)
      ..lineTo(32, 37)
      ..close();
    canvas.drawPath(hat, paint(color));
    path([
      const ui.Offset(45, 10),
      const ui.Offset(50, 0),
      const ui.Offset(55, 10),
      const ui.Offset(53, 30),
      const ui.Offset(47, 30),
    ], gold);
    canvas.drawCircle(const ui.Offset(50, 27), 4, paint(gold));
    for (final x in [38.0, 62.0]) {
      canvas.drawLine(
        ui.Offset(x - 5, 42),
        ui.Offset(x + 4, 44),
        paint(outline, stroke: 2.6),
      );
      canvas.drawCircle(ui.Offset(x, 49), 2.1, paint(outline));
    }
    canvas.drawPath(
      ui.Path()
        ..moveTo(47, 49)
        ..lineTo(45, 57)
        ..lineTo(51, 58),
      paint(const ui.Color(0xffc48b65), stroke: 1),
    );
    canvas.drawPath(
      ui.Path()
        ..moveTo(33, 62)
        ..quadraticBezierTo(50, 69, 67, 62)
        ..quadraticBezierTo(64, 83, 50, 91)
        ..quadraticBezierTo(35, 80, 33, 62),
      paint(seed.isEven ? outline : const ui.Color(0xffece5ce)),
    );
    canvas.drawPath(
      ui.Path()
        ..moveTo(41, 64)
        ..quadraticBezierTo(50, 68, 59, 64),
      paint(outline, stroke: 1),
    );
    canvas.restore();
  }

  /// 只镜像人物实体；姓名、兵力、生命条由调用方在未翻转的画布上绘制。
  /// 战斗特写自行安排左右站位，战场则显式传入敌我朝向，避免重复翻转。
  void soldier(
    ui.Rect rect,
    int type,
    ui.Color flag, {
    int frame = 0,
    bool inactive = false,
    int state = 0,
    String? pose,
    bool facingLeft = false,
    bool battlefield = false,
  }) {
    canvas.save();
    if (facingLeft) {
      canvas.translate(rect.center.dx * 2, 0);
      canvas.scale(-1, 1);
    }
    try {
      _soldier(
        rect,
        type,
        flag,
        frame: frame,
        inactive: inactive,
        state: state,
        pose: pose,
        battlefield: battlefield,
      );
    } finally {
      canvas.restore();
    }
  }

  void _soldier(
    ui.Rect rect,
    int type,
    ui.Color flag, {
    int frame = 0,
    bool inactive = false,
    int state = 0,
    String? pose,
    bool battlefield = false,
  }) {
    final key =
        'unit/${flag.r > flag.g ? 'friendly' : 'enemy'}/${type.clamp(0, 5)}';
    final requested = pose ?? (frame.isOdd && !inactive ? 'stride' : 'idle');
    if (battlefield &&
        assets?.sprite(
              canvas,
              '$key/field_$requested',
              rect,
              opacity: inactive ? .85 : 1,
            ) ==
            true) {
      return;
    }
    if (assets?.sprite(
              canvas,
              '$key/$requested',
              rect,
              opacity: inactive ? .85 : 1,
            ) ==
            true ||
        assets?.sprite(canvas, key, rect) == true) {
      return;
    }
    canvas.save();
    canvas.translate(rect.left, rect.top);
    canvas.scale(rect.width / 32, rect.height / 32);
    if (inactive) {
      canvas.saveLayer(
        const ui.Rect.fromLTWH(0, 0, 34, 34),
        ui.Paint()..color = const ui.Color(0xaaffffff),
      );
    }
    canvas.drawOval(
      const ui.Rect.fromLTWH(1, 26, 30, 5),
      paint(const ui.Color(0x33436b58)),
    );
    if (type == 3) {
      path([
        const ui.Offset(0, 19),
        const ui.Offset(30, 19),
        const ui.Offset(24, 30),
        const ui.Offset(7, 29),
      ], ink ? outline : const ui.Color(0xffa46c3f));
      canvas.drawLine(
        const ui.Offset(17, 3),
        const ui.Offset(17, 25),
        paint(outline, stroke: 1),
      );
      path([
        const ui.Offset(18, 3),
        const ui.Offset(28, 17),
        const ui.Offset(18, 17),
      ], paper);
      rounded(const ui.Rect.fromLTWH(7, 16, 9, 11), flag, radius: 2);
      canvas.drawCircle(
        const ui.Offset(11, 13),
        4,
        paint(const ui.Color(0xffffd4a0)),
      );
      canvas.drawCircle(const ui.Offset(10, 12.5), .55, paint(outline));
      canvas.drawCircle(const ui.Offset(12.5, 12.5), .55, paint(outline));
      canvas.drawLine(
        const ui.Offset(10.5, 15),
        const ui.Offset(12, 15),
        paint(outline, stroke: .4),
      );
      for (var i = 0; i < 3; i++) {
        canvas.drawLine(
          ui.Offset(8 + i * 5, 23),
          ui.Offset(10 + i * 5, 28),
          paint(paper.withValues(alpha: .35), stroke: .6),
        );
      }
    } else {
      if (type == 0) {
        rounded(
          const ui.Rect.fromLTWH(4, 20, 24, 8),
          const ui.Color(0xffb18a55),
          radius: 4,
        );
        path([
          const ui.Offset(24, 22),
          const ui.Offset(25, 14),
          const ui.Offset(29, 13),
          const ui.Offset(31, 20),
        ], const ui.Color(0xffb18a55));
        canvas.drawCircle(const ui.Offset(28, 17), .7, paint(outline));
        canvas.drawLine(
          const ui.Offset(25, 15),
          const ui.Offset(24, 19),
          paint(outline, stroke: 1),
        );
        canvas.drawPath(
          ui.Path()
            ..moveTo(4, 22)
            ..quadraticBezierTo(-1, 19, 1, 27),
          paint(outline, stroke: 1.2),
        );
        for (final x in [8.0, 23.0]) {
          canvas.drawLine(
            ui.Offset(x, 25),
            ui.Offset(x + (frame == 0 ? 0 : 2), 31),
            paint(outline, stroke: 2),
          );
        }
      } else {
        for (final x in [12.0, 21.0]) {
          canvas.drawLine(
            ui.Offset(x, 23),
            ui.Offset(x + (frame == 0 ? 0 : 1.5), 30),
            paint(outline, stroke: 2.3),
          );
        }
      }
      rounded(
        const ui.Rect.fromLTWH(8, 11, 17, 14),
        type == 5 ? const ui.Color(0xff8d78bd) : flag,
        radius: type == 4 ? 2 : 4,
      );
      if (type == 5) {
        // 术袍保持玄兵的紫色轮廓，胸前绶带保留红蓝阵营，避免敌我同色。
        rounded(const ui.Rect.fromLTWH(11, 13, 11, 3), flag, radius: 1);
      }
      canvas.drawCircle(
        const ui.Offset(16, 8),
        5,
        paint(const ui.Color(0xffffd4a0)),
      );
      canvas.drawPath(
        ui.Path()
          ..moveTo(10, 7)
          ..quadraticBezierTo(11, 0, 16, 1)
          ..quadraticBezierTo(22, 0, 23, 8)
          ..close(),
        paint(type == 5 ? const ui.Color(0xff6e7898) : outline),
      );
      canvas.drawCircle(const ui.Offset(14, 8.5), .65, paint(outline));
      canvas.drawCircle(const ui.Offset(18, 8.5), .65, paint(outline));
      canvas.drawPath(
        ui.Path()
          ..moveTo(14.5, 10.5)
          ..quadraticBezierTo(16, 11.5, 18, 10.5),
        paint(outline, stroke: .45),
      );
      if (type == 4) {
        // 极兵以肩甲、重盔和宽刃区分，缩小到战场图标后仍保留不同外轮廓。
        rounded(const ui.Rect.fromLTWH(5, 12, 8, 5), gold, radius: 1);
        rounded(const ui.Rect.fromLTWH(20, 12, 8, 5), gold, radius: 1);
        path([
          const ui.Offset(12, 2),
          const ui.Offset(16, -2),
          const ui.Offset(20, 2),
          const ui.Offset(16, 5),
        ], gold);
      }
      if (type != 5) {
        path([
          const ui.Offset(15, 2),
          const ui.Offset(18, -1),
          const ui.Offset(18, 5),
        ], flag);
        for (var i = 0; i < 3; i++) {
          canvas.drawLine(
            ui.Offset(10, 15 + i * 3),
            ui.Offset(22, 15 + i * 3),
            paint(gold, stroke: .7),
          );
        }
      }
      if (type == 2) {
        rounded(
          const ui.Rect.fromLTWH(4, 13, 4, 11),
          const ui.Color(0xff9c7048),
          radius: 1,
        );
        for (var i = 0; i < 3; i++) {
          canvas.drawLine(
            ui.Offset(4 + i * 1.5, 10),
            ui.Offset(5 + i * 1.5, 19),
            paint(paper, stroke: .6),
          );
        }
        canvas.drawArc(
          const ui.Rect.fromLTWH(23, 5, 8, 20),
          -math.pi / 2,
          math.pi,
          false,
          paint(gold, stroke: 1.4),
        );
        canvas.drawLine(
          const ui.Offset(27, 6),
          const ui.Offset(27, 25),
          paint(paper, stroke: .5),
        );
      } else if (type == 5) {
        canvas.drawLine(
          const ui.Offset(27, 4),
          const ui.Offset(27, 28),
          paint(gold, stroke: 1),
        );
        canvas.drawCircle(
          const ui.Offset(27, 4),
          3,
          paint(const ui.Color(0xffb4a6e4)),
        );
        canvas.drawCircle(const ui.Offset(27, 4), 1.4, paint(paper));
      } else {
        canvas.drawLine(
          const ui.Offset(28, 2),
          const ui.Offset(27, 30),
          paint(outline, stroke: 1),
        );
        if (type == 4) {
          path([
            const ui.Offset(28, 3),
            const ui.Offset(33, 7),
            const ui.Offset(29, 12),
            const ui.Offset(24, 9),
          ], gold);
        } else {
          path([
            const ui.Offset(28, -1),
            const ui.Offset(30, 6),
            const ui.Offset(26, 6),
          ], paper);
        }
        if (type == 1) {
          path([
            const ui.Offset(3, 12),
            const ui.Offset(11, 10),
            const ui.Offset(12, 22),
            const ui.Offset(7, 27),
            const ui.Offset(3, 22),
          ], gold);
        }
      }
    }
    if (state == 1 || state == 6) {
      rounded(const ui.Rect.fromLTWH(6, 20, 20, 10), outline, radius: 3);
    }
    if (inactive) canvas.restore();
    canvas.restore();
  }

  /// 历史中国的概略陆地与东海岸，画布坐标归一化到给定矩形。
  void geography(ui.Rect rect) {
    final cached = assets;
    if (cached != null) {
      canvas.drawImageRect(
        cached.map,
        ui.Rect.fromLTWH(
          0,
          0,
          cached.map.width.toDouble(),
          cached.map.height.toDouble(),
        ),
        rect,
        ui.Paint()..filterQuality = ui.FilterQuality.medium,
      );
      return;
    }
    canvas.save();
    canvas.clipRect(rect);
    canvas.translate(rect.left, rect.top);
    canvas.scale(rect.width, rect.height);
    canvas.drawRect(const ui.Rect.fromLTWH(0, 0, 1, 1), paint(water));
    final coast = ui.Path()
      ..moveTo(-.1, -.1)
      ..lineTo(.76, -.1)
      ..cubicTo(.79, .01, .91, .02, .94, .12)
      ..cubicTo(.94, .17, .89, .22, .87, .23)
      ..cubicTo(.85, .21, .84, .18, .81, .22)
      ..cubicTo(.76, .22, .80, .30, .74, .32)
      ..cubicTo(.72, .34, .76, .36, .81, .36)
      ..cubicTo(.87, .36, .88, .39, .85, .42)
      ..cubicTo(.83, .44, .79, .42, .79, .46)
      ..cubicTo(.81, .50, .80, .55, .85, .56)
      ..cubicTo(.87, .58, .82, .60, .85, .63)
      ..cubicTo(.89, .65, .86, .71, .83, .76)
      ..cubicTo(.80, .81, .74, .85, .69, .87)
      ..cubicTo(.64, .91, .59, .90, .55, .93)
      ..cubicTo(.53, .97, .48, .92, .50, .88)
      ..cubicTo(.46, .91, .44, .90, .40, .87)
      ..lineTo(.28, .87)
      ..lineTo(.21, .90)
      ..lineTo(.13, .85)
      ..lineTo(.06, .89)
      ..lineTo(-.1, .74)
      ..close();
    canvas.drawPath(
      coast.shift(const ui.Offset(.005, .009)),
      paint(outline.withValues(alpha: .15)),
    );
    canvas.drawPath(coast, paint(land));
    canvas.drawPath(coast, paint(outline.withValues(alpha: .3), stroke: .002));
    canvas.drawOval(const ui.Rect.fromLTWH(.88, .78, .018, .055), paint(land));
    canvas.drawOval(const ui.Rect.fromLTWH(.54, .95, .027, .014), paint(land));
    for (final points in [
      [.28, .32, .39, .43, .48, .33, .66, .35, .79, .42],
      [.18, .64, .4, .59, .57, .66, .7, .59, .84, .65],
    ]) {
      final river = ui.Path()
        ..moveTo(points[0], points[1])
        ..cubicTo(
          points[2],
          points[3],
          points[4],
          points[5],
          points[6],
          points[7],
        )
        ..lineTo(points[8], points[9]);
      canvas.drawPath(
        river,
        paint(outline.withValues(alpha: .15), stroke: .012),
      );
      canvas.drawPath(river, paint(water, stroke: .007));
    }
    canvas.restore();
    for (var i = 0; i < 13; i++) {
      mountain(
        rect.left + rect.width * (.07 + (i % 5) * .11),
        rect.top + rect.height * (.22 + (i ~/ 5) * .22),
        rect.width * .002,
        i,
      );
    }
    text(
      '东 海',
      ui.Rect.fromLTWH(
        rect.left + rect.width * .91,
        rect.top + rect.height * .59,
        rect.width * .1,
        15,
      ),
      size: rect.width * .025,
      color: outline.withValues(alpha: .5),
    );
    if (ink) {
      final random = math.Random(193);
      for (var i = 0; i < 600; i++) {
        final at = ui.Offset(
          rect.left + random.nextDouble() * rect.width,
          rect.top + random.nextDouble() * rect.height,
        );
        canvas.drawCircle(
          at,
          random.nextDouble() * .25,
          paint(outline.withValues(alpha: .04)),
        );
      }
    }
  }

  void appIcon(ui.Rect rect) {
    canvas.save();
    canvas.translate(rect.left, rect.top);
    canvas.scale(rect.width / 1024, rect.height / 1024);
    final bg = ui.Gradient.linear(
      const ui.Offset(0, 0),
      const ui.Offset(1024, 1024),
      [const ui.Color(0xff57b4ad), const ui.Color(0xff173c59)],
    );
    rounded(
      const ui.Rect.fromLTWH(0, 0, 1024, 1024),
      const ui.Color(0xff24516a),
      radius: 190,
    );
    canvas.save();
    canvas.clipRRect(
      ui.RRect.fromRectAndRadius(
        const ui.Rect.fromLTWH(0, 0, 1024, 1024),
        const ui.Radius.circular(190),
      ),
    );
    canvas.drawPaint(ui.Paint()..shader = bg);
    for (var i = 0; i < 4; i++) {
      mountain(50 + i * 280, 680 + (i % 2) * 90, 13, i);
    }
    canvas.drawCircle(
      const ui.Offset(512, 445),
      366,
      paint(gold.withValues(alpha: .17)),
    );
    canvas.drawCircle(
      const ui.Offset(512, 445),
      342,
      paint(gold.withValues(alpha: .65), stroke: 7),
    );
    portrait(
      const ui.Rect.fromLTWH(224, 125, 576, 660),
      seed: 2,
      accent: const ui.Color(0xffe87550),
    );
    rounded(
      const ui.Rect.fromLTWH(139, 761, 746, 188),
      const ui.Color(0xff183e55),
      radius: 48,
    );
    rounded(
      const ui.Rect.fromLTWH(147, 769, 730, 172),
      gold,
      radius: 40,
      stroke: 4,
    );
    text(
      '三国霸业',
      const ui.Rect.fromLTWH(175, 791, 680, 130),
      size: 124,
      bold: true,
      color: const ui.Color(0xffffe2a0),
      align: ui.TextAlign.center,
    );
    canvas.restore();
    canvas.restore();
  }
}

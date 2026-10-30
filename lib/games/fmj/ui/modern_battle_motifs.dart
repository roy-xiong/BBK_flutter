part of 'modern_battle_semantics.dart';

/// 复审第二轮确认的八套共享SRS；仅替换对应图形，其他已通过动画继续原绘制。
abstract final class _Round3Motifs {
  static const ids = {
    '2:6',
    '2:8',
    '2:15',
    '2:37',
    '2:41',
    '2:42',
    '2:46',
    '2:47',
  };
  static Paint p(Color color, [double stroke = 0]) =>
      ModernBattleSemantics._paint(color, stroke);

  static bool composition(
    Canvas canvas,
    GameMovie movie,
    Offset anchor,
    List<Color> colors,
  ) {
    if (movie.id != '2:15' || movie.active.isEmpty) return false;
    final t = ModernBattleSemantics.progress(movie),
        center = anchor + const Offset(0, -12);
    if (t < .42) {
      ModernBattleSemantics._taiji(canvas, center, 64, t * math.pi * 5, colors);
    }
    if (t > .32) {
      final launch = ((t - .32) / .68).clamp(0.0, 1.0);
      for (var i = 0; i < 7; i++) {
        final phase = (launch * 1.5 - i * .055).clamp(0.0, 1.0);
        if (phase == 0) continue;
        final angle = (i - 3) * .23,
            start = center + Offset((i - 3) * 25.0, -91 + (i - 3).abs() * 8);
        final end = center + Offset((i - 3) * 9.0, 28);
        final point = Offset.lerp(start, end, phase)!;
        canvas.drawLine(
          point + Offset(-math.sin(angle) * 30, -math.cos(angle) * 45),
          point,
          p(colors[1].withValues(alpha: .3), 2),
        );
        canvas.save();
        canvas.translate(point.dx, point.dy);
        canvas.rotate(angle);
        canvas.scale(.7);
        _sword(canvas, colors);
        canvas.restore();
      }
    }
    return true;
  }

  static bool frame(
    Canvas canvas,
    String id,
    int image,
    Size size,
    double age,
    int index,
    List<Color> colors,
  ) {
    if (!ids.contains(id) || id == '2:15') return false;
    canvas.save();
    if (id == '2:46') {
      // 四张原图只增加手臂露出高度，地面底边不移动；不能把整只手纵向拉长。
      final k = size.width / 100, visibleHeight = size.height / k;
      canvas.scale(k, k);
      canvas.clipRect(Rect.fromLTWH(-12, -8, 124, visibleHeight + 12));
      _earthHand(canvas, visibleHeight);
    } else {
      canvas.scale(size.width / 100, size.height / 100);
      switch (id) {
        case '2:6':
          _claw(canvas, false, age);
        case '2:8':
          _claw(canvas, true, age);
        case '2:37':
          _snake(canvas, image, age);
        case '2:41':
          _bee(canvas, index + age * 2);
        case '2:42':
          _worm(canvas, image + age);
        case '2:47':
          if (image == 0) _bell(canvas);
      }
    }
    canvas.restore();
    return true;
  }

  static void _bee(Canvas canvas, double phase) {
    canvas.save();
    canvas.translate(50, 52);
    canvas.rotate(-.3 + math.sin(phase) * .08);
    for (final side in [-1.0, 1.0]) {
      canvas.save();
      canvas.scale(side, 1);
      canvas.rotate(math.sin(phase * 6) * .11);
      final wing = Path()
        ..moveTo(0, -4)
        ..cubicTo(-6, -45, 23, -54, 29, -35)
        ..cubicTo(34, -17, 18, -3, 0, -4)
        ..close();
      canvas.drawPath(wing, p(const Color(0xaacbe5df)));
      canvas.drawPath(wing, p(const Color(0xff96b8b5), 1));
      canvas.drawPath(
        Path()
          ..moveTo(2, -6)
          ..quadraticBezierTo(7, -24, 23, -39)
          ..moveTo(5, -17)
          ..lineTo(23, -22)
          ..moveTo(9, -27)
          ..lineTo(16, -38),
        p(const Color(0xaa6a9797), .65),
      );
      canvas.restore();
    }
    for (var i = 0; i < 3; i++) {
      final x = -16 + i * 13.0;
      for (final side in [-1.0, 1.0]) {
        canvas.drawPath(
          Path()
            ..moveTo(x, side * 8)
            ..lineTo(x - 4, side * 20)
            ..lineTo(x + 5, side * 26),
          p(const Color(0xff473a29), 1.4),
        );
      }
    }
    canvas.drawPath(
      Path()
        ..moveTo(-28, 10)
        ..lineTo(-46, 14)
        ..lineTo(-33, 3)
        ..close(),
      p(const Color(0xff49362b)),
    );
    final body = Path()..addOval(const Rect.fromLTWH(-34, -15, 57, 33));
    canvas.drawPath(
      body,
      p(const Color(0xffe3ad46))
        ..shader = Gradient.linear(
          const Offset(0, -15),
          const Offset(0, 18),
          const [Color(0xffffe991), Color(0xffb9792f)],
        ),
    );
    canvas.save();
    canvas.clipPath(body);
    for (var i = 0; i < 3; i++) {
      canvas.drawPath(
        Path()
          ..moveTo(-25 + i * 15.0, -20)
          ..quadraticBezierTo(-15 + i * 15.0, 0, -25 + i * 15.0, 21),
        p(const Color(0xff49362c), 7),
      );
    }
    canvas.restore();
    canvas.drawPath(body, p(const Color(0xff5f482d), 1));
    canvas.drawOval(
      const Rect.fromLTWH(9, -17, 27, 30),
      p(const Color(0xff795a30)),
    );
    canvas.drawOval(
      const Rect.fromLTWH(25, -12, 8, 14),
      p(const Color(0xff262e2d)),
    );
    canvas.drawCircle(const Offset(29, -8), 1.7, p(const Color(0xfff1f2ce)));
    canvas.drawPath(
      Path()
        ..moveTo(23, -13)
        ..quadraticBezierTo(29, -32, 38, -30)
        ..moveTo(17, -15)
        ..quadraticBezierTo(18, -34, 10, -35),
      p(const Color(0xff4c432d), 1.2),
    );
    canvas.drawLine(
      const Offset(33, 0),
      const Offset(43, 4),
      p(const Color(0xff4c432d), 1.5),
    );
    canvas.restore();
  }

  static void _snake(Canvas canvas, int image, double age) {
    final bend = (image == 0 ? -1.0 : 1.0) * (1 + age * .15);
    final body = Path()
      ..moveTo(4, 74)
      ..cubicTo(29, 91, 8, 24, 31, 30)
      ..cubicTo(56, 36, 21, 91, 48, 75)
      ..cubicTo(78, 59, 47, 25, 83, 39 + bend * 7);
    canvas.drawPath(
      body.shift(const Offset(1, 3)),
      p(const Color(0x77453631), 11),
    );
    canvas.drawPath(body, p(const Color(0xff374e34), 10));
    canvas.drawPath(body, p(const Color(0xff8a9957), 6));
    canvas.drawPath(
      body.shift(const Offset(0, -1)),
      p(const Color(0xffd3c885), 1.2),
    );
    final metrics = body.computeMetrics().first;
    for (var s = 4.0; s < metrics.length - 8; s += 5) {
      final tangent = metrics.getTangentForOffset(s);
      if (tangent == null) continue;
      final normal = Offset(-tangent.vector.dy, tangent.vector.dx);
      canvas.drawLine(
        tangent.position - normal * 2.7,
        tangent.position + normal * 2.7,
        p(const Color(0xff53633d), .7),
      );
    }
    final y = 39 + bend * 7;
    final head = Path()
      ..moveTo(77, y - 6)
      ..quadraticBezierTo(87, y - 14, 97, y - 5)
      ..lineTo(98, y + 3)
      ..quadraticBezierTo(87, y + 9, 77, y + 4)
      ..close();
    canvas.drawPath(head, p(const Color(0xffa7a461)));
    canvas.drawPath(head, p(const Color(0xff465438), .9));
    canvas.drawCircle(Offset(91, y - 5), 2.1, p(const Color(0xffd4b74d)));
    canvas.drawLine(
      Offset(91, y - 6.5),
      Offset(91, y - 3.5),
      p(const Color(0xff202c23), 1),
    );
    canvas.drawPath(
      Path()
        ..moveTo(96, y)
        ..lineTo(106, y + 2)
        ..lineTo(111, y - 1)
        ..moveTo(106, y + 2)
        ..lineTo(110, y + 6),
      p(const Color(0xffae4b45), 1),
    );
  }

  static void _worm(Canvas canvas, double phase) {
    // 御虫咒原图是蠕动幼虫；使用分节体与腹足，区别于御蜂咒的飞行翅膀。
    for (var segment = 0; segment < 10; segment++) {
      final x = 7 + segment * 8.3,
          y = 54 + math.sin(segment * .74 + phase * 2) * 10;
      final r = 4.5 + math.sin(segment / 9 * math.pi) * 3;
      for (final side in [-1.0, 1.0]) {
        canvas.drawPath(
          Path()
            ..moveTo(x, y + 4)
            ..lineTo(x - 3 + side * 2, y + 15)
            ..lineTo(x + side * 5, y + 19),
          p(const Color(0xff594333), 1.4),
        );
      }
      canvas.drawCircle(
        Offset(x, y),
        r,
        p(segment.isEven ? const Color(0xffa3a76a) : const Color(0xff748856)),
      );
      canvas.drawArc(
        Rect.fromCircle(center: Offset(x, y), radius: r * .75),
        math.pi,
        math.pi * .85,
        false,
        p(const Color(0xffd5cf96), .8),
      );
    }
    final y = 54 + math.sin(9 * .74 + phase * 2) * 10;
    canvas.drawOval(
      Rect.fromCenter(center: Offset(89, y), width: 19, height: 22),
      p(const Color(0xff805c3d)),
    );
    for (final side in [-1.0, 1.0]) {
      canvas.drawCircle(
        Offset(94, y + side * 5),
        2,
        p(const Color(0xff282c23)),
      );
      canvas.drawPath(
        Path()
          ..moveTo(96, y + side * 7)
          ..quadraticBezierTo(108, y + side * 17, 103, y + side * 2),
        p(const Color(0xff46372c), 2),
      );
    }
  }

  static void _claw(Canvas canvas, bool large, double age) {
    if (large) {
      canvas.translate(-12, -12);
      canvas.scale(1.24);
    }
    final skin = const Color(0xffa7ad9b),
        dark = const Color(0xff435751),
        highlight = const Color(0xffd4d2ac);
    final wrist = Path()
      ..moveTo(5, 99)
      ..lineTo(20, 71)
      ..lineTo(46, 66)
      ..lineTo(60, 99)
      ..close();
    canvas.drawPath(wrist, p(const Color(0xff4b6563)));
    canvas.drawPath(
      Path()
        ..moveTo(10, 90)
        ..lineTo(55, 85),
      p(const Color(0xffb6a46b), 4),
    );
    final palm = Path()
      ..moveTo(23, 76)
      ..quadraticBezierTo(17, 56, 33, 44)
      ..lineTo(59, 37)
      ..quadraticBezierTo(80, 44, 75, 65)
      ..lineTo(60, 80)
      ..close();
    canvas.drawPath(
      palm,
      p(skin)
        ..shader = Gradient.linear(
          const Offset(25, 40),
          const Offset(74, 78),
          [highlight, skin, dark],
          const [0, .5, 1],
        ),
    );
    canvas.drawPath(palm, p(dark, 1.1));
    final fingers = <List<Offset>>[
      [
        const Offset(30, 56),
        const Offset(11, 37),
        const Offset(23, 17),
        const Offset(40, 21),
      ],
      [
        const Offset(39, 48),
        const Offset(29, 16),
        const Offset(44, 0),
        const Offset(56, 20),
      ],
      [
        const Offset(52, 44),
        const Offset(51, 9),
        const Offset(68, 0),
        const Offset(71, 25),
      ],
      [
        const Offset(64, 50),
        const Offset(80, 16),
        const Offset(95, 20),
        const Offset(87, 42),
      ],
      [
        const Offset(72, 61),
        const Offset(96, 45),
        const Offset(108, 55),
        const Offset(90, 68),
      ],
    ];
    for (final points in fingers) {
      final a = points[0], b = points[1], c = points[2], d = points[3];
      final path = Path()
        ..moveTo(a.dx - 4, a.dy + 4)
        ..cubicTo(b.dx - 4, b.dy, c.dx - 4, c.dy, d.dx, d.dy)
        ..lineTo(d.dx - 2, d.dy + 8)
        ..cubicTo(c.dx + 2, c.dy + 9, b.dx + 5, b.dy + 10, a.dx + 5, a.dy + 6)
        ..close();
      canvas.drawPath(path, p(skin));
      canvas.drawPath(path, p(dark, 1));
      canvas.drawPath(
        Path()
          ..moveTo(d.dx, d.dy)
          ..quadraticBezierTo(d.dx + 8, d.dy + 4, d.dx + 2, d.dy + 14)
          ..lineTo(d.dx - 2, d.dy + 8)
          ..close(),
        p(const Color(0xffe5dcc4)),
      );
      canvas.drawLine(
        Offset(b.dx, b.dy + 4),
        Offset(b.dx + 4, b.dy + 7),
        p(highlight, .8),
      );
    }
    canvas.drawPath(
      Path()
        ..moveTo(32, 65)
        ..quadraticBezierTo(46, 55, 62, 61)
        ..moveTo(36, 71)
        ..lineTo(57, 68),
      p(dark, .8),
    );
  }

  static void _earthHand(Canvas canvas, double height) {
    final arm = Path()
      ..moveTo(32, 245)
      ..lineTo(26, 92)
      ..quadraticBezierTo(15, 67, 26, 52)
      ..lineTo(36, 57)
      ..lineTo(33, 16)
      ..quadraticBezierTo(34, 6, 41, 13)
      ..lineTo(48, 46)
      ..lineTo(51, 4)
      ..quadraticBezierTo(56, -2, 60, 7)
      ..lineTo(61, 45)
      ..lineTo(69, 12)
      ..quadraticBezierTo(75, 7, 78, 16)
      ..lineTo(75, 53)
      ..lineTo(85, 34)
      ..quadraticBezierTo(94, 32, 91, 44)
      ..lineTo(81, 76)
      ..quadraticBezierTo(82, 94, 69, 105)
      ..lineTo(75, 245)
      ..close();
    canvas.drawPath(
      arm,
      p(const Color(0xffa09f88))
        ..shader = Gradient.linear(
          const Offset(22, 0),
          const Offset(80, 0),
          const [Color(0xff626e63), Color(0xffc1c1a2), Color(0xff697565)],
          const [0, .6, 1],
        ),
    );
    canvas.drawPath(arm, p(const Color(0xff394c45), 1.5));
    canvas.drawPath(
      Path()
        ..moveTo(32, 77)
        ..quadraticBezierTo(49, 67, 68, 73)
        ..moveTo(41, 91)
        ..lineTo(61, 86)
        ..moveTo(44, 116)
        ..lineTo(49, 217)
        ..moveTo(64, 108)
        ..lineTo(62, 220),
      p(const Color(0xff647463), 1),
    );
    for (var i = 0; i < 5; i++) {
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(13 + i * 18.0, height - 2 + math.sin(i) * 3),
          width: 13,
          height: 6,
        ),
        p(const Color(0xff655c49)),
      );
    }
    canvas.drawOval(
      Rect.fromCenter(center: Offset(52, height), width: 88, height: 10),
      p(const Color(0x663c342a)),
    );
  }

  static void _bell(Canvas canvas) {
    final bronze = Path()
      ..moveTo(27, 25)
      ..quadraticBezierTo(30, 12, 50, 12)
      ..quadraticBezierTo(70, 12, 73, 25)
      ..lineTo(83, 76)
      ..quadraticBezierTo(90, 81, 88, 87)
      ..quadraticBezierTo(50, 99, 12, 87)
      ..quadraticBezierTo(10, 81, 17, 76)
      ..close();
    canvas.drawOval(
      const Rect.fromLTWH(42, 0, 17, 20),
      p(const Color(0xff7b6b43), 5),
    );
    canvas.drawOval(
      const Rect.fromLTWH(42, 0, 17, 20),
      p(const Color(0xffcfb877), 1),
    );
    canvas.drawPath(
      bronze,
      p(const Color(0xff8b8258))
        ..shader = Gradient.linear(
          const Offset(16, 45),
          const Offset(84, 45),
          const [Color(0xff605d42), Color(0xffc4b77d), Color(0xff6f7557)],
          const [0, .45, 1],
        ),
    );
    canvas.drawPath(bronze, p(const Color(0xff4e543e), 1.1));
    for (final y in [29.0, 37.0, 69.0, 77.0]) {
      canvas.drawPath(
        Path()
          ..moveTo(23 - (y - 29) * .12, y)
          ..quadraticBezierTo(50, y + 5, 77 + (y - 29) * .12, y),
        p(const Color(0xffdec88b), 1),
      );
    }
    for (var i = 0; i < 7; i++) {
      canvas.drawCircle(
        Offset(31 + i * 6.0, 43 + math.sin(i * 1.2) * 2),
        1.4,
        p(const Color(0xff4d6049)),
      );
    }
    canvas.drawOval(
      const Rect.fromLTWH(14, 80, 72, 13),
      p(const Color(0xff353e31)),
    );
    canvas.drawArc(
      const Rect.fromLTWH(14, 80, 72, 13),
      0,
      math.pi,
      false,
      p(const Color(0xffc5b075), 2.5),
    );
    canvas.drawCircle(const Offset(50, 57), 10, p(const Color(0xffcfc082), 1));
    canvas.drawPath(
      Path()
        ..moveTo(44, 55)
        ..lineTo(50, 48)
        ..lineTo(56, 55)
        ..lineTo(50, 65)
        ..close(),
      p(const Color(0xff667451), 1),
    );
    canvas.drawLine(
      const Offset(50, 85),
      const Offset(50, 93),
      p(const Color(0xff8d7545), 3),
    );
  }

  static void _sword(Canvas canvas, List<Color> colors) {
    final blade = Path()
      ..moveTo(0, -62)
      ..lineTo(9, -41)
      ..lineTo(6, 7)
      ..lineTo(0, 17)
      ..lineTo(-6, 7)
      ..lineTo(-9, -41)
      ..close();
    canvas.drawPath(
      blade,
      p(const Color(0xffe5f0e8))
        ..shader = Gradient.linear(
          const Offset(-9, 0),
          const Offset(9, 0),
          [const Color(0xff7a9eaa), colors.first, const Color(0xffb2cbd0)],
          const [0, .5, 1],
        ),
    );
    canvas.drawPath(blade, p(const Color(0xff668793), .7));
    canvas.drawLine(
      const Offset(0, -54),
      const Offset(0, 10),
      p(const Color(0xffffffff), 1),
    );
    canvas.drawPath(
      Path()
        ..moveTo(-19, 15)
        ..quadraticBezierTo(0, 4, 19, 15)
        ..lineTo(15, 21)
        ..lineTo(0, 17)
        ..lineTo(-15, 21)
        ..close(),
      p(const Color(0xffb99c59)),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-4, 17, 8, 25),
        const Radius.circular(2),
      ),
      p(const Color(0xff664c3a)),
    );
    for (var i = 0; i < 4; i++) {
      canvas.drawLine(
        Offset(-4, 21 + i * 5.0),
        Offset(4, 24 + i * 5.0),
        p(const Color(0xffc3a165), .7),
      );
    }
    canvas.drawCircle(const Offset(0, 44), 5, p(const Color(0xffb99c59)));
  }
}

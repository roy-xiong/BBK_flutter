import 'dart:math' as math;
import 'dart:ui';
import '../data/game_data.dart';
import 'battle_calligraphy.dart';

part 'modern_battle_motifs.dart';

/// 本轮审核确认的招式语义图形。原SRS仍是唯一时钟和位置来源，绘制不写入会话。
/// 共用SRS的所有人物、敌人和道具自动使用同一修订，不按角色另造分支。
abstract final class ModernBattleSemantics {
  static const statusLetters = {
    '1:240': '攻',
    '1:241': '防',
    '1:242': '速',
    '1:243': '毒',
    '1:244': '乱',
    '1:245': '封',
    '1:246': '眠',
  };
  static final Set<String> correctedMovies = {
    '2:4',
    '2:14',
    '2:16',
    '2:20',
    '2:21',
    '2:22',
    '2:23',
    '2:24',
    '2:32',
    '2:40',
    '2:44',
    '2:50',
    '2:203',
    '2:204',
    '2:205',
    ...statusLetters.keys,
    ..._Round3Motifs.ids,
  };
  static final _timings = Expando<(List<int>, int)>();
  static Paint _paint(Color color, [double stroke = 0]) => Paint()
    ..isAntiAlias = true
    ..color = color
    ..style = stroke > 0 ? PaintingStyle.stroke : PaintingStyle.fill
    ..strokeWidth = stroke
    ..strokeJoin = StrokeJoin.round
    ..strokeCap = StrokeCap.round;

  /// 由活动帧剩余寿命反推原始时间，不自行增加帧或改变技能时长。
  static double progress(GameMovie movie) {
    final timing = _timings[movie] ??= _schedule(movie);
    var elapsed = 0;
    for (final item in movie.active) {
      final index = item[0];
      if (index < 0 || index >= movie.headers.length) continue;
      elapsed = math.max(
        elapsed,
        timing.$1[index] + movie.headers[index][2] - item[1],
      );
    }
    return timing.$2 == 0 ? 0 : (elapsed / timing.$2).clamp(0.0, 1.0);
  }

  static (List<int>, int) _schedule(GameMovie movie) {
    final starts = <int>[];
    var start = 0, end = 0;
    for (final header in movie.headers) {
      starts.add(start);
      end = math.max(end, start + header[2]);
      start += header[3];
    }
    return (starts, end);
  }

  /// 完整构图类动画只绘制一次，避免原重叠帧将太极、凤凰叠成发亮的一团。
  static bool drawComposition(
    Canvas canvas,
    GameMovie movie,
    Offset anchor,
    List<Color> colors,
  ) {
    if (movie.active.isEmpty) return false;
    if (_Round3Motifs.composition(canvas, movie, anchor, colors)) return true;
    final t = progress(movie);
    switch (movie.id) {
      case '2:14':
      case '2:16':
        _taiji(canvas, anchor + const Offset(0, -12), 63, t * .65, colors);
        return true;
      case '2:50':
        _taiji(
          canvas,
          const Offset(320, 160),
          105,
          t * .2,
          colors,
          faint: true,
        );
        const rows = ['休生伤杜', '景死惊开'];
        for (var row = 0; row < 2; row++) {
          for (var column = 0; column < 4; column++) {
            final appear = (t * 24 - row * 4 - column + 1).clamp(0.0, 1.0);
            if (appear == 0) continue;
            glyph(
              canvas,
              rows[row][column],
              Rect.fromCenter(
                center: Offset(194 + column * 84.0, 104 + row * 92.0),
                width: 64 * (.75 + appear * .25),
                height: 74,
              ),
              colors,
            );
          }
        }
        return true;
      case '2:203':
        if (t < .28) {
          _taiji(canvas, const Offset(172, 170), 85, t * 1.2, colors);
          return true;
        }
        // 初始太极之后继续原神剑SRS，已经认可的飞剑阶段沿用现有绘制。
        return false;
      case '2:204':
        _phoenixFlight(canvas, t);
        return true;
      case '2:205':
        _insectSwarm(canvas, t);
        return true;
    }
    return false;
  }

  /// 单个物件继续沿原帧坐标运动；只替换其图形，保留重叠/出现/消失时机。
  static bool drawFrame(
    Canvas canvas,
    String id,
    int bitmapIndex,
    Size size,
    double age,
    int frame,
    List<Color> colors,
  ) {
    if (_Round3Motifs.frame(
      canvas,
      id,
      bitmapIndex,
      size,
      age,
      frame,
      colors,
    )) {
      return true;
    }
    if (statusLetters.containsKey(id)) {
      glyph(canvas, statusLetters[id]!, Offset.zero & size, colors);
      return true;
    }
    if (!const {
      '2:4',
      '2:20',
      '2:21',
      '2:22',
      '2:23',
      '2:24',
      '2:32',
      '2:40',
      '2:44',
    }.contains(id)) {
      return false;
    }
    canvas.save();
    canvas.scale(size.width / 100, size.height / 100);
    switch (id) {
      case '2:4':
        if (bitmapIndex == 0) {
          _talisman(canvas, colors);
        } else {
          final r = 39.0 + age * 4;
          canvas.drawCircle(
            const Offset(50, 50),
            r,
            _paint(colors[1].withValues(alpha: .7), 1.7),
          );
          canvas.drawCircle(
            const Offset(50, 50),
            r - 4,
            _paint(colors.first.withValues(alpha: .55), .7),
          );
        }
      case '2:20':
        _grasp(canvas, bitmapIndex != 0, colors);
      case '2:21':
        _scissors(canvas, age);
      case '2:22':
        _blade(canvas, -.1);
      case '2:23':
        _blade(canvas, math.pi / 2 - .12);
      case '2:24':
        if (bitmapIndex == 0) {
          _blade(canvas, -.12);
        } else {
          _fracture(canvas, age, colors);
        }
      case '2:32':
        _tornado(canvas, frame * .7 + age * 2);
      case '2:40':
        _skull(canvas, colors);
      case '2:44':
        _rock(canvas);
    }
    canvas.restore();
    return true;
  }

  /// 状态“攻防速毒乱封眠”和八门文字采用真正的书法矢量轮廓，保持镂空笔画。
  static void glyph(
    Canvas canvas,
    String letter,
    Rect target,
    List<Color> colors,
  ) {
    final path = BattleCalligraphy.glyphs[letter];
    if (path == null || target.isEmpty) return;
    final bounds = path.getBounds();
    final scale = math.min(
      target.width * .84 / bounds.width,
      target.height * .87 / bounds.height,
    );
    canvas.save();
    canvas.translate(target.center.dx, target.center.dy);
    canvas.scale(scale);
    canvas.translate(-bounds.center.dx, -bounds.center.dy);
    canvas.drawPath(
      path,
      _paint(colors[1].withValues(alpha: .4))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, .035),
    );
    canvas.drawPath(path, _paint(const Color(0xff432c30), .025));
    canvas.drawPath(
      path,
      _paint(colors.first)
        ..shader = Gradient.linear(
          bounds.topCenter,
          bounds.bottomCenter,
          [colors.first, colors[1]],
          const [0, 1],
        ),
    );
    canvas.restore();
  }

  static void _taiji(
    Canvas canvas,
    Offset center,
    double radius,
    double turn,
    List<Color> colors, {
    bool faint = false,
  }) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(turn);
    final opacity = faint ? .23 : 1.0;
    canvas.drawCircle(
      Offset.zero,
      radius,
      _paint(colors[1].withValues(alpha: .1 * opacity)),
    );
    canvas.drawCircle(
      Offset.zero,
      radius * .98,
      _paint(colors[1].withValues(alpha: .65 * opacity), 2),
    );
    canvas.drawCircle(
      Offset.zero,
      radius * .67,
      _paint(colors.first.withValues(alpha: .8 * opacity), 1),
    );
    final r = radius * .56;
    canvas.drawCircle(
      Offset.zero,
      r,
      _paint(const Color(0xffffeed1).withValues(alpha: opacity)),
    );
    final dark = const Color(0xff1c393b).withValues(alpha: opacity);
    final yin = Path()
      ..moveTo(0, -r)
      ..arcTo(
        Rect.fromCircle(center: Offset.zero, radius: r),
        -math.pi / 2,
        math.pi,
        false,
      )
      ..arcTo(
        Rect.fromCircle(center: Offset(0, r / 2), radius: r / 2),
        math.pi / 2,
        math.pi,
        false,
      )
      ..arcTo(
        Rect.fromCircle(center: Offset(0, -r / 2), radius: r / 2),
        math.pi / 2,
        -math.pi,
        false,
      )
      ..close();
    canvas.drawPath(yin, _paint(dark));
    canvas.drawCircle(Offset(0, -r / 2), r * .12, _paint(dark));
    canvas.drawCircle(
      Offset(0, r / 2),
      r * .12,
      _paint(const Color(0xffffeed1).withValues(alpha: opacity)),
    );
    const trigrams = [7, 3, 5, 1, 6, 2, 4, 0];
    for (var i = 0; i < 8; i++) {
      canvas.save();
      canvas.rotate(i * math.pi / 4);
      for (var line = 0; line < 3; line++) {
        final y = -radius * (.76 + line * .065), half = radius * .105;
        final p = _paint(
          colors.first.withValues(alpha: opacity * .9),
          math.max(1, radius * .025),
        );
        if (trigrams[i] & (1 << line) != 0) {
          canvas.drawLine(Offset(-half, y), Offset(half, y), p);
        } else {
          canvas.drawLine(Offset(-half, y), Offset(-half * .24, y), p);
          canvas.drawLine(Offset(half * .24, y), Offset(half, y), p);
        }
      }
      canvas.restore();
    }
    canvas.restore();
  }

  static void _talisman(Canvas canvas, List<Color> colors) {
    final paper = Path()
      ..moveTo(13, 2)
      ..lineTo(87, 2)
      ..lineTo(83, 94)
      ..lineTo(72, 98)
      ..lineTo(25, 96)
      ..lineTo(17, 99)
      ..close();
    canvas.drawPath(
      paper.shift(const Offset(2, 2)),
      _paint(const Color(0x99412820)),
    );
    canvas.drawPath(
      paper,
      _paint(const Color(0xffffd98e))
        ..shader = Gradient.linear(
          const Offset(10, 0),
          const Offset(80, 100),
          const [Color(0xffffefd0), Color(0xffe7b66a)],
        ),
    );
    canvas.drawPath(paper, _paint(const Color(0xffa04b27), 1.5));
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(22, 8, 56, 79),
        const Radius.circular(2),
      ),
      _paint(const Color(0xffb33d2d), 1),
    );
    const ink = [Color(0xffb32c23), Color(0xffa72520), Color(0xff742523)];
    glyph(canvas, '降', const Rect.fromLTWH(24, 12, 52, 32), ink);
    glyph(canvas, '魔', const Rect.fromLTWH(24, 45, 52, 32), ink);
    canvas.drawRect(
      const Rect.fromLTWH(40, 80, 20, 10),
      _paint(const Color(0xffb32c23), 1),
    );
    for (var i = 0; i < 4; i++) {
      canvas.drawLine(
        Offset(43 + i * 4, 82),
        Offset(45 + i * 3, 88),
        _paint(const Color(0xffb32c23), .8),
      );
    }
  }

  static void _grasp(Canvas canvas, bool closed, List<Color> colors) {
    final cuff = Path()
      ..moveTo(28, 100)
      ..lineTo(28, 77)
      ..lineTo(68, 75)
      ..lineTo(73, 100)
      ..close();
    canvas.drawPath(cuff, _paint(const Color(0xff244f61)));
    canvas.drawLine(
      const Offset(28, 85),
      const Offset(70, 83),
      _paint(const Color(0xffd5b477), 4),
    );
    final palm = Path()
      ..moveTo(33, 80)
      ..cubicTo(26, 68, 20, 59, 16, 51)
      ..cubicTo(12, 43, 17, 39, 22, 44)
      ..lineTo(32, 54);
    if (closed) {
      palm
        ..lineTo(28, 28)
        ..cubicTo(28, 20, 35, 18, 38, 27)
        ..lineTo(42, 37)
        ..lineTo(43, 23)
        ..cubicTo(44, 16, 51, 16, 53, 25)
        ..lineTo(57, 37)
        ..lineTo(62, 26)
        ..cubicTo(65, 20, 72, 23, 70, 31)
        ..lineTo(67, 54)
        ..cubicTo(83, 40, 88, 50, 78, 61)
        ..cubicTo(72, 68, 68, 77, 64, 81)
        ..close();
    } else {
      palm
        ..lineTo(23, 18)
        ..cubicTo(22, 10, 30, 8, 33, 17)
        ..lineTo(42, 42)
        ..lineTo(38, 6)
        ..cubicTo(38, -1, 46, -1, 48, 7)
        ..lineTo(54, 39)
        ..lineTo(57, 9)
        ..cubicTo(58, 2, 66, 3, 66, 10)
        ..lineTo(65, 43)
        ..lineTo(74, 20)
        ..cubicTo(77, 13, 84, 17, 81, 25)
        ..lineTo(74, 58)
        ..cubicTo(71, 70, 67, 77, 63, 81)
        ..close();
    }
    canvas.drawPath(
      palm,
      _paint(const Color(0xfff4cda6))
        ..shader = Gradient.linear(
          const Offset(28, 28),
          const Offset(74, 81),
          const [Color(0xffffe6bb), Color(0xffc38c6d)],
        ),
    );
    canvas.drawPath(palm, _paint(const Color(0xff785a4b), 1.4));
    canvas.drawPath(
      Path()
        ..moveTo(36, 57)
        ..quadraticBezierTo(49, 48, 65, 56)
        ..moveTo(38, 69)
        ..quadraticBezierTo(50, 64, 62, 66),
      _paint(const Color(0xffb78266), 1),
    );
    if (closed) {
      canvas.drawOval(const Rect.fromLTWH(49, 32, 23, 17), _paint(colors[1]));
      canvas.drawOval(
        const Rect.fromLTWH(54, 35, 14, 10),
        _paint(colors.first, 1),
      );
    }
  }

  static void _scissors(Canvas canvas, double age) {
    canvas.save();
    canvas.translate(50, 50);
    canvas.rotate(-.55);
    for (final side in [-1.0, 1.0]) {
      canvas.save();
      canvas.rotate(side * (.2 + age * .2));
      final blade = Path()
        ..moveTo(-4, 8)
        ..lineTo(-3, -47)
        ..quadraticBezierTo(11, -39, 7, -2)
        ..lineTo(4, 12)
        ..close();
      canvas.drawPath(
        blade,
        _paint(const Color(0xffe7f2ed))
          ..shader = Gradient.linear(
            const Offset(-4, 0),
            const Offset(8, 0),
            const [Color(0xff6b8791), Color(0xfff7ffff), Color(0xffa5bdc1)],
            const [0, .45, 1],
          ),
      );
      canvas.drawPath(blade, _paint(const Color(0xff425d64), 1));
      canvas.drawOval(
        const Rect.fromLTWH(-14, 15, 25, 29),
        _paint(const Color(0xffbe804c), 5),
      );
      canvas.drawOval(
        const Rect.fromLTWH(-14, 15, 25, 29),
        _paint(const Color(0xfff0cb83), 1),
      );
      canvas.restore();
    }
    canvas.drawCircle(const Offset(0, 8), 4, _paint(const Color(0xffd5b77a)));
    canvas.drawCircle(const Offset(0, 8), 1.2, _paint(const Color(0xff55483e)));
    canvas.restore();
  }

  static void _blade(Canvas canvas, double rotation) {
    canvas.save();
    canvas.translate(50, 50);
    canvas.rotate(rotation);
    canvas.drawPath(
      Path()
        ..moveTo(-44, 14)
        ..quadraticBezierTo(6, 22, 45, 7),
      _paint(const Color(0x448ed9e6), 5),
    );
    final metal = Path()
      ..moveTo(-23, -5)
      ..lineTo(39, -7)
      ..quadraticBezierTo(49, -12, 49, -16)
      ..quadraticBezierTo(51, 7, 33, 12)
      ..lineTo(-23, 7)
      ..close();
    canvas.drawPath(
      metal,
      _paint(const Color(0xffe8f2ee))
        ..shader = Gradient.linear(
          const Offset(0, -9),
          const Offset(0, 13),
          const [Color(0xff658891), Color(0xfff9fff0), Color(0xffa2babd)],
          const [0, .45, 1],
        ),
    );
    canvas.drawPath(metal, _paint(const Color(0xff4b6266), 1));
    canvas.drawLine(
      const Offset(-21, 5),
      const Offset(32, 8),
      _paint(const Color(0xfffffff0), 1.3),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-29, -13, 6, 27),
        const Radius.circular(2),
      ),
      _paint(const Color(0xffc39e54)),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-47, -3, 19, 8),
        const Radius.circular(2),
      ),
      _paint(const Color(0xff75472f)),
    );
    for (var i = 0; i < 4; i++) {
      canvas.drawLine(
        Offset(-44 + i * 4, -2),
        Offset(-42 + i * 4, 4),
        _paint(const Color(0xffd1a569), .8),
      );
    }
    canvas.restore();
  }

  static void _fracture(Canvas canvas, double age, List<Color> colors) {
    final main = Path()
      ..moveTo(1, 57)
      ..lineTo(15, 51)
      ..lineTo(28, 56)
      ..lineTo(42, 46)
      ..lineTo(57, 54)
      ..lineTo(75, 42)
      ..lineTo(98, 47);
    canvas.drawOval(
      const Rect.fromLTWH(0, 32, 100, 43),
      _paint(const Color(0x88262120)),
    );
    canvas.drawPath(main, _paint(colors[1].withValues(alpha: .32), 9));
    canvas.drawPath(main, _paint(const Color(0xff292423), 6));
    canvas.drawPath(main, _paint(const Color(0xffffd28b), 1));
    for (var i = 0; i < 5; i++) {
      final x = 12.0 + i * 17, sign = i.isEven ? 1.0 : -1.0;
      canvas.drawPath(
        Path()
          ..moveTo(x, 53)
          ..lineTo(x + 6, 53 + sign * 13)
          ..lineTo(x - 1, 53 + sign * 24),
        _paint(const Color(0xff332c29), 2),
      );
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(x, 34 - age * 16),
          width: 4 + i % 3,
          height: 3,
        ),
        _paint(const Color(0xffc4a882)),
      );
    }
  }

  static void _skull(Canvas canvas, List<Color> colors) {
    canvas.drawOval(
      const Rect.fromLTWH(4, 7, 92, 89),
      _paint(const Color(0x555f447c))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    final head = Path()
      ..moveTo(21, 57)
      ..cubicTo(5, 39, 15, 10, 37, 7)
      ..cubicTo(67, -1, 91, 18, 82, 45)
      ..lineTo(77, 59)
      ..lineTo(67, 64)
      ..lineTo(67, 83)
      ..quadraticBezierTo(50, 94, 32, 82)
      ..lineTo(31, 64)
      ..close();
    canvas.drawPath(
      head,
      _paint(const Color(0xffeee6c6))
        ..shader = Gradient.linear(
          const Offset(20, 10),
          const Offset(76, 83),
          const [Color(0xfffff4d3), Color(0xffb6a895)],
        ),
    );
    canvas.drawPath(head, _paint(const Color(0xff62586a), 1.7));
    canvas.drawOval(
      const Rect.fromLTWH(24, 32, 22, 23),
      _paint(const Color(0xff302d42)),
    );
    canvas.drawOval(
      const Rect.fromLTWH(55, 31, 21, 23),
      _paint(const Color(0xff302d42)),
    );
    canvas.drawCircle(const Offset(36, 45), 2, _paint(const Color(0xffc388b0)));
    canvas.drawCircle(const Offset(65, 44), 2, _paint(const Color(0xffc388b0)));
    canvas.drawPath(
      Path()
        ..moveTo(50, 50)
        ..lineTo(43, 63)
        ..lineTo(55, 62)
        ..close(),
      _paint(const Color(0xff504258)),
    );
    canvas.drawLine(
      const Offset(33, 72),
      const Offset(66, 72),
      _paint(const Color(0xff62586a), 1.4),
    );
    for (var i = 0; i < 5; i++) {
      canvas.drawLine(
        Offset(37 + i * 6.0, 67),
        Offset(37 + i * 6.0, 82),
        _paint(const Color(0xff62586a), 1),
      );
    }
    canvas.drawPath(
      Path()
        ..moveTo(43, 11)
        ..lineTo(47, 20)
        ..lineTo(42, 27)
        ..lineTo(49, 31),
      _paint(const Color(0xff9b907e), 1),
    );
  }

  static void _tornado(Canvas canvas, double phase) {
    canvas.drawOval(
      const Rect.fromLTWH(34, 87, 35, 9),
      _paint(const Color(0x664b4740)),
    );
    final funnel = Path()
      ..moveTo(8, 15)
      ..cubicTo(20, 42, 58, 54, 48, 91)
      ..lineTo(57, 91)
      ..cubicTo(52, 59, 89, 42, 94, 16)
      ..close();
    canvas.drawPath(funnel, _paint(const Color(0x557eafb6)));
    for (var i = 0; i < 8; i++) {
      final y = 12 + i * 10.0, w = 42 - i * 4.8;
      final turn = phase + i * .7;
      final path = Path()
        ..moveTo(50 - w, y + math.sin(turn) * 3)
        ..cubicTo(50 - w * .4, y - 9, 50 + w, y - 4, 50 + w, y + 3)
        ..cubicTo(50 + w * .4, y + 10, 50 - w, y + 9, 50 - w, y + 5);
      canvas.drawPath(
        path,
        _paint(
          i.isEven ? const Color(0xffd4ecdf) : const Color(0xff6f9da5),
          2.2 - i * .12,
        ),
      );
    }
    for (var i = 0; i < 7; i++) {
      final a = phase + i * 1.9, y = 26 + i * 8.0;
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(50 + math.cos(a) * (40 - i * 4), y),
          width: 4,
          height: 2,
        ),
        _paint(const Color(0xffc3b294)),
      );
    }
  }

  static void _rock(Canvas canvas) {
    final rock = Path()
      ..moveTo(4, 53)
      ..lineTo(17, 24)
      ..lineTo(43, 8)
      ..lineTo(71, 14)
      ..lineTo(92, 36)
      ..lineTo(97, 69)
      ..lineTo(78, 91)
      ..lineTo(45, 96)
      ..lineTo(15, 83)
      ..close();
    canvas.drawPath(
      rock.shift(const Offset(2, 3)),
      _paint(const Color(0x88473c31)),
    );
    canvas.drawPath(
      rock,
      _paint(const Color(0xff969990))
        ..shader = Gradient.linear(
          const Offset(12, 15),
          const Offset(88, 88),
          const [Color(0xffc4c4b0), Color(0xff747d79), Color(0xff424f51)],
          const [0, .5, 1],
        ),
    );
    final facets = [
      Path()
        ..moveTo(17, 24)
        ..lineTo(43, 8)
        ..lineTo(51, 45)
        ..lineTo(30, 67)
        ..close(),
      Path()
        ..moveTo(71, 14)
        ..lineTo(92, 36)
        ..lineTo(69, 52)
        ..lineTo(51, 45)
        ..close(),
      Path()
        ..moveTo(30, 67)
        ..lineTo(51, 45)
        ..lineTo(69, 52)
        ..lineTo(78, 91)
        ..lineTo(45, 96)
        ..close(),
    ];
    for (var i = 0; i < facets.length; i++) {
      canvas.drawPath(
        facets[i],
        _paint(
          [
            const Color(0xffb6b9a7),
            const Color(0xff929e98),
            const Color(0xff65716d),
          ][i],
        ),
      );
    }
    canvas.drawPath(rock, _paint(const Color(0xff414b49), 1.4));
    canvas.drawPath(
      Path()
        ..moveTo(43, 10)
        ..lineTo(51, 45)
        ..lineTo(45, 56)
        ..lineTo(50, 64)
        ..lineTo(38, 79)
        ..moveTo(51, 45)
        ..lineTo(69, 52)
        ..lineTo(86, 44),
      _paint(const Color(0xff4a5753), 1),
    );
    canvas.drawLine(
      const Offset(18, 30),
      const Offset(31, 24),
      _paint(const Color(0xffe2dfc4), 1),
    );
  }

  static void _insectSwarm(Canvas canvas, double t) {
    for (var i = 0; i < 42; i++) {
      final x = (t * 820 + i * 83) % 820 - 90, y = 55.0 + (i * 43) % 245;
      canvas.save();
      canvas.translate(x, y + math.sin(t * 35 + i) * 2);
      canvas.rotate(-.1 + math.sin(i * 3.0) * .22);
      canvas.scale(1.0 + i % 3 * .15);
      final p = _paint(const Color(0xff302c2a), 1.2),
          step = math.sin(t * 70 + i);
      for (var side in [-1.0, 1.0]) {
        for (var leg = 0; leg < 3; leg++) {
          final offset = leg * 4.0 - 4;
          canvas.drawPath(
            Path()
              ..moveTo(offset, side * 2)
              ..lineTo(offset - 4, side * (6 + step))
              ..lineTo(offset - 1, side * 9),
            p,
          );
        }
      }
      canvas.drawOval(
        const Rect.fromLTWH(-9, -4, 10, 8),
        _paint(i % 3 == 0 ? const Color(0xff586448) : const Color(0xff493f34)),
      );
      canvas.drawOval(
        const Rect.fromLTWH(-2, -3, 6, 6),
        _paint(const Color(0xff32382e)),
      );
      canvas.drawOval(
        const Rect.fromLTWH(3, -4, 6, 7),
        _paint(const Color(0xff786b4d)),
      );
      canvas.drawPath(
        Path()
          ..moveTo(7, -2)
          ..quadraticBezierTo(13, -9, 15, -6)
          ..moveTo(7, 2)
          ..quadraticBezierTo(14, 9, 16, 5),
        p,
      );
      canvas.drawLine(
        const Offset(-7, -2),
        const Offset(-2, -2),
        _paint(const Color(0xff94906a), .7),
      );
      canvas.restore();
    }
  }

  static void _phoenixFlight(Canvas canvas, double t) {
    final flight = (t / .42).clamp(0.0, 1.0);
    if (t < .55) {
      final alpha = ((.55 - t) / .13).clamp(0.0, 1.0);
      canvas.save();
      canvas.translate(72 + flight * 390, 315 - flight * 245);
      canvas.scale(1.1);
      final flutter = math.sin(flight * math.pi * 5) * .18;
      for (var side in [-1.0, 1.0]) {
        canvas.save();
        canvas.scale(side, 1);
        canvas.rotate(flutter);
        for (var feather = 0; feather < 7; feather++) {
          final end = Offset(38 + feather * 9.0, -31 - feather * 6.0);
          final wing = Path()
            ..moveTo(0, 2)
            ..cubicTo(31, -14, end.dx - 14, end.dy - 17, end.dx, end.dy)
            ..quadraticBezierTo(end.dx + 7, end.dy + 9, 27, 21)
            ..close();
          canvas.drawPath(
            wing,
            _paint(
              Color.lerp(
                const Color(0xffda5439),
                const Color(0xffffd779),
                feather / 7,
              )!.withValues(alpha: alpha),
            ),
          );
          canvas.drawPath(
            wing,
            _paint(const Color(0xff873a30).withValues(alpha: alpha), .6),
          );
        }
        canvas.restore();
      }
      for (var tail = 0; tail < 5; tail++) {
        final x = (tail - 2) * 10.0;
        final path = Path()
          ..moveTo(x * .2, 8)
          ..cubicTo(
            x + 30,
            45,
            x - 40,
            75,
            x + math.sin(flight * 7 + tail) * 27,
            103 + tail * 6.0,
          )
          ..cubicTo(x - 15, 69, x + 40, 37, x * .2 + 4, 8)
          ..close();
        canvas.drawPath(
          path,
          _paint(
            (tail.isEven ? const Color(0xfff4bb59) : const Color(0xffb84337))
                .withValues(alpha: alpha),
          ),
        );
      }
      canvas.drawOval(
        const Rect.fromLTWH(-10, -21, 20, 51),
        _paint(const Color(0xffe89c44).withValues(alpha: alpha)),
      );
      canvas.drawCircle(
        const Offset(0, -26),
        11,
        _paint(const Color(0xffffd472).withValues(alpha: alpha)),
      );
      canvas.drawPath(
        Path()
          ..moveTo(5, -31)
          ..lineTo(22, -25)
          ..lineTo(8, -23)
          ..close(),
        _paint(const Color(0xffc6843f).withValues(alpha: alpha)),
      );
      canvas.drawCircle(
        const Offset(5, -29),
        1.7,
        _paint(const Color(0xff382e2a).withValues(alpha: alpha)),
      );
      canvas.drawPath(
        Path()
          ..moveTo(-5, -34)
          ..quadraticBezierTo(-20, -56, -11, -42)
          ..lineTo(0, -37)
          ..quadraticBezierTo(7, -55, 4, -37),
        _paint(const Color(0xffffe6a1).withValues(alpha: alpha), 2),
      );
      canvas.restore();
    }
    if (t > .32) {
      final fall = ((t - .32) / .68).clamp(0.0, 1.0);
      for (var i = 0; i < 30; i++) {
        final delay = i % 5 * .1, local = (fall - delay).clamp(0.0, 1.0);
        if (local == 0) continue;
        final x = 55.0 + (i * 73) % 530 + math.sin(local * 8 + i) * 19,
            y = -25 + local * (260 + i % 4 * 28);
        canvas.save();
        canvas.translate(x, y);
        canvas.rotate(.3 + math.sin(i + local * 5) * .7);
        final feather = Path()
          ..moveTo(0, -16)
          ..cubicTo(14, -15, 12, 4, 0, 16)
          ..cubicTo(-9, 1, -11, -10, 0, -16)
          ..close();
        canvas.drawPath(
          feather,
          _paint(i.isEven ? const Color(0xfff5cf75) : const Color(0xffc76046)),
        );
        canvas.drawPath(
          Path()
            ..moveTo(0, -13)
            ..quadraticBezierTo(2, 0, 0, 18),
          _paint(const Color(0xfffcf0c2), .7),
        );
        for (var j = 0; j < 4; j++) {
          canvas.drawLine(
            Offset(0, -9 + j * 6.0),
            Offset(6, -12 + j * 6.0),
            _paint(const Color(0xff934d3b), .4),
          );
        }
        canvas.restore();
      }
    }
  }
}

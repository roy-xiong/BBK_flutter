part of 'modern_battle_semantics.dart';

/// 共享本轮已认可的银白剑身、金色护手和深色剑柄，仅替换真实剑体帧。
///
/// 数量、坐标和停留时间全部消费原SRS活动列表，不能另排剑阵或用插值改写飞行。
/// 剑气、刀、剪刀、飞爪等资源仍由原分支绘制，不根据技能名字猜测图形。
abstract final class ModernBattleSwords {
  static const movieIds = {
    '2:2',
    '2:12',
    '2:13',
    '2:15',
    '2:17',
    '2:18',
    '2:201',
    '2:202',
    '2:203',
  };
  static const _palette = [
    Color(0xfffff5dc),
    Color(0xffe6bf73),
    Color(0xffa26c45),
  ];
  static final _outline = Path()
    ..addPath(_Round3Motifs._swordBlade, Offset.zero)
    ..addPath(_Round3Motifs._swordGuard, Offset.zero)
    ..addRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-4, 17, 8, 25),
        const Radius.circular(2),
      ),
    )
    ..addOval(Rect.fromCircle(center: const Offset(0, 44), radius: 5));
  static final Map<double, Rect> _rotatedBounds = {};
  static const _diagonal = -math.pi / 4;

  /// 原图的八方向和剑阵倾角。角度以剑尖向上为零，随原bitmap切换，不自行旋转。
  static double? angle(String id, int image) => switch ((id, image)) {
    ('2:2', >= 0 && <= 7) => (image - 4) * math.pi / 4,
    ('2:12', 0) => math.pi,
    ('2:12', 1) => -math.pi + .36,
    ('2:12', 2) => math.pi - .36,
    ('2:15', 3) => 3 * math.pi / 4,
    ('2:13' || '2:17' || '2:18' || '2:201', 0) => _diagonal,
    ('2:202', >= 0 && <= 3) => 0,
    ('2:203', 4) => math.pi,
    _ => null,
  };

  /// 把原版wide渲染的中心差映射至640画布。first基准只算一次，不能每帧
  /// 按当前图片宽高重新居中，否则11x9太极换19x19剑时会平移到错误位置。
  /// 奇数尺寸的一像素修正来自原版round(width/2)，同一公式用于单体和全体。
  static Offset frameOrigin(
    GameMovie movie,
    int frame,
    Offset anchor, {
    required bool fullScreen,
  }) {
    final header = movie.headers[frame], first = movie.headers.first;
    final image = movie.bitmaps[header[4]], reference = movie.bitmaps[first[4]];
    final odd = Offset(image.width.isOdd ? 1 : 0, image.height.isOdd ? 1 : 0);
    if (fullScreen || image.width == 160 && image.height == 96) {
      return Offset(header[0] * 4.0, header[1] * 4.0) + odd;
    }
    return anchor +
        Offset(
          (header[0] - first[0]) * 4.0 - reference.width * 2,
          (header[1] - first[1]) * 4.0 - reference.height * 2,
        ) +
        odd -
        Offset(reference.width.isOdd ? 1 : 0, reference.height.isOdd ? 1 : 0);
  }

  /// 御魔剑诀的原太极帧重叠时，后帧覆盖前帧；只重画可见的最后一帧。
  /// 飞剑仍在后续主循环逐个绘制，保留太极和首把剑同时存在的原始重叠时段。
  static void drawPrelude(
    Canvas canvas,
    GameMovie movie,
    Offset anchor,
    bool fullScreen,
    List<Color> colors,
  ) {
    if (movie.id != '2:15' && movie.id != '2:203') return;
    List<int>? visible;
    for (final active in movie.active) {
      final image = movie.headers[active[0]][4];
      if (movie.id == '2:203' && image == 0) {
        final origin = frameOrigin(
          movie,
          active[0],
          anchor,
          fullScreen: fullScreen,
        );
        final bitmap = movie.bitmaps[0];
        ModernBattleSemantics._taiji(
          canvas,
          origin + Offset(bitmap.width * 2, bitmap.height * 2),
          85,
          ModernBattleSemantics.progress(movie) * 1.2,
          colors,
        );
      }
      final small = movie.id == '2:15' ? image < 3 : image >= 1 && image <= 3;
      if (small && (visible == null || active[0] > visible[0])) {
        visible = active;
      }
    }
    if (visible == null) return;
    final header = movie.headers[visible[0]], image = movie.bitmaps[header[4]];
    final origin = frameOrigin(
      movie,
      visible[0],
      anchor,
      fullScreen: fullScreen,
    );
    final center =
        origin +
        Offset(
          image.width * 2,
          image.height * 2 - (movie.id == '2:15' ? 12 : 0),
        );
    ModernBattleSemantics._taiji(
      canvas,
      center,
      movie.id == '2:15' ? 64 : 18,
      (header[4] - (movie.id == '2:203' ? 1 : 0)) * math.pi * 2 / 3,
      colors,
    );
  }

  static bool drawFrame(Canvas canvas, String id, int image, Size size) {
    if (id == '2:15' && image < 3) return true;
    if (id == '2:203' && image < 4) return true;
    final rotation = angle(id, image);
    if (rotation == null) return false;
    if (id == '2:202') {
      // 破天一剑先出完整巨剑，再依原图依次裁掉顶端20/40/60像素；
      // 不能把65/45/25像素的剩余剑段都缩成另一把完整短剑。
      canvas.save();
      canvas.clipRect(Offset.zero & size);
      canvas.translate(0, -(85 - size.height));
      _drawBody(canvas, const Size(13, 85), rotation);
      canvas.restore();
    } else {
      _drawBody(canvas, size, rotation);
    }
    return true;
  }

  static void _drawBody(Canvas canvas, Size size, double rotation) {
    // 按真实剑轮廓旋转后的边界适配，不能旋转外接矩形后再缩放，
    // 否则斜剑会被额外缩小，剑柄与剑尖也会偏离原位图的中心。
    final bounds = _rotatedBounds.putIfAbsent(rotation, () {
      final cosine = math.cos(rotation), sine = math.sin(rotation);
      return _outline
          .transform(
            Float64List.fromList([
              cosine,
              sine,
              0,
              0,
              -sine,
              cosine,
              0,
              0,
              0,
              0,
              1,
              0,
              0,
              0,
              0,
              1,
            ]),
          )
          .getBounds();
    });
    // 沿原位图轮廓尺寸适配，同一套造型保留原本大剑/小剑和不同方向的占地。
    const inset = .25;
    canvas.save();
    canvas.translate(inset, inset);
    canvas.scale(
      math.max(.1, size.width - inset * 2) / bounds.width,
      math.max(.1, size.height - inset * 2) / bounds.height,
    );
    canvas.translate(-bounds.left, -bounds.top);
    canvas.rotate(rotation);
    _Round3Motifs._sword(canvas, _palette);
    canvas.restore();
  }
}

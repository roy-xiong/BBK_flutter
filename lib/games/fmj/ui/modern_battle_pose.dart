import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import '../engine/game_actor.dart';
import 'modern_art.dart';

/// 仅补低血休息帧和本回合已执行的防御姿态，不接管原战斗动作或时钟。
///
/// 姿态只读取角色与 ticks：普通、出手、受击、死亡和原异常状态返回 false，
/// 由调用方逐像素沿用原图。这里不缓存角色、图集或原生 Shader，避免退出会话
/// 后仍持有 GPU 图片；临时网格和 Shader 在提交本次绘制后立即释放。
abstract final class ModernBattlePose {
  static final Float64List _identity = Float64List(16)
    ..[0] = 1
    ..[5] = 1
    ..[10] = 1
    ..[15] = 1;
  static const _segments = 24;
  static final List<int> _triangles = [
    for (var y = 0; y < _segments; y++)
      for (var x = 0; x < _segments; x++) ...[
        y * (_segments + 1) + x,
        y * (_segments + 1) + x + 1,
        (y + 1) * (_segments + 1) + x + 1,
        y * (_segments + 1) + x,
        (y + 1) * (_segments + 1) + x + 1,
        (y + 1) * (_segments + 1) + x,
      ],
  ];

  /// 绘制成功返回 true；返回 false 时不修改 Canvas，调用方继续原资源分派。
  ///
  /// 仅在真实 combatFrame=11 且低血时弯身，不能把攻击途中或普通待机中的
  /// 低血角色擅自换姿态。异常状态优先，保留毒伤等已经审核的结算画面。
  static bool draw(
    ui.Canvas canvas,
    ModernArt art,
    GameActor actor,
    ui.Rect target, {
    required bool defending,
    required int ticks,
    required ui.FilterQuality filterQuality,
  }) {
    if (actor.type != 1 ||
        actor.index < 1 ||
        actor.index > 3 ||
        !actor.alive ||
        actor.status & 15 != 0 ||
        target.isEmpty) {
      return false;
    }
    final rest = actor.combatFrame == 1 || actor.combatFrame == 11;
    if (defending && rest) {
      return _guard(canvas, art, actor.index, target, filterQuality);
    }
    if (actor.combatFrame != 11 || actor.hp >= actor.maxHp ~/ 10) {
      return false;
    }
    final sprite = art.sprites['battle:hero:${actor.index}/10'];
    if (sprite == null ||
        sprite.texture >= art.textures.length ||
        sprite.texture < 0 ||
        sprite.rect.isEmpty) {
      return false;
    }
    _weak(canvas, art, sprite, actor.index, target, ticks);
    return true;
  }

  /// 把本人休息图分成连续关节网格：颈部低头、髋部前倾、膝部向前弯曲，
  /// 双脚保持原地。脸、衣服和主要躯干使用局部旋转，不能靠整张压扁冒充虚弱。
  ///
  /// 髋/膝连接处用连续权重保留衣摆，不使用相邻矩形硬切，避免出现腰部断缝。
  /// 只有微弱呼吸角度读取原 ticks，不写 combatFrame，也不创建额外计时器。
  static void _weak(
    ui.Canvas canvas,
    ModernArt art,
    ModernSprite sprite,
    int hero,
    ui.Rect target,
    int ticks,
  ) {
    final (hip, neck, drop) = switch (hero) {
      1 => (.83, .43, .055),
      2 => (.78, .31, .065),
      _ => (.75, .20, .075),
    };
    final hipX = hero == 1 ? .57 : .54;
    final breath = math.sin(ticks * .13 + hero);
    final angle = -.36 + breath * .012;
    final cosine = math.cos(angle), sine = math.sin(angle);
    final positions = <ui.Offset>[], texture = <ui.Offset>[];
    for (var row = 0; row <= _segments; row++) {
      final y = row / _segments;
      final headWeight = ((neck + .035 - y) / .07).clamp(0.0, 1.0);
      final headAngle = -.20 * headWeight;
      final headCos = math.cos(headAngle), headSin = math.sin(headAngle);
      final lower = ((y - hip) / (1 - hip)).clamp(0.0, 1.0);
      final knee = math.sin(math.pi * lower);
      final blend = ((hip + .09 - y) / .18).clamp(0.0, 1.0);
      final torsoWeight = blend * blend * (3 - 2 * blend);
      for (var column = 0; column <= _segments; column++) {
        final x = column / _segments;
        final headX =
            hipX - .045 + headCos * (x - hipX + .045) - headSin * (y - neck);
        final headY = neck + headSin * (x - hipX + .045) + headCos * (y - neck);
        final torsoX =
            hipX + cosine * (headX - hipX) - sine * (headY - hip) + .015;
        final torsoY =
            hip +
            sine * (headX - hipX) +
            cosine * (headY - hip) +
            drop +
            breath * .003;
        final legX = x - .045 * knee + .015 * (1 - lower);
        final legY = y + drop * (1 - lower) + .012 * knee;
        positions.add(
          ui.Offset(
            target.left +
                (torsoX * torsoWeight + legX * (1 - torsoWeight)) *
                    target.width,
            target.top +
                (torsoY * torsoWeight + legY * (1 - torsoWeight)) *
                    target.height,
          ),
        );
        texture.add(
          ui.Offset(
            sprite.rect.left + x * sprite.rect.width,
            sprite.rect.top + y * sprite.rect.height,
          ),
        );
      }
    }
    final vertices = ui.Vertices(
      ui.VertexMode.triangles,
      positions,
      textureCoordinates: texture,
      indices: _triangles,
    );
    final shader = ui.ImageShader(
      art.textures[sprite.texture],
      ui.TileMode.clamp,
      ui.TileMode.clamp,
      _identity,
      filterQuality: ui.FilterQuality.high,
    );
    try {
      _drawWeakMesh(canvas, vertices, shader, target);
    } finally {
      shader.dispose();
      vertices.dispose();
    }
  }

  /// 小画布先在受限临时层中采样，再以真正的图片缩小滤波合成回原位置。
  ///
  /// Skia 软件后端的显式纹理坐标会经过 SkTransformShader，将总矩阵标记为
  /// 不可知；SkImageShader 因而只读取基础 MIP 层。512px 人物直接缩到手机
  /// 画布的约 72px 时，即使 medium 也会跳过大量源像素，出现硬边与闪烁。
  /// 参见官方源码 src/shaders/SkTransformShader.cpp 的 markTotalMatrixInvalid
  /// 以及 src/shaders/SkImageShader.cpp 的 totalMatrixIsValid 分支：
  /// https://github.com/google/skia/blob/main/src/shaders/SkTransformShader.cpp
  /// https://github.com/google/skia/blob/main/src/shaders/SkImageShader.cpp
  ///
  /// 临时层按根 Canvas 变换计算采样倍率，目标约 320 物理像素、最高 4 倍。
  /// 手机 DPR 较高时不再额外放大。只为本次弱态绘制分配小层，不 toImage、
  /// 不做 GPU 缓存；缩回使用 medium 的 MIP 预滤波，不能用事后模糊代替采样。
  static void _drawWeakMesh(
    ui.Canvas canvas,
    ui.Vertices vertices,
    ui.ImageShader shader,
    ui.Rect target,
  ) {
    final transform = canvas.getTransform();
    final scale = math.max(
      math.sqrt(transform[0] * transform[0] + transform[1] * transform[1]),
      math.sqrt(transform[4] * transform[4] + transform[5] * transform[5]),
    );
    final physicalHeight = target.height * scale;
    final samplingScale = physicalHeight.isFinite && physicalHeight > 0
        ? (320 / physicalHeight).clamp(1.0, 4.0)
        : 1.0;
    final paint = ui.Paint()
      ..shader = shader
      ..filterQuality = ui.FilterQuality.high;
    if (samplingScale <= 1) {
      canvas.drawVertices(vertices, ui.BlendMode.srcOver, paint);
      return;
    }
    final downsample = Float64List.fromList(_identity)
      ..[0] = 1 / samplingScale
      ..[5] = 1 / samplingScale;
    final padding = target.height * .3;
    canvas.save();
    canvas.translate(target.left, target.top);
    canvas.saveLayer(
      ui.Rect.fromLTWH(
        -padding * samplingScale,
        -padding * samplingScale,
        (target.width + padding * 2) * samplingScale,
        (target.height + padding * 2) * samplingScale,
      ),
      ui.Paint()
        ..imageFilter = ui.ImageFilter.matrix(
          downsample,
          filterQuality: ui.FilterQuality.medium,
        ),
    );
    try {
      canvas.scale(samplingScale);
      canvas.translate(-target.left, -target.top);
      canvas.drawVertices(vertices, ui.BlendMode.srcOver, paint);
    } finally {
      canvas.restore();
      canvas.restore();
    }
  }

  /// 复用已审核的本人举剑帧，保持原画宽高比与脚底锚点；前方小型盾光
  /// 只说明护体方向，不遮盖人物。动作不新增帧、不推进回合，末帧仍可防守。
  static bool _guard(
    ui.Canvas canvas,
    ModernArt art,
    int hero,
    ui.Rect target,
    ui.FilterQuality filterQuality,
  ) {
    final sprite = art.sprites['battle:hero:$hero/1'];
    if (sprite == null || sprite.rect.isEmpty) return false;
    var height = target.height;
    var width = height * sprite.rect.width / sprite.rect.height;
    final maxWidth = target.height * (190 / 144);
    if (width > maxWidth) {
      height *= maxWidth / width;
      width = maxWidth;
    }
    final guard = ui.Rect.fromLTWH(
      target.center.dx - width / 2,
      target.bottom - height,
      width,
      height,
    );
    final paint = ui.Paint()..filterQuality = filterQuality;
    if (!art.drawSprite(canvas, 'battle:hero:$hero/1', guard, paint)) {
      return false;
    }
    final h = target.height, x = target.center.dx - h * .26;
    final y = target.bottom - h * .64;
    final shield = ui.Path()
      ..moveTo(x, y - h * .14)
      ..quadraticBezierTo(x - h * .14, y - h * .07, x - h * .14, y + h * .04)
      ..quadraticBezierTo(x - h * .13, y + h * .21, x, y + h * .30)
      ..quadraticBezierTo(x + h * .08, y + h * .18, x + h * .08, y + h * .03)
      ..quadraticBezierTo(x + h * .08, y - h * .08, x, y - h * .14)
      ..close();
    canvas.drawPath(shield, paint..color = const ui.Color(0x302aa8b8));
    canvas.drawPath(
      shield,
      paint
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..color = const ui.Color(0xb8c7e9d3),
    );
    return true;
  }
}

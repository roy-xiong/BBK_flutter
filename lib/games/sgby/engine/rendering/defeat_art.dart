import 'dart:math' as math;
import 'dart:ui' as ui;

import 'game_art.dart';

/// 战场退场表现：四个手绘阶段绑定原六帧时隙，共用地面锚点。
///
/// 只读图集并绘制，不改变单位、坐标、结算回调或随机数。水面使用沉没、水纹，
/// 陆地使用失衡、侧倒、接地和短暂扬尘，帧号由原播放器提供。
final class DefeatArt {
  const DefeatArt(this.art);
  final GameArt art;

  void paint({
    required ui.Offset foot,
    required int type,
    required bool friendly,
    required double phase,
    required bool water,
  }) {
    final canvas = art.canvas, assets = art.assets;
    if (assets == null) return;
    final kind = (water ? 3 : type).clamp(0, 5);
    final side = friendly ? 'friendly' : 'enemy';
    final metadata = assets.manifest['defeatAnchors'];
    final anchor = metadata is Map ? metadata['$side/$kind'] : null;
    if (anchor is! List || anchor.length != 3 || anchor.any((v) => v is! num)) {
      return;
    }
    final p = phase.clamp(0.0, 1.0);
    final length = (anchor[2] as num).toDouble();
    if (!length.isFinite || length <= 0 || length > 64) return;
    final rect = ui.Rect.fromLTWH(
      foot.dx - (anchor[0] as num).toDouble() * length,
      foot.dy - (anchor[1] as num).toDouble() * length,
      length,
      length,
    );
    final alpha = (1 - (p - .78) / .22).clamp(0.0, 1.0);
    final frame = (p * 5).round().clamp(0, 5);
    canvas.save();
    canvas.clipRect(const ui.Rect.fromLTWH(0, 0, 240, 128));
    if (!water) {
      canvas.drawOval(
        ui.Rect.fromCenter(center: foot, width: 11 + 3 * p, height: 2.5),
        art.paint(ui.Color.fromRGBO(34, 29, 24, .20 * alpha)),
      );
    }
    canvas.save();
    // 船只低于水线的部分被河面遮住；陆地人物在同一位置接地，不缩放跳位。
    if (water) canvas.clipRect(ui.Rect.fromLTRB(0, 0, 240, foot.dy - .4));
    // 手绘船帧以统一船底归一化；逐步下移并用原水线遮住船体，避免只变淡。
    final target = water && assets.manifest['defeatSinks'] == true
        ? rect.shift(ui.Offset(0, p * 18))
        : rect;
    if (!friendly) {
      canvas.translate(foot.dx * 2, 0);
      canvas.scale(-1, 1);
    }
    assets.sprite(canvas, 'defeat/$side/$kind/$frame', target, opacity: alpha);
    canvas.restore();
    if (water) {
      for (var i = 0; i < 2; i++) {
        final ripple = (p - i * .15).clamp(0.0, 1.0);
        canvas.drawOval(
          ui.Rect.fromCenter(
            center: foot + ui.Offset(0, i * .5),
            width: 6 + ripple * 17,
            height: 1.5 + ripple * 5,
          ),
          art.paint(
            ui.Color.fromRGBO(220, 240, 234, .65 * (1 - p)),
            stroke: .5,
          ),
        );
      }
    } else if (p > .34) {
      // 扬尘在身体接地后出现，体积沿地面扩散，避免一圈固定圆点像爆炸特效。
      final contact = ((p - .34) / .66).clamp(0.0, 1.0);
      final opacity = math.sin(contact * math.pi) * .24;
      for (var i = 0; i < 4; i++) {
        final x = (i - 1.5) * (1.8 + contact * 3);
        final center = foot + ui.Offset(x, -.7 - (i % 2) * .5);
        canvas.drawOval(
          ui.Rect.fromCenter(
            center: center,
            width: 3 + contact * 4,
            height: 1.2 + contact,
          ),
          ui.Paint()
            ..shader = ui.Gradient.radial(center, 4, [
              ui.Color.fromRGBO(150, 132, 100, opacity),
              const ui.Color(0x00968464),
            ]),
        );
      }
    }
    canvas.restore();
  }
}

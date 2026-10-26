import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../engine/rendering/cartoon_assets.dart';
import '../../../../engine/resources/baye_database.dart';
import '../../../../engine/resources/baye_picture.dart';

/// 将领列表的身份头像：彩色使用既有剧照/原图绑定，黑白读取该人物原始位图。
///
/// 图集由GameViewModel拥有，本控件不重复解码、持有定时器或释放共享图片。
/// 资源、时期和人物均允许为空，读档或页面退出期间显示中性占位，避免借用别人的脸。
final class SgbyGeneralPortrait extends StatelessWidget {
  const SgbyGeneralPortrait({
    super.key,
    required this.person,
    required this.period,
    required this.resources,
    required this.label,
    this.assets,
  });

  final int? person, period;
  final BayeDatabase? resources;
  final CartoonAssets? assets;
  final String label;

  @override
  Widget build(BuildContext context) {
    final era = period, id = person;
    final bitmap = era != null && id != null
        ? resources?.pictures(47 + era)?.picture(id)
        : null;
    return Semantics(
      label: label,
      image: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox.square(
          dimension: 48,
          child: CustomPaint(
            painter: _GeneralPortraitPainter(assets, era, id, bitmap),
          ),
        ),
      ),
    );
  }
}

/// 原始位图以连续黑色段合并成路径，首次绘制后复用，不在滚动帧中创建ui.Image。
final class _GeneralPortraitPainter extends CustomPainter {
  _GeneralPortraitPainter(this.assets, this.period, this.person, this.bitmap);
  final CartoonAssets? assets;
  final int? period, person;
  final BayeBitmap? bitmap;
  Path? _ink;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawColor(const Color(0xffb4b4b4), BlendMode.src);
    if (period != null &&
        person != null &&
        assets?.portrait(
              canvas,
              Offset.zero & size,
              period: period,
              person: person,
            ) ==
            true) {
      return;
    }
    final original = bitmap;
    if (original == null) {
      final paint = Paint()..color = const Color(0xff737d7d);
      canvas.drawCircle(
        Offset(size.width * .5, size.height * .34),
        size.width * .16,
        paint,
      );
      canvas.drawOval(
        Rect.fromLTWH(
          size.width * .2,
          size.height * .56,
          size.width * .6,
          size.height * .45,
        ),
        paint,
      );
      return;
    }
    final path = _ink ??= _originalPath(original);
    final scale = math.min(
      size.width / original.width,
      size.height / original.height,
    );
    canvas.save();
    canvas.translate(
      (size.width - original.width * scale) / 2,
      (size.height - original.height * scale) / 2,
    );
    canvas.scale(scale);
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.black
        ..isAntiAlias = false,
    );
    canvas.restore();
  }

  Path _originalPath(BayeBitmap source) {
    final path = Path();
    for (var y = 0; y < source.height; y++) {
      var x = 0;
      while (x < source.width) {
        if (!source.inkAt(x, y)) {
          x++;
          continue;
        }
        final start = x++;
        while (x < source.width && source.inkAt(x, y)) {
          x++;
        }
        path.addRect(
          Rect.fromLTWH(
            start.toDouble(),
            y.toDouble(),
            (x - start).toDouble(),
            1,
          ),
        );
      }
    }
    return path;
  }

  @override
  bool shouldRepaint(_GeneralPortraitPainter old) =>
      old.period != period ||
      old.person != person ||
      !identical(old.assets, assets) ||
      !identical(old.bitmap, bitmap);
}

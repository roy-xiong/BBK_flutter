import 'dart:collection';
import 'dart:math' as math;
import 'package:flutter/painting.dart';
import '../engine/pixel_surface.dart';

/// 系统字体是唯一的文字来源；使用实际字形宽度分页，不按 GBK 字节数切割。
final class FlutterSystemFontLayout implements SystemTextLayout {
  final LinkedHashMap<(String, int, int, int), TextPage> _cache =
      LinkedHashMap();
  static const double fontSize = 14;
  static const double lineHeight = 16;
  static TextStyle style({Color color = const Color(0xff000000)}) => TextStyle(
    color: color,
    fontSize: fontSize,
    height: lineHeight / fontSize,
    fontWeight: FontWeight.w400,
  );
  static const StrutStyle strut = StrutStyle(
    fontSize: fontSize,
    height: lineHeight / fontSize,
    forceStrutHeight: true,
  );

  @override
  TextPage fit(String text, int start, int width, int height) {
    start = start.clamp(0, text.length);
    if (height < lineHeight || start >= text.length) return TextPage('', start);
    final key = (text, start, width, height), cached = _cache.remove(key);
    if (cached != null) {
      _cache[key] = cached;
      return cached;
    }
    final remaining = text.substring(start),
        rows = math.max(1, (height / lineHeight).floor());
    final painter = TextPainter(
      text: TextSpan(text: remaining, style: style()),
      textDirection: TextDirection.ltr,
      maxLines: rows,
      strutStyle: strut,
    );
    painter.layout(maxWidth: width.toDouble());
    var length = remaining.length;
    if (painter.didExceedMaxLines) {
      final lines = painter.computeLineMetrics();
      if (lines.isNotEmpty) {
        final position = painter.getPositionForOffset(
          Offset(width.toDouble() - .01, lines.last.baseline - 1),
        );
        length = painter
            .getLineBoundary(position)
            .end
            .clamp(1, remaining.length);
        // 避免在 UTF-16 代理对中间分页。
        if (length < remaining.length &&
            remaining.codeUnitAt(length) >= 0xdc00 &&
            remaining.codeUnitAt(length) <= 0xdfff) {
          length--;
        }
      }
    }
    painter.dispose();
    final page = TextPage(remaining.substring(0, length), start + length);
    while (_cache.length >= 256) {
      _cache.remove(_cache.keys.first);
    }
    _cache[key] = page;
    return page;
  }
}

import 'dart:ui' as ui;

import 'game_art.dart';

/// 战略城市与战场光标共用的稳定选中态，不依赖闪烁或额外动画时钟。
abstract final class SelectionArt {
  static const gold = ui.Color(0xffffd35c);

  /// 底色先于实体绘制，保留人物与建筑本身的阵营颜色和材质。
  static void backdrop(GameArt art, ui.Rect cell) =>
      art.rounded(cell.deflate(.6), const ui.Color(0x55ffd35c), radius: 2);

  /// 深色外沿、饱和金边与白色角标共同提供亮度和形状差异。
  static void outline(GameArt art, ui.Rect cell) {
    final rect = cell.deflate(1.05);
    art.rounded(rect, const ui.Color(0xff172c32), radius: 1.6, stroke: 2.1);
    art.rounded(rect, gold, radius: 1.6, stroke: 1.35);
    for (final corner in [
      (rect.left, rect.top, 1.0, 1.0),
      (rect.right, rect.top, -1.0, 1.0),
      (rect.left, rect.bottom, 1.0, -1.0),
      (rect.right, rect.bottom, -1.0, -1.0),
    ]) {
      art.path(
        [
          ui.Offset(corner.$1 + corner.$3 * 3, corner.$2),
          ui.Offset(corner.$1, corner.$2),
          ui.Offset(corner.$1, corner.$2 + corner.$4 * 3),
        ],
        const ui.Color(0xfffff5cb),
        stroke: .55,
      );
    }
  }

  /// 已选部队仍保持金框，浏览目的地时另用白框表示光标。
  static void cursor(GameArt art, ui.Rect cell) {
    final rect = cell.deflate(.9);
    art.rounded(rect, const ui.Color(0xff172c32), radius: 1.5, stroke: 1.9);
    art.rounded(rect, const ui.Color(0xfffff8e4), radius: 1.5, stroke: .75);
  }
}

import 'dart:ui';
import 'original_tile_catalog.dart';

/// 原图分类只有一份离线目录，避免绘制器自行猜测同一编号范围的物件语义。
final class ModernTerrain {
  const ModernTerrain._();
  static String base(int tileset) => switch (tileset) {
    2 || 9 => 'earth',
    3 => 'wood-cross',
    8 => 'cave',
    _ => 'stone',
  };
  static (String, String, String?)? _rule(int tileset, int tile) {
    final list = originalTileCatalog[tileset];
    return list != null && tile >= 0 && tile < list.length ? list[tile] : null;
  }

  static String sceneMaterial(int tileset, int tile, bool walkable) =>
      tileset == 8
      ? (walkable ? 'cave' : 'cave-wall')
      : _rule(tileset, tile)?.$1 ?? base(tileset);
  static String? material(int tileset, int tile) => _rule(tileset, tile)?.$1;
  static String? structureKey(int tileset, int tile) =>
      _rule(tileset, tile)?.$3;
  static String role(int tileset, int tile) =>
      _rule(tileset, tile)?.$2 ?? 'source-detail';
  static String? tree(int tileset, int tile) {
    if (tileset == 9 && (tile >= 2 && tile <= 8 || tile >= 46 && tile <= 49)) {
      return 'camphor';
    }
    if (tileset == 2 && tile >= 2 && tile <= 7) return 'camphor';
    if (tileset == 2 && tile >= 8 && tile <= 14) return 'pine';
    if (tileset == 2 && (tile == 18 || tile == 19) ||
        tileset == 9 && tile == 9) {
      return 'bamboo';
    }
    return null;
  }

  static bool rock(int tileset, int tile) => role(tileset, tile) == 'rock';
  static String? overlay(int tileset, int tile) =>
      switch (role(tileset, tile)) {
        'fence-h' => 'fence-h',
        'fence-v' => 'fence-v',
        'stone-steps' => 'steps',
        _ => null,
      };

  /// 旧备用图集保留连续取样接口；正式地面通过世界原点 ImageShader 绘制。
  static Rect source(Rect sprite, int x, int y) {
    const span = 8;
    final width = sprite.width / span, height = sprite.height / span;
    int column(int value) {
      final p = value % (span * 2);
      return p < span ? p : span * 2 - 1 - p;
    }

    return Rect.fromLTWH(
      sprite.left + column(x) * width,
      sprite.top + column(y) * height,
      width,
      height,
    );
  }

  static bool mirrored(int coordinate) => coordinate % 16 >= 8;
  static double variation(int x, int y, int salt) =>
      (((x * 73856093) ^ (y * 19349663) ^ (salt * 83492791)) & 1023) / 1023;
}

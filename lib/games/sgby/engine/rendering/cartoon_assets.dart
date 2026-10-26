import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';

/// 卡通写实纹理的会话级所有者。一次解码、重复绘制，销毁后释放GPU图片。
///
/// 图集坐标只读，不在paint阶段读文件、创建解码器或生成临时图片。加载失败和
/// 过期初始化均由调用方处理，dispose幂等，避免页面重建留下旧图集。
final class CartoonAssets {
  CartoonAssets._(this.atlas, this.map, this.texture, this.manifest);
  final ui.Image atlas, map, texture;
  final Map<String, dynamic> manifest;
  bool _disposed = false;

  static Future<CartoonAssets> load({AssetBundle? bundle}) async {
    final assets = bundle ?? rootBundle;
    final images = <ui.Image>[];
    try {
      final json = jsonDecode(
        await assets.loadString('assets/sgby/art/manifest.json'),
      );
      if (json is! Map<String, dynamic> || json['sprites'] is! Map) {
        throw const FormatException('卡通美术索引无效');
      }
      for (final name in [
        'atlas.png',
        'strategy_map.png',
        'battle_texture.png',
      ]) {
        final bytes = await assets.load('assets/sgby/art/$name');
        final codec = await ui.instantiateImageCodec(
          bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        );
        try {
          images.add((await codec.getNextFrame()).image);
        } finally {
          codec.dispose();
        }
      }
      return CartoonAssets._(images[0], images[1], images[2], json);
    } catch (_) {
      for (final image in images) {
        image.dispose();
      }
      rethrow;
    }
  }

  ui.Rect? spriteRect(String key) {
    final raw = (manifest['sprites'] as Map)[key];
    if (_disposed ||
        raw is! List ||
        raw.length != 4 ||
        raw.any((v) => v is! num)) {
      return null;
    }
    final rect = ui.Rect.fromLTWH(
      (raw[0] as num).toDouble(),
      (raw[1] as num).toDouble(),
      (raw[2] as num).toDouble(),
      (raw[3] as num).toDouble(),
    );
    return rect.isEmpty ||
            rect.left < 0 ||
            rect.top < 0 ||
            rect.right > atlas.width ||
            rect.bottom > atlas.height
        ? null
        : rect;
  }

  bool sprite(
    ui.Canvas canvas,
    String key,
    ui.Rect target, {
    double opacity = 1,
    ui.FilterQuality filterQuality = ui.FilterQuality.medium,
  }) {
    final source = spriteRect(key);
    if (source == null || target.isEmpty) return false;
    canvas.drawImageRect(
      atlas,
      source,
      target,
      ui.Paint()
        ..filterQuality = filterQuality
        ..color = ui.Color.fromRGBO(255, 255, 255, opacity.clamp(0, 1)),
    );
    return true;
  }

  bool portrait(
    ui.Canvas canvas,
    ui.Rect target, {
    int? period,
    int? person,
    String? name,
  }) {
    if (_disposed) return false;
    final key = period != null && person != null
        ? (manifest['portraitIds'] as Map)['portrait/$period/$person']
        : (manifest['portraitNames'] as Map)[name ?? '曹操'];
    if (key is! String) return false;
    final source = spriteRect(key);
    if (source == null || target.isEmpty) return false;
    // 未找到剧照时保留该人物、该时期的原始黑白头像，不拉伸、不染色或平滑字点。
    final scale =
        (target.width / source.width) < (target.height / source.height)
        ? target.width / source.width
        : target.height / source.height;
    final fitted = ui.Rect.fromCenter(
      center: target.center,
      width: source.width * scale,
      height: source.height * scale,
    );
    return sprite(
      canvas,
      key,
      fitted,
      filterQuality: key.startsWith('original/')
          ? ui.FilterQuality.none
          : ui.FilterQuality.medium,
    );
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    atlas.dispose();
    map.dispose();
    texture.dispose();
  }
}

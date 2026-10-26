import 'package:flutter/material.dart';

/// 合集首页统一的图片入口；解码失败时保留可点击的游戏卡片。
abstract final class ImageManager {
  static Widget asset(String name, {BoxFit fit = BoxFit.contain}) =>
      Image.asset(
        name,
        fit: fit,
        excludeFromSemantics: true,
        errorBuilder: (_, _, _) =>
            const Center(child: Icon(Icons.videogame_asset_outlined, size: 44)),
      );
}

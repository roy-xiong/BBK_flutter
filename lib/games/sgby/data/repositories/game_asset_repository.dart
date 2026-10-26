import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../engine/resources/baye_archive.dart';
import '../../engine/resources/baye_database.dart';
import '../../engine/resources/bitmap_font.dart';
import '../../engine/resources/gbk_codec.dart';

/// 应用资产入口，平台读取与纯Dart资源模型分离。
///
/// 文件读取完成后在独立isolate解析，不在界面构建期间扫描码表或资源索引。
/// 返回值只包含Dart数据，不传递AssetBundle、BuildContext或原生图片资源。
final class GameAssetRepository {
  GameAssetRepository({AssetBundle? bundle}) : _bundle = bundle ?? rootBundle;

  final AssetBundle _bundle;

  Future<BayeDatabase> load() async {
    const paths = <String>[
      'assets/sgby/game/SGBY-Reset-4X.lib',
      'assets/sgby/game/gbk_unicode.bin',
      'assets/sgby/game/fallback_font12.bin',
      'assets/sgby/game/refined_rules.json',
    ];
    // 测试或自定义AssetBundle可返回SynchronousFuture。显式异步包装，避免
    // 同步then在Future.wait登记全部任务前触发，造成结果列表被清空。
    final values = await Future.wait(
      paths.map((path) async => await _bundle.load(path)),
    );
    final bytes = <Uint8List>[
      for (final value in values)
        value.buffer.asUint8List(value.offsetInBytes, value.lengthInBytes),
    ];
    final manifest = await AssetManifest.loadFromAssetBundle(_bundle);
    const androidFontPath = 'assets/sgby/game/android_font48.bin';
    if (manifest.listAssets().contains(androidFontPath)) {
      final font = await _bundle.load(androidFontPath);
      bytes.add(
        font.buffer.asUint8List(font.offsetInBytes, font.lengthInBytes),
      );
    }
    return compute(_decodeAssets, bytes);
  }
}

/// compute入口必须为顶层函数，避免捕获界面或仓库实例。
BayeDatabase _decodeAssets(List<Uint8List> bytes) {
  final rules = jsonDecode(utf8.decode(bytes[3]));
  if (rules is! Map<String, dynamic>) {
    throw const FormatException('精修配置格式无效');
  }
  return BayeDatabase(
    archive: BayeArchive(bytes[0]),
    codec: GbkCodec(bytes[1]),
    font: BitmapFont(
      bytes[2],
      androidAtlas: bytes.length > 4 ? bytes[4] : null,
    ),
    refinedRules: rules,
  );
}

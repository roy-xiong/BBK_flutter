import 'dart:convert';
import 'dart:io';
import 'package:bbk_flutter/games/sgby/engine/resources/baye_archive.dart';
import 'package:bbk_flutter/games/sgby/engine/resources/baye_database.dart';
import 'package:bbk_flutter/games/sgby/engine/resources/bitmap_font.dart';
import 'package:bbk_flutter/games/sgby/engine/resources/gbk_codec.dart';

/// 领域回归使用固定磁盘资源，不持有Flutter图片或平台通道。
BayeDatabase loadGameDatabase() => BayeDatabase(
  archive: BayeArchive(
    File('assets/sgby/game/SGBY-Reset-4X.lib').readAsBytesSync(),
  ),
  codec: GbkCodec(File('assets/sgby/game/gbk_unicode.bin').readAsBytesSync()),
  font: BitmapFont(
    File('assets/sgby/game/fallback_font12.bin').readAsBytesSync(),
  ),
  refinedRules:
      jsonDecode(File('assets/sgby/game/refined_rules.json').readAsStringSync())
          as Map<String, dynamic>,
);

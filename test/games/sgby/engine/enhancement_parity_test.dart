import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:bbk_flutter/games/sgby/data/services/game_save_codec.dart';
import 'package:bbk_flutter/games/sgby/domain/use_cases/game_enhancements.dart';
import 'package:bbk_flutter/games/sgby/domain/models/game_options.dart';
import 'package:bbk_flutter/games/sgby/engine/resources/baye_archive.dart';
import 'package:bbk_flutter/games/sgby/engine/resources/baye_database.dart';
import 'package:bbk_flutter/games/sgby/engine/resources/bitmap_font.dart';
import 'package:bbk_flutter/games/sgby/engine/resources/gbk_codec.dart';

/// 当前增强脚本的实际结果，覆盖未来武将、全地图新势力和俘虏装备回收。
void main() {
  late BayeDatabase database;
  late List<dynamic> samples;
  setUpAll(() {
    database = BayeDatabase(
      archive: BayeArchive(
        File('assets/sgby/game/SGBY-Reset-4X.lib').readAsBytesSync(),
      ),
      codec: GbkCodec(
        File('assets/sgby/game/gbk_unicode.bin').readAsBytesSync(),
      ),
      font: BitmapFont(
        File('assets/sgby/game/fallback_font12.bin').readAsBytesSync(),
      ),
      refinedRules:
          jsonDecode(
                File('assets/sgby/game/refined_rules.json').readAsStringSync(),
              )
              as Map<String, dynamic>,
    );
    samples =
        jsonDecode(
              File(
                'test/games/sgby/fixtures/reference_cheats.json',
              ).readAsStringSync(),
            )
            as List;
  });
  for (var index = 0; index < 9; index++) {
    test('当前增强脚本逐字段对照，样本$index', () {
      final sample = samples[index] as Map;
      final codec = GameSaveCodec(), base = database.loadPeriod(1, seed: 1);
      database.beginGame(base, 5);
      final envelope = codec.encode(base);
      final saved = Map<String, dynamic>.from(envelope['world']! as Map)
        ..addAll(Map<String, dynamic>.from(sample['before'] as Map));
      final world = codec.decode(<String, dynamic>{
        ...envelope,
        'world': saved,
      });
      final enhancements = GameEnhancements(database, GameOptions());
      final result = enhancements.apply(
        world,
        sample['action'] as String,
        selectedCity: 0,
      );
      expect(result.isSuccess, sample['result']['ok']);
      for (final field in (sample['after'] as Map).keys) {
        expect(
          world.toJson()[field],
          sample['after'][field],
          reason: '${sample['action']} / $field',
        );
      }
    });
  }
}

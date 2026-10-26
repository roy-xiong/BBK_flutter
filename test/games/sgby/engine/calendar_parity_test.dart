import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:bbk_flutter/games/sgby/data/services/game_save_codec.dart';
import 'package:bbk_flutter/games/sgby/domain/use_cases/advance_calendar.dart';
import 'package:bbk_flutter/games/sgby/engine/resources/baye_archive.dart';
import 'package:bbk_flutter/games/sgby/engine/resources/baye_database.dart';
import 'package:bbk_flutter/games/sgby/engine/resources/bitmap_font.dart';
import 'package:bbk_flutter/games/sgby/engine/resources/gbk_codec.dart';

/// 十二个月的前后数据从当前仓库WASM的tacticStage4/5采集，隔离AI与订单阶段。
/// 同时比较人物、城市、在野/物品队列和随机状态，能发现运算截断及随机次序偏差。
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
                'test/games/sgby/fixtures/reference_calendar.json',
              ).readAsStringSync(),
            )
            as List;
  });

  for (var month = 0; month < 12; month++) {
    test('旧内核月结逐字段对照，第${month + 1}个月', () {
      final sample = samples[month] as Map;
      final before = Map<String, dynamic>.from(sample['before'] as Map);
      final codec = GameSaveCodec();
      final envelope = codec.encode(database.loadPeriod(1, seed: 1));
      final saved = Map<String, dynamic>.from(envelope['world']! as Map)
        ..addAll(before);
      final world = codec.decode(<String, dynamic>{
        ...envelope,
        'world': saved,
      });
      AdvanceCalendar(database)(world);
      final actual = world.toJson();
      for (final field in (sample['after'] as Map).keys) {
        expect(
          actual[field],
          sample['after'][field],
          reason: '月${month + 1} / $field',
        );
      }
    });
  }
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:bbk_flutter/games/sgby/data/services/game_save_codec.dart';
import 'package:bbk_flutter/games/sgby/domain/models/game_order.dart';
import 'package:bbk_flutter/games/sgby/domain/use_cases/execute_strategy_order.dart';
import 'package:bbk_flutter/games/sgby/engine/resources/baye_archive.dart';
import 'package:bbk_flutter/games/sgby/engine/resources/baye_database.dart';
import 'package:bbk_flutter/games/sgby/engine/resources/bitmap_font.dart';
import 'package:bbk_flutter/games/sgby/engine/resources/gbk_codec.dart';

/// 旧OrderExec实际执行前后采样，覆盖搜寻、招降、移动、外交和资源输送。
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
                'test/games/sgby/fixtures/reference_orders.json',
              ).readAsStringSync(),
            )
            as List;
  });
  for (var index = 0; index < 30; index++) {
    test('旧内核订单执行逐字段对照，样本$index', () {
      final sample = samples[index] as Map;
      final codec = GameSaveCodec();
      final base = database.loadPeriod(1, seed: 1);
      database.beginGame(base, 5);
      final envelope = codec.encode(base);
      final saved = Map<String, dynamic>.from(envelope['world']! as Map)
        ..addAll(Map<String, dynamic>.from(sample['before'] as Map));
      final world = codec.decode(<String, dynamic>{
        ...envelope,
        'world': saved,
      });
      final data = sample['order'] as Map;
      final order = GameOrder(
        orderId: data['OrderId'] as int,
        person: data['Person'] as int,
        city: data['City'] as int,
        object: data['Object'] as int,
        arms: data['Arms'] as int,
        food: data['Food'] as int,
        money: data['Money'] as int,
        consume: data['Consume'] as int,
        timeCount: data['TimeCount'] as int,
      );
      ExecuteStrategyOrder(database, dialogs: database.strategyDialogs)(
        world,
        order,
      );
      final actual = world.toJson();
      for (final field in (sample['after'] as Map).keys) {
        expect(
          actual[field],
          sample['after'][field],
          reason: '样本$index / 指令${order.orderId} / $field',
        );
      }
    });
  }
}

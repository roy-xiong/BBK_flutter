import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:bbk_flutter/games/sgby/data/services/game_save_codec.dart';
import 'package:bbk_flutter/games/sgby/domain/use_cases/computer_strategy.dart';
import 'package:bbk_flutter/games/sgby/engine/resources/baye_archive.dart';
import 'package:bbk_flutter/games/sgby/engine/resources/baye_database.dart';
import 'package:bbk_flutter/games/sgby/engine/resources/bitmap_font.dart';
import 'package:bbk_flutter/games/sgby/engine/resources/gbk_codec.dart';

/// 关闭活跃度保留旧内核逐字段对照；外交开启时验证合法目标及固定种子的可重放性。
///
/// 旧采样包含对同势力武将下达外交命令，修复后不能继续把这些错误输出作为预期。
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
                'test/games/sgby/fixtures/reference_ai.json',
              ).readAsStringSync(),
            )
            as List;
  });
  for (var index = 0; index < 20; index++) {
    test('AI决策对照与外交目标回归，样本$index', () {
      final sample = samples[index] as Map;
      final codec = GameSaveCodec();
      final envelope = codec.encode(database.loadPeriod(1, seed: 1));
      final before = Map<String, dynamic>.from(sample['before'] as Map)
        ..remove('orders');
      final saved = Map<String, dynamic>.from(envelope['world']! as Map)
        ..addAll(before);
      final world = codec.decode(<String, dynamic>{
        ...envelope,
        'world': saved,
      });
      ComputerStrategy(database)(world, activity: sample['activity'] as int);
      final actual = world.toJson();
      if (sample['activity'] != 0) {
        final replay = codec.decode(<String, dynamic>{
          ...envelope,
          'world': saved,
        });
        ComputerStrategy(database)(replay, activity: sample['activity'] as int);
        expect(actual, replay.toJson(), reason: '同一世界与随机种子应产生相同结果');
        for (final order in world.orders) {
          if (![15, 16, 17, 19].contains(order.orderId)) continue;
          final actor = world.person(order.person);
          final target = world.person(order.object);
          expect(actor, isNotNull);
          expect(target, isNotNull);
          expect(actor?.belong, isNot(target?.belong), reason: '外交不能针对同势力');
          expect(target?.belong, isNot(0));
          expect(target?.belong, isNot(65535));
        }
        return;
      }
      for (final field in (sample['after'] as Map).keys) {
        if (field == 'orders') continue;
        expect(
          actual[field],
          sample['after'][field],
          reason: '样本$index / $field',
        );
      }
      final expectedOrders = sample['after']['orders'] as List;
      expect(world.orders.length, expectedOrders.length);
      for (var i = 0; i < expectedOrders.length; i++) {
        final expected = expectedOrders[i] as Map;
        final order = world.orders[i].toJson();
        for (final field in expected.keys) {
          // 普通内政的Object在旧版部分分支未初始化，执行阶段也不读取。
          if (field == 'Object' &&
              ![3, 14, 15, 16, 17, 19, 27].contains(order['OrderId'])) {
            continue;
          }
          expect(
            order[field],
            expected[field],
            reason: '样本$index / 订单$i / $field',
          );
        }
      }
    });
  }
}

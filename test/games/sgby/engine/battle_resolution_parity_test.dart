import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:bbk_flutter/games/sgby/data/services/game_save_codec.dart';
import 'package:bbk_flutter/games/sgby/domain/models/game_order.dart';
import 'package:bbk_flutter/games/sgby/domain/use_cases/battle_engine.dart';
import 'package:bbk_flutter/games/sgby/domain/use_cases/resolve_battle.dart';
import 'package:bbk_flutter/games/sgby/engine/resources/baye_archive.dart';
import 'package:bbk_flutter/games/sgby/engine/resources/baye_database.dart';
import 'package:bbk_flutter/games/sgby/engine/resources/bitmap_font.dart';
import 'package:bbk_flutter/games/sgby/engine/resources/gbk_codec.dart';

/// 旧BattleDrv/FightResultDeal实际结算，覆盖五种处置、攻守结果和路线开关。
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
                'test/games/sgby/fixtures/reference_battle_resolution.json',
              ).readAsStringSync(),
            )
            as List;
  });
  for (var index = 0; index < 20; index++) {
    test('旧内核战后结算逐字段对照，样本$index', () {
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
      final order = GameOrder(
        orderId: 27,
        person: 0,
        city: 8,
        object: 3,
        arms: 0,
        food: 5000,
        money: 0,
        consume: 0,
        timeCount: 0,
        fighters: [58, 60],
      );
      final resolver = ResolveBattle(database), engine = BattleEngine(database);
      final battle = resolver.prepare(world, order).battle!;
      engine.initialize(world, battle);
      battle.result = sample['result'] as int;
      engine.finish(world, battle);
      resolver(
        world,
        battle,
        loserOutcome: [
          'original',
          'death',
          'captive',
          'escape',
          'wild',
        ].indexOf(sample['outcome'] as String),
        enemyEscapeRoute: sample['route'] == true,
      );
      for (final field in (sample['afterResolution'] as Map).keys) {
        expect(
          world.toJson()[field],
          sample['afterResolution'][field],
          reason: '样本$index / ${sample['outcome']} / $field',
        );
      }
    });
  }
}

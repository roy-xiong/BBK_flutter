import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:bbk_flutter/games/sgby/data/services/game_save_codec.dart';
import 'package:bbk_flutter/games/sgby/domain/models/game_battle.dart';
import 'package:bbk_flutter/games/sgby/domain/use_cases/battle_engine.dart';
import 'package:bbk_flutter/games/sgby/engine/resources/baye_archive.dart';
import 'package:bbk_flutter/games/sgby/engine/resources/baye_database.dart';
import 'package:bbk_flutter/games/sgby/engine/resources/bitmap_font.dart';
import 'package:bbk_flutter/games/sgby/engine/resources/gbk_codec.dart';

/// 旧FgtDrvCmd的36组兵种交叉伤害，包含不同地形、float系数与经验/随机状态。
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
                'test/games/sgby/fixtures/reference_attack.json',
              ).readAsStringSync(),
            )
            as List;
  });
  for (var index = 0; index < 36; index++) {
    test('旧内核普通攻击逐字段对照，兵种组合$index', () {
      final sample = samples[index] as Map, params = sample['params'] as Map;
      final codec = GameSaveCodec(), base = database.loadPeriod(1, seed: 1);
      database.beginGame(base, 5);
      final envelope = codec.encode(base),
          saved = Map<String, dynamic>.from(codec.encode(base)['world']! as Map)
            ..addAll(
              Map<String, dynamic>.from(sample['enemyBefore']['world'] as Map),
            );
      final world = codec.decode(<String, dynamic>{
        ...envelope,
        'world': saved,
      });
      final battle = GameBattle(
        mode: params['mode'] as int,
        city: params['city'] as int,
        sourceCity: 8,
        way: params['way'] as int,
        mapId: params['mapId'] as int,
        playerFood: 5000,
        enemyFood: 5000,
        people: (params['people'] as List).cast<int?>(),
      );
      battle.width = sample['width'] as int;
      battle.height = sample['height'] as int;
      battle.cityX = sample['cityX'] as int;
      battle.cityY = sample['cityY'] as int;
      battle.weather = sample['enemyBefore']['weather'] as int;
      battle.map = database
          .requiredItem(battle.mapId)
          .sublist(16, 16 + battle.width * battle.height);
      for (var i = 0; i < 20; i++) {
        final p = sample['enemyBefore']['units'][i] as Map;
        battle.units[i]
          ..x = p['x'] as int
          ..y = p['y'] as int
          ..hp = p['hp'] as int
          ..mp = p['mp'] as int
          ..move = p['move'] as int
          ..active = p['active'] as int
          ..state = p['state'] as int;
      }
      final engine = BattleEngine(database);
      engine.path(world, battle, 10);
      engine.execute(world, battle, const BattleCommand(10, 0, target: 0));
      for (final field in (sample['enemyAfter']['world'] as Map).keys) {
        expect(
          world.toJson()[field],
          sample['enemyAfter']['world'][field],
          reason: '组合$index / $field',
        );
      }
      for (var i = 0; i < 20; i++) {
        if (battle.people[i] != null) {
          expect(
            battle.units[i].toJson(),
            sample['enemyAfter']['units'][i],
            reason: '组合$index / 槽$i',
          );
        }
      }
    });
  }
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:bbk_flutter/games/sgby/data/services/game_save_codec.dart';
import 'package:bbk_flutter/games/sgby/domain/models/game_order.dart';
import 'package:bbk_flutter/games/sgby/domain/models/game_battle.dart';
import 'package:bbk_flutter/games/sgby/domain/use_cases/battle_ai.dart';
import 'package:bbk_flutter/games/sgby/domain/use_cases/battle_engine.dart';
import 'package:bbk_flutter/games/sgby/domain/use_cases/resolve_battle.dart';
import 'package:bbk_flutter/games/sgby/engine/resources/baye_archive.dart';
import 'package:bbk_flutter/games/sgby/engine/resources/baye_database.dart';
import 'package:bbk_flutter/games/sgby/engine/resources/bitmap_font.dart';
import 'package:bbk_flutter/games/sgby/engine/resources/gbk_codec.dart';

/// 实际旧内核BattleDrv/enterBattle采集的三个地图、两个种子初始化快照。
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
                'test/games/sgby/fixtures/reference_battle_init.json',
              ).readAsStringSync(),
            )
            as List;
  });
  for (var index = 0; index < 6; index++) {
    test('旧内核战场初始化逐字段对照，样本$index', () {
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
      final params = sample['params'] as Map;
      final order = GameOrder(
        orderId: 27,
        person: 0,
        city: 8,
        object: params['city'] as int,
        arms: 0,
        food: 5000,
        money: 0,
        consume: 0,
        timeCount: 0,
        fighters: [5, 58, 60],
      );
      final prepared = ResolveBattle(database).prepare(world, order);
      final battle = prepared.battle!;
      expect(battle.way, params['way']);
      expect(battle.mapId, params['mapId']);
      expect(battle.people, params['people']);
      BattleEngine(database).initialize(world, battle);
      expect(battle.width, sample['width']);
      expect(battle.height, sample['height']);
      expect(battle.cityX, sample['cityX']);
      expect(battle.cityY, sample['cityY']);
      expect(world.random.state, sample['after']['randomSeed']);
      for (var i = 0; i < 20; i++) {
        final expected = sample['units'][i] as Map,
            actual = battle.units[i].toJson();
        for (final field in expected.keys) {
          if (battle.people[i] == null &&
              !['x', 'y', 'state'].contains(field)) {
            continue;
          }
          expect(
            actual[field],
            expected[field],
            reason: '样本$index / 槽$i / $field',
          );
        }
      }
      for (final field in ['persons', 'cities', 'personQueue', 'goodsQueue']) {
        expect(
          world.toJson()[field],
          sample['after'][field],
          reason: '样本$index / $field',
        );
      }
    });
  }
  test('六组旧内核敌方战场行动与移动范围逐字段对照', () {
    final samples =
        jsonDecode(
              File(
                'test/games/sgby/fixtures/reference_battle_enemy.json',
              ).readAsStringSync(),
            )
            as List;
    for (var sampleIndex = 0; sampleIndex < samples.length; sampleIndex++) {
      final sample = samples[sampleIndex] as Map,
          params = sample['params'] as Map;
      final codec = GameSaveCodec(), base = database.loadPeriod(1, seed: 1);
      database.beginGame(base, 5);
      final envelope = codec.encode(base);
      final saved = Map<String, dynamic>.from(envelope['world']! as Map)
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
        sourceCity: params['sourceCity'] as int,
        way: params['way'] as int,
        mapId: params['mapId'] as int,
        playerFood: params['playerFood'] as int,
        enemyFood: params['enemyFood'] as int,
        people: (params['people'] as List).cast<int?>(),
      );
      final map = database.requiredItem(battle.mapId);
      battle.width = sample['width'] as int;
      battle.height = sample['height'] as int;
      battle.map = map.sublist(16, 16 + battle.width * battle.height);
      battle.cityX = sample['cityX'] as int;
      battle.cityY = sample['cityY'] as int;
      battle.weather = sample['enemyBefore']['weather'] as int;
      battle.day = 1;
      for (var i = 0; i < 20; i++) {
        final data = sample['enemyBefore']['units'][i] as Map;
        battle.units[i]
          ..x = data['x'] as int
          ..y = data['y'] as int
          ..hp = data['hp'] as int
          ..mp = data['mp'] as int
          ..move = data['move'] as int
          ..active = data['active'] as int
          ..state = data['state'] as int;
      }
      final engine = BattleEngine(database),
          ai = BattleAi(BattleEngine(database));
      final paths = sample['paths'] as List;
      var actions = 0;
      while (battle.result == 0) {
        if (actions < paths.length) {
          final expected = paths[actions] as Map;
          final path = engine.path(world, battle, expected['source'] as int);
          expect(
            [path.left, path.top, path.useX, path.useY],
            [
              expected['left'],
              expected['top'],
              expected['useX'],
              expected['useY'],
            ],
          );
          expect(
            path.values,
            (expected['values'] as List).take(225).toList(),
            reason: '样本$sampleIndex / 行动$actions / 移动范围',
          );
        }
        final command = ai.nextEnemy(world, battle);
        if (command == null) break;
        expect(
          command.source,
          paths[actions]['source'],
          reason: '样本$sampleIndex / 行动$actions / 顺序',
        );
        engine.execute(world, battle, command);
        actions++;
        expect(actions, lessThanOrEqualTo(10));
      }
      expect(actions, paths.length);
      expect(
        world.random.state,
        sample['enemyAfter']['world']['randomSeed'],
        reason: '样本$sampleIndex / 随机状态',
      );
      for (var i = 0; i < 20; i++) {
        if (battle.people[i] == null) continue;
        expect(
          battle.units[i].toJson(),
          sample['enemyAfter']['units'][i],
          reason: '样本$sampleIndex / 武将$i',
        );
      }
      for (final field in ['persons', 'cities', 'personQueue', 'goodsQueue']) {
        expect(
          world.toJson()[field],
          sample['enemyAfter']['world'][field],
          reason: '样本$sampleIndex / $field',
        );
      }
    }
  });
}

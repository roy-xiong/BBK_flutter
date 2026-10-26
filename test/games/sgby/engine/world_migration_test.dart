import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:bbk_flutter/games/sgby/data/services/game_save_codec.dart';
import 'package:bbk_flutter/games/sgby/engine/core/native_game_session.dart';
import 'package:bbk_flutter/games/sgby/engine/resources/baye_archive.dart';
import 'package:bbk_flutter/games/sgby/engine/resources/baye_database.dart';
import 'package:bbk_flutter/games/sgby/engine/resources/bitmap_font.dart';
import 'package:bbk_flutter/games/sgby/engine/resources/gbk_codec.dart';

/// 对照数据由当前旧WASM的真实LoadPeriod和精修Hook采集，非Dart实现生成。
void main() {
  late BayeDatabase database;
  late List<dynamic> reference;
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
    reference =
        jsonDecode(
              File(
                'test/games/sgby/fixtures/reference_periods.json',
              ).readAsStringSync(),
            )
            as List;
  });

  for (var period = 1; period <= 4; period++) {
    test('时期$period人物与城市逐字段匹配旧内核开局快照', () {
      final world = database.loadPeriod(period, seed: 1);
      final expected = reference[period - 1] as Map;
      expect(world.year, expected['year']);
      expect(world.month, expected['month']);
      expect(world.persons.length, 200);
      expect(world.cities.length, 38);
      final people = (expected['persons'] as List)
          .map(
            (value) => Map<String, dynamic>.from(value as Map)..remove('name'),
          )
          .toList();
      final cities = (expected['cities'] as List)
          .map(
            (value) => Map<String, dynamic>.from(value as Map)..remove('name'),
          )
          .toList();
      expect(world.persons.map((value) => value.toJson()).toList(), people);
      expect(world.cities.map((value) => value.toJson()).toList(), cities);
      // C的全局数组尾部可能留有前一时期未使用的字节，只比较城池实际占用段。
      final used = world.cities.fold<int>(
        0,
        (count, city) => count + city.persons,
      );
      expect(
        world.personQueue.take(used).toList(),
        (expected['personQueue'] as List).take(used).toList(),
      );
    });

    test('时期$period精修属性保留武将覆盖与装备加成', () {
      final world = database.loadPeriod(period, seed: 1);
      database.beginGame(world, database.rulers(world).first);
      final expected = reference[period - 1] as Map;
      final people = expected['afterRefinedHook'] as List;
      for (var i = 0; i < people.length; i++) {
        final actual = world.persons[i];
        final record = people[i] as Map;
        final actualFields = actual.toJson()..remove('Arms');
        final expectedFields = Map<String, dynamic>.from(record)
          ..remove('Arms');
        expect(actualFields, expectedFields, reason: '武将$i精修属性');
      }
      final tools = expected['tools'] as List;
      for (var i = 0; i < tools.length; i++) {
        final record = tools[i] as Map;
        final actual = world.tools[i];
        expect(
          [actual.attack, actual.iq, actual.move, actual.arm, actual.useFlag],
          [
            record['at'],
            record['iq'],
            record['move'],
            record['arm'],
            record['useflag'],
          ],
        );
      }
    });
  }

  test('开场到战略地图的输入链和城市详情取消路径闭合', () {
    final session = NativeGameSession(database, seedProvider: () => 1);
    session.input(NativeInput.confirm);
    expect(session.scene, NativeScene.mainMenu);
    session.input(NativeInput.confirm);
    expect(session.scene, NativeScene.periodMenu);
    session.input(NativeInput.confirm);
    expect(session.scene, NativeScene.rulers);
    session.input(NativeInput.confirm);
    expect(session.scene, NativeScene.strategy);
    expect(session.world?.playerRulerIndex, 5);
    session.input(NativeInput.confirm);
    expect(session.scene, NativeScene.menu);
    for (var i = 0; i < 3; i++) {
      session.input(NativeInput.down);
    }
    session.input(NativeInput.confirm);
    expect(session.scene, NativeScene.cityInfo);
    session.input(NativeInput.cancel);
    expect(session.scene, NativeScene.strategy);
    session.dispose();
    final version = session.frameVersion;
    session.input(NativeInput.confirm);
    session.advance(const Duration(seconds: 3));
    expect(session.frameVersion, version);
    expect(session.world, isNull);
  });

  test('保存快照不共享后续记录修改，随机状态可精确恢复', () {
    final world = database.loadPeriod(1, seed: 1);
    database.beginGame(world, database.rulers(world).first);
    world.random.next();
    world.random.next();
    final codec = GameSaveCodec();
    final snapshot = codec.encode(world);
    final oldForce = world.persons[0].force;
    world.setPerson(0, world.persons[0].copyWith(force: oldForce + 1));
    final restored = codec.decode(snapshot);
    expect(restored.persons[0].force, oldForce);
    expect(restored.random.next(), world.random.next());
    expect(restored.personQueue, world.personQueue);
  });

  test('存档引用验证及战场显示参数恢复', () {
    final world = database.loadPeriod(1, seed: 1);
    database.beginGame(world, 5);
    final codec = GameSaveCodec();
    for (final field in ['ArmsType', 'Equip']) {
      final bad =
          jsonDecode(jsonEncode(codec.encode(world))) as Map<String, dynamic>;
      final person = bad['world']['persons'][0] as Map;
      person[field] = field == 'ArmsType' ? 6 : [world.tools.length + 1, 0];
      expect(() => codec.decode(bad), throwsFormatException);
    }
    world.lookBattleMovie = false;
    world.slowBattleMovement = false;
    expect(codec.decode(codec.encode(world)).lookBattleMovie, isFalse);
    expect(codec.decode(codec.encode(world)).slowBattleMovement, isFalse);
  });

  test('损坏的存档数值被拒绝，不能修改现有会话', () {
    final world = database.loadPeriod(1, seed: 1);
    final codec = GameSaveCodec();
    final snapshot =
        jsonDecode(jsonEncode(codec.encode(world))) as Map<String, dynamic>;
    ((snapshot['world'] as Map)['persons'] as List)[0]['Belong'] = -1;
    expect(() => codec.decode(snapshot), throwsFormatException);
    expect(world.persons[0].belong, 1);
  });
}

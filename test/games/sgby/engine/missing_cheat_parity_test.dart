import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:bbk_flutter/games/sgby/data/services/game_save_codec.dart';
import 'package:bbk_flutter/games/sgby/domain/models/game_options.dart';
import 'package:bbk_flutter/games/sgby/domain/models/hidden_general_backup.dart';
import 'package:bbk_flutter/games/sgby/domain/use_cases/game_enhancements.dart';
import 'package:bbk_flutter/games/sgby/engine/resources/baye_archive.dart';
import 'package:bbk_flutter/games/sgby/engine/resources/baye_database.dart';
import 'package:bbk_flutter/games/sgby/engine/resources/bitmap_font.dart';
import 'package:bbk_flutter/games/sgby/engine/resources/gbk_codec.dart';

/// 固定BBK e210eda实际WASM/增强脚本产生的独立快照，覆盖20万数值和特殊君主。
void main() {
  test('遗漏作弊与当前BBK的13步状态、队列及随机流逐字段一致', () {
    final database = BayeDatabase(
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
    final samples =
        jsonDecode(
              File(
                'test/games/sgby/fixtures/reference_missing_cheats.json',
              ).readAsStringSync(),
            )
            as List;
    final options = GameOptions(),
        enhancements = GameEnhancements(database, options),
        codec = GameSaveCodec();
    final base = database.loadPeriod(1, seed: 1);
    database.beginGame(base, 5);
    final envelope = codec.encode(base);
    var backups = <int, HiddenGeneralBackup>{};
    for (final sample in samples) {
      final saved = Map<String, dynamic>.from(envelope['world'] as Map)
        ..addAll(Map<String, dynamic>.from(sample['before'] as Map));
      final world = codec.decode(<String, dynamic>{
        ...envelope,
        'world': saved,
      });
      world.hiddenGenerals.addAll(backups);
      final result = enhancements.apply(
        world,
        sample['action'] as String,
        parameters: Map<String, Object?>.from(sample['parameters'] as Map),
      );
      expect(
        result.isSuccess,
        sample['result']['ok'],
        reason: sample['name'] as String,
      );
      for (final field in (sample['after'] as Map).keys) {
        expect(
          world.toJson()[field],
          sample['after'][field],
          reason: '${sample['name']} / $field',
        );
      }
      for (final key in [
        'enemyArmsLimitEnabled',
        'autoSaveAfterTurn',
        'diplomacyProtection',
        'hideSpecialGenerals',
      ]) {
        expect(
          options.enabled(key),
          sample['state'][key],
          reason: '${sample['name']} / $key',
        );
      }
      expect(options.enemyArmsLimit, sample['state']['enemyArmsLimit']);
      backups = Map.of(world.hiddenGenerals);
    }
  });
}

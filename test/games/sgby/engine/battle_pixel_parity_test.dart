import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bbk_flutter/games/sgby/data/repositories/game_asset_repository.dart';
import 'package:bbk_flutter/games/sgby/data/services/game_save_codec.dart';
import 'package:bbk_flutter/games/sgby/domain/models/game_battle.dart';
import 'package:bbk_flutter/games/sgby/engine/core/battle_flow.dart';
import 'package:bbk_flutter/games/sgby/engine/core/native_game_session.dart';
import 'package:bbk_flutter/games/sgby/engine/rendering/game_display_enhancements.dart';

import '../support/pixel_artifact.dart';

/// 在当前旧内核中实际进入战斗后采集完整帧，不由Dart代码生成参考像素。
/// 闪烁兵种和形势点对齐整帧相位，所有960×576像素均参与比较。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final name in [
    'map',
    'information',
    'situation_enemy',
    'situation_player',
    'main_menu',
    'animation_menu',
  ]) {
    test('手机字模与旧内核战场整帧对照：$name', () async {
      final database = await GameAssetRepository().load();
      final samples =
          jsonDecode(
                File(
                  'test/games/sgby/fixtures/reference_pixels_battle.json',
                ).readAsStringSync(),
              )
              as List;
      final sample = samples.firstWhere((s) => s['name'] == name) as Map;
      final codec = GameSaveCodec(), base = database.loadPeriod(1, seed: 1);
      database.beginGame(base, 5);
      final envelope = codec.encode(base);
      final saved = Map<String, dynamic>.from(envelope['world']! as Map)
        ..addAll(Map<String, dynamic>.from(sample['world'] as Map));
      final world = codec.decode(<String, dynamic>{
        ...envelope,
        'world': saved,
      });
      world.lookBattleMovie = false;
      world.slowBattleMovement = false;
      world.lookEnemyMovement = false;
      final b = sample['battle'] as Map, p = b['params'] as Map;
      final battle = GameBattle(
        mode: p['mode'] as int,
        city: p['city'] as int,
        sourceCity: p['sourceCity'] as int,
        way: p['way'] as int,
        mapId: p['mapId'] as int,
        playerFood: p['playerFood'] as int,
        enemyFood: p['enemyFood'] as int,
        people: (p['people'] as List).cast<int?>(),
      );
      battle.width = b['width'] as int;
      battle.height = b['height'] as int;
      battle.cityX = b['cityX'] as int;
      battle.cityY = b['cityY'] as int;
      battle.viewX = b['viewX'] as int;
      battle.viewY = b['viewY'] as int;
      battle.focusX = b['focusX'] as int;
      battle.focusY = b['focusY'] as int;
      battle.weather = b['weather'] as int;
      battle.day = b['day'] as int;
      battle.map = database
          .requiredItem(battle.mapId)
          .sublist(16, 16 + battle.width * battle.height);
      for (var i = 0; i < 20; i++) {
        final u = b['units'][i] as Map;
        battle.units[i]
          ..x = u['x'] as int
          ..y = u['y'] as int
          ..hp = u['hp'] as int
          ..mp = u['mp'] as int
          ..move = u['move'] as int
          ..active = u['active'] as int
          ..state = u['state'] as int;
      }
      final session = NativeGameSession(database)..replaceWorld(world);
      final flow = BattleFlow(session, battle, completed: () {});
      void render(int phase) {
        flow.renderer.draw(world, battle, frame: phase);
        if (name == 'information') flow.renderer.information(world, battle);
        if (name.startsWith('situation_')) {
          flow.renderer.situation(
            world,
            battle,
            name == 'situation_enemy' ? 1 : 0,
            0,
            blink: phase == 1,
          );
        }
      }

      render(0);
      if (name.endsWith('menu')) {
        flow.input(NativeInput.cancel);
        if (name == 'animation_menu') {
          session.input(NativeInput.down);
          session.input(NativeInput.down);
          session.input(NativeInput.confirm);
        }
      }
      final display = GameDisplayEnhancements(database);
      var actual = display.frame(
        session.canvas.surface,
        world,
        strategy: false,
        factionColors: true,
        roads: false,
        playerBattle: true,
      );
      final expected = gzip.decode(
        File(
          'test/games/sgby/fixtures/pixels_battle_$name.rgba.gz',
        ).readAsBytesSync(),
      );
      if (!name.endsWith('menu') && !listEquals(actual, expected)) {
        render(1);
        actual = display.frame(
          session.canvas.surface,
          world,
          strategy: false,
          factionColors: true,
          roads: false,
          playerBattle: true,
        );
      }
      var difference = 0, minX = 960, minY = 576, maxX = 0, maxY = 0;
      for (var i = 0; i < actual.length; i += 4) {
        if (actual[i] != expected[i] ||
            actual[i + 1] != expected[i + 1] ||
            actual[i + 2] != expected[i + 2] ||
            actual[i + 3] != expected[i + 3]) {
          difference++;
          final x = i ~/ 4 % 960, y = i ~/ 4 ~/ 960;
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
        }
      }
      if (difference != 0) {
        Directory('.dart_tool/pixel_failures').createSync(recursive: true);
        File(
          '.dart_tool/pixel_failures/battle_$name.rgba',
        ).writeAsBytesSync(actual);
      }
      session.dispose();
      expect(
        difference,
        0,
        reason: '$name: $difference个像素不同，范围($minX,$minY)~($maxX,$maxY)',
      );
      await exportPixelFrame(actual, 'battle_$name');
    });
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bbk_flutter/games/fmj/data/game_data.dart';
import 'package:bbk_flutter/games/fmj/engine/game_actor.dart';
import 'package:bbk_flutter/games/fmj/engine/game_engine.dart';
import 'package:bbk_flutter/games/fmj/ui/modern_art.dart';
import 'package:bbk_flutter/games/fmj/ui/modern_scene.dart';
import 'package:bbk_flutter/games/fmj/ui/game_page.dart'
    show ClassicFramePainter;
import 'package:bbk_flutter/games/fmj/ui/system_font_layout.dart';
import 'game_engine_test.dart' show loadData;

/// 仅在单独的审核流水线导出；调用真实战斗状态机与Painter，不修改产品逻辑。
/// 逐个案例持有帧并立即编码释放，不同时保存全部案例的大量解码位图。
void main() {
  if (Platform.environment['FMJ_EXPORT_BATTLE_REVIEW'] != '1') return;
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('按40ms原时钟导出全部战斗动作，固定一倍速', (tester) async {
    await tester.runAsync(() async {
      final format = Platform.environment['FMJ_REVIEW_FORMAT'] == 'webp'
          ? 'webp'
          : 'gif';
      final classic = Platform.environment['FMJ_REVIEW_CLASSIC'] == '1';
      final patch = Platform.environment['FMJ_REVIEW_PATCH'] == '1';
      final selected = <String>{};
      if (patch) {
        final feedback =
            jsonDecode(
                  File(
                    'tool/fmj_battle_review_feedback_round2.json',
                  ).readAsStringSync(),
                )
                as Map;
        for (final row
            in (feedback['groupReviews'] as Map).values.cast<Map>()) {
          final written =
              (row['comment'] as String? ?? '').trim().isNotEmpty ||
              (row['markers'] as List? ?? []).cast<Map>().any(
                (m) => (m['comment'] as String? ?? '').trim().isNotEmpty,
              );
          if (written) selected.addAll((row['caseIds'] as List).cast<String>());
        }
        expect(selected, hasLength(48), reason: '本轮只重录有文字意见的10组、48个关联案例');
      }
      final shard = int.parse(Platform.environment['FMJ_REVIEW_SHARD'] ?? '0');
      final shards = int.parse(
        Platform.environment['FMJ_REVIEW_SHARDS'] ?? '4',
      );
      final catalog =
          jsonDecode(
                File('build/battle-review/catalog.json').readAsStringSync(),
              )
              as Map;
      final data = await loadData();
      final art = await ModernArt.load();
      final font = FontLoader('BBK CJK')
        ..addFont(rootBundle.load('assets/fonts/NotoSansCJKsc-Regular.otf'));
      await font.load();
      final root = Directory('build/battle-review')
        ..createSync(recursive: true);
      final records = <Map<String, dynamic>>[];
      try {
        final cases = catalog['cases'] as List;
        for (var index = shard; index < cases.length; index += shards) {
          final entry = Map<String, dynamic>.from(cases[index] as Map);
          if (patch && !selected.contains(entry['id'])) continue;
          final game =
              GameEngine(
                  data,
                  textLayout: FlutterSystemFontLayout(),
                  random: math.Random(1000 + index),
                )
                ..screen = 'play'
                ..intro = null
                ..allowMiss = false;
          game.preferences.addAll({
            'runSpeed': 1,
            'autoBattle': false,
            'invincible': false,
            'oneHitKill': false,
            'modernUi': !classic,
          });
          for (var id = 1; id <= 3; id++) {
            final hero = GameActor.load(data, 1, id)!;
            hero.levelUp(data, 50);
            hero.maxHp = 999;
            hero.hp = 800;
            hero.maxMp = 999;
            hero.mp = 999;
            hero.equipment.fillRange(0, hero.equipment.length, null);
            game.players.add(hero);
          }
          final enemyCase = entry['actorType'] == 3;
          final enemyId = enemyCase ? entry['actor'] as int : 44;
          final group = entry['all'] == true || entry['kind'] == 'coop';
          final battle = GameBattle(
            game,
            monsters: group ? [enemyId, 5, 42] : [enemyId],
            background: [2, 2, 2],
            randomFight: true,
          );
          game.battle = battle;
          for (final enemy in battle.monsters) {
            enemy.maxHp = 999;
            enemy.hp = 800;
            enemy.maxMp = 999;
            enemy.mp = 999;
          }
          final actor = enemyCase
              ? battle.monsters.first
              : game.players.firstWhere((p) => p.index == entry['actor']);
          final kind = entry['kind'] as String;
          final resource = entry['resource'] as String?;
          final allies = enemyCase ? battle.monsters : game.players;
          final opponents = enemyCase ? game.players : battle.monsters;
          final helper = allies.firstWhere(
            (p) => !identical(p, actor),
            orElse: () => actor,
          );
          BattleAction? action;
          var staticTicks = 0;
          if (kind == 'weak' || kind == 'death' && !enemyCase) {
            actor.hp = kind == 'weak' ? 1 : 0;
            actor.combatFrame = kind == 'weak' ? 11 : 12;
            staticTicks = 40;
          } else if (kind == 'status') {
            final mask = entry['mask'] as int;
            actor.status = mask & 15;
            actor.statusRounds.addAll({
              for (final bit in [1, 2, 4, 8])
                if (mask & bit != 0) bit: 3,
            });
            action = BattleAction(actor, [actor], 'item')
              ..started = true
              ..stage = 2
              ..originX = actor.combatX
              ..originY = actor.combatY;
            action.raises.add(
              BattleRaise(
                data,
                actor.combatX,
                actor.combatY,
                0,
                mask,
                actor: actor,
              ),
            );
            battle.current = action;
          } else if (kind == 'movie') {
            action = BattleAction(actor, battle.monsters, 'magic')
              ..started = true
              ..stage = 1
              ..originX = actor.combatX
              ..originY = actor.combatY
              ..movie = (GameMovie(data, 2, entry['movie'] as int)
                ..iterations = 2);
            battle.current = action;
          } else if (kind == 'hit' || kind == 'death') {
            final attacker = enemyCase
                ? game.players.first
                : battle.monsters.first;
            actor.hp = kind == 'death' ? 30 : 800;
            actor.defense = 0;
            attacker.attack = 80;
            action = BattleAction(attacker, [actor], 'attack');
          } else if (kind == 'flee-fail' || kind == 'flee-success') {
            action = BattleAction(
              actor,
              [],
              'flee',
              fleeSucceeded: kind == 'flee-success',
            );
          } else if (kind == 'poison') {
            actor.status = 8;
            actor.statusRounds[8] = 3;
            action = BattleAction(actor, [actor], 'defend');
          } else if (kind == 'coop') {
            game.players.first.equipment[0] = entry['equipment'] as String?;
            action = BattleAction(actor, battle.monsters, 'coop');
          } else {
            final support =
                kind == 'help' ||
                kind == 'item' ||
                kind == 'defend' ||
                kind == 'self';
            final targets = kind == 'defend' || kind == 'self'
                ? [actor]
                : support
                ? (group ? allies : [helper])
                : group
                ? opponents
                : [opponents.first];
            if (support && kind != 'defend' && kind != 'self') {
              for (final target in targets) {
                target.hp = 200;
                target.mp = 200;
              }
              if (kind == 'help' &&
                  resource != null &&
                  game.magic(resource)?.byte(0) == 4) {
                targets.first.hp = 0;
                targets.first.combatFrame = 12;
              }
            }
            if (kind == 'item' || kind == 'throw') {
              game.inventory[resource!] = 1;
            }
            action = BattleAction(actor, targets, kind, resource: resource);
          }
          battle.phase = 'perform';
          if (action != null && !action.started) battle.queue.add(action);
          final folder = Directory('${root.path}/frames-${entry['id']}')
            ..createSync(recursive: true);
          final timeline = <Map<String, Object>>[];
          final movies = <String>{};
          Uint8List? last;
          var frameCount = 0, started = action?.started ?? false;
          final states = <String>{};
          Future<void> capture() async {
            final recorder = ui.PictureRecorder();
            if (classic) {
              // 使用正式黑白渲染入口和同一动作时钟，不能把彩色帧去色冒充原版。
              game.render();
              final surface = game.surface;
              final decoded = Completer<ui.Image>();
              ui.decodeImageFromPixels(
                surface.pixels.buffer.asUint8List(),
                surface.width,
                surface.height,
                ui.PixelFormat.bgra8888,
                decoded.complete,
              );
              final pixels = await decoded.future;
              try {
                ClassicFramePainter(
                  pixels,
                  surface.textRuns,
                  surface.width,
                  surface.height,
                  false,
                ).paint(Canvas(recorder), const Size(640, 384));
              } finally {
                pixels.dispose();
              }
            } else {
              ModernScenePainter(
                game,
                art,
                textStyle: const TextStyle(fontFamily: 'BBK CJK'),
              ).paint(Canvas(recorder), const Size(640, 384));
            }
            final picture = recorder.endRecording();
            final image = await picture.toImage(640, 384);
            try {
              final bytes = (await image.toByteData(
                format: ui.ImageByteFormat.png,
              ))!.buffer.asUint8List();
              if (last != null && listEquals(last, bytes)) {
                timeline.last['ms'] = (timeline.last['ms'] as int) + 40;
              } else {
                final filename =
                    '${timeline.length.toString().padLeft(4, '0')}.png';
                File('${folder.path}/$filename').writeAsBytesSync(bytes);
                timeline.add({'file': filename, 'ms': 40});
                last = Uint8List.fromList(bytes);
              }
              frameCount++;
            } finally {
              image.dispose();
              picture.dispose();
            }
          }

          try {
            await capture();
            for (var tick = 0; tick < 1000; tick++) {
              if (staticTicks > 0) {
                game.ticks++;
                staticTicks--;
                await capture();
                if (staticTicks == 0) break;
                continue;
              }
              game.update();
              expect(game.error, isEmpty, reason: entry['title'] as String);
              final current = battle.current;
              if (current != null) {
                started = true;
                states.add('${current.kind}:${current.stage}');
                if (current.movie != null) {
                  movies.add(current.movie!.id);
                }
              }
              for (final raise in battle.visibleRaises) {
                movies.addAll(raise.movies.map((m) => m.id));
              }
              await capture();
              if (started && current == null && battle.visibleRaises.isEmpty) {
                break;
              }
              if (game.battle != battle) break;
              expect(tick, lessThan(999), reason: '${entry['id']} 动画未结束');
            }
            timeline.last['ms'] = (timeline.last['ms'] as int) + 600;
            File(
              '${folder.path}/timeline.json',
            ).writeAsStringSync(jsonEncode(timeline));
            final output =
                '${root.path}/${entry['id']}${classic ? '-classic' : ''}.$format';
            final encoded = await Process.run('python3', [
              'tool/encode_fmj_battle_gif.py',
              folder.path,
              output,
            ]);
            expect(
              encoded.exitCode,
              0,
              reason: '${entry['id']} ${encoded.stderr}',
            );
            final info = jsonDecode(encoded.stdout as String) as Map;
            records.add({
              ...entry,
              'renderStyle': classic ? 'classic' : 'color',
              'simulationFrames': frameCount,
              'durationMs': frameCount * 40,
              'loopGapMs': 600,
              'observedMovies': movies.toList(),
              'observedStates': states.toList(),
              'gifFrames': info['frames'],
              'gifBytes': info['bytes'],
              'gifDurationMs': info['durationMs'],
              if (info['extension'] == 'webp') ...{
                'webpFrames': info['frames'],
                'webpBytes': info['bytes'],
                'webpDurationMs': info['durationMs'],
              },
            });
          } finally {
            folder.deleteSync(recursive: true);
          }
          if (records.length % 15 == 0) {
            debugPrint(
              'shard $shard: ${records.length} / ~${(cases.length / shards).ceil()}',
            );
          }
        }
        File(
          '${root.path}/${patch
              ? 'patch-'
              : classic
              ? 'classic-'
              : ''}shard-$shard.json',
        ).writeAsStringSync(jsonEncode(records));
        expect(records, isNotEmpty);
      } finally {
        art.dispose();
      }
    });
  }, timeout: const Timeout(Duration(minutes: 45)));
}

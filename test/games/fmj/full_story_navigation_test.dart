import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:bbk_flutter/games/fmj/engine/game_engine.dart';
import 'package:bbk_flutter/games/fmj/ui/system_font_layout.dart';
import 'game_engine_test.dart' show loadData;

/// 从新游戏连续推进，不用选关、传送、补物品或写剧情标志掩盖导航断点。
/// 战斗使用游戏内已有的无敌/一击必杀辅助，仍经过真实胜利、奖励及剧情指令。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('完整故事一键直达：开局、主线、可用支线、最终结局', () async {
    final game = GameEngine(
      await loadData(),
      textLayout: FlutterSystemFontLayout(),
      random: math.Random(24),
    );
    final trace = <Map<String, dynamic>>[];
    void record(String action, [Object? detail]) {
      final row = <String, dynamic>{
        'action': action,
        'script': game.cursor?.script.id,
        'position': [game.player?.x, game.player?.y],
        'detail': detail,
      };
      trace.add(row);
      // ignore: avoid_print
      print('STORY ${jsonEncode(row)}');
    }

    Future<void> settle() async {
      String? previousScript;
      for (var frame = 0; frame < 60000; frame++) {
        if (game.navigation.planning) {
          // 隔离区使用真实 CPU 时间；不能在主隔离区几毫秒内空转数万模拟帧，
          // 把仍正常运行的规划误判为未完成。
          await Future<void>.delayed(const Duration(milliseconds: 1));
        }
        game.update();
        if (game.cursor?.script.id != previousScript) {
          previousScript = game.cursor?.script.id;
          record('transfer', previousScript);
        }
        expect(game.error, isEmpty, reason: '${trace.lastOrNull}');
        if (frame % 10 == 0) {
          await Future<void>.delayed(Duration.zero);
        }
        final op = game.operation;
        if (op?.kind == 'choice' || op?.kind == 'menu') {
          // 放走老王才能体验密道支线；其余选择接受任务、归还、用钥匙。
          final index = op!.scriptId == '5:18' ? 0 : op.options.length - 1;
          record(
            'choice',
            '${op.scriptId}@${op.address}: ${op.options[index]}',
          );
          game.choose(index, expected: op);
        } else if (op != null &&
            {'dialogue', 'message', 'timed'}.contains(op.kind)) {
          game.press(GameKey.confirm);
        }
        if (game.menus.isNotEmpty) game.press(GameKey.cancel);
        if (game.ended) return;
        if (game.canSave &&
            !game.navigation.planning &&
            game.navigation.active == null &&
            game.route.isEmpty) {
          return;
        }
      }
      fail(
        '导航或剧情未结束：${game.notice} / ${trace.lastOrNull} / '
        'op=${game.operation?.kind}:${game.operation?.text}:${game.operation?.start}:${game.operation?.next} '
        'battle=${game.battle?.phase}:${game.battle?.round} '
        'target=${game.battle?.targetKind} '
        'planning=${game.navigation.planning} route=${game.route.length} '
        'at=${game.cursor?.script.id}:${game.player?.x},${game.player?.y} '
        'cursor=${game.cursor?.running}:${game.cursor?.pointer}',
      );
    }

    try {
      for (final key in [
        'invincible',
        'oneHitKill',
        'autoBattle',
        'randomBattleDisabled',
        'modernUi',
      ]) {
        game.setPreference(key, true);
      }
      game.setPreference('runSpeed', 4);
      game.startNewGame();
      await settle();
      final repeats = <String, int>{};
      for (var step = 0; step < 180 && !game.ended; step++) {
        final goal = game.navigation.nextGoal;
        if (goal.event == 0 && goal.label.startsWith('装备')) {
          final candidates = game.inventory.keys.toList();
          for (final id in candidates) {
            final name = game.goodsName(id);
            if (!name.contains('芦藤') && !name.contains('天心灯')) continue;
            for (final actor in game.players) {
              if ((game.inventory[id] ?? 0) > 0 && game.equip(actor, id)) {
                record('equip', '${actor.name}:$name');
                break;
              }
            }
          }
        }
        final state =
            '${goal.label}/${game.cursor?.script.id}/'
            '${game.player?.x},${game.player?.y}/${game.flags.toList()..sort()}/'
            '${game.variables}/${game.inventory}';
        repeats[state] = (repeats[state] ?? 0) + 1;
        expect(repeats[state], lessThan(4), reason: '目标反复不推进：${goal.label}');
        record('goal', '${goal.label} => ${goal.scriptId}:${goal.event}');
        await game.navigation.startGoal();
        await settle();
        record('arrived', game.notice);
        if (game.cursor?.script.id == '5:16' && !game.flags.contains(214)) {
          expect(
            game.navigation.sideGoals.any(
              (g) => g.ready && g.scriptId == '5:16',
            ),
            isTrue,
            reason: '消耗最后一把钥匙后仍必须能走到小画家面前救人',
          );
        }
      }
      expect(game.flags.contains(214), isTrue, reason: '完整路线必须真正救出小画家');
      expect(game.flags.contains(260), isTrue);
      expect(game.ended, isTrue, reason: '必须经最终剧情进入结局');
      record('complete', game.flags.toList()..sort());
    } finally {
      game.navigation.cancel();
      Directory('build/validation').createSync(recursive: true);
      File(
        'build/validation/full-story-navigation.json',
      ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(trace));
    }
  }, timeout: const Timeout(Duration(minutes: 12)));
}

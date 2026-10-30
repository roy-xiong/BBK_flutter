import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bbk_flutter/games/fmj/data/game_data.dart';
import 'package:bbk_flutter/games/fmj/engine/game_engine.dart';
import 'package:bbk_flutter/games/fmj/ui/dialogue_presentation.dart';
import 'package:bbk_flutter/games/fmj/ui/system_font_layout.dart';
import 'game_engine_test.dart' show loadData;

/// 同时覆盖原始脚本全集及真实柜台事件，防止只替换一处“路人”字符串。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GameData data;
  late Map<String, dynamic> initial;
  setUpAll(() async {
    data = await loadData();
    initial =
        jsonDecode(
              File(
                'test/games/fmj/fixtures/navigation_start.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
  });
  GameEngine engine() => GameEngine(data, textLayout: FlutterSystemFontLayout())
    ..restore(initial)
    ..setPreference('modernUi', true);

  test('185段脚本632条对白逐条署名，98条无署名对白不会串入路人身份', () {
    final game = engine();
    final before = jsonEncode(game.snapshot());
    final prefix = RegExp(r'^([^：:\r\n，。！？!?]{1,16})[：:]');
    var dialogues = 0, unprefixed = 0, unattributed = 0;
    expect(data.scripts, hasLength(185));
    for (final script in data.scripts.values) {
      for (final command in script.commands.where((c) => c.opcode == 13)) {
        final op =
            GameOperation('dialogue', text: command.string, args: command.args)
              ..scriptId = script.id
              ..address = command.address
              ..next = command.string.length
              ..speakerName = '路人'; // 模拟前一个场景遗留的通用名字。
        final rendered = DialoguePresentation.from(game, op);
        final explicit = prefix.firstMatch(command.string);
        if (command.arg(0) == 0 && explicit == null) unprefixed++;
        if (script.id == '2:43' && command.address == 317) {
          expect(rendered.speaker, isNull, reason: '不替原版未确定署名的边界提示编造人物');
          unattributed++;
        } else if (script.id == '7:14' && command.address == 15) {
          expect(rendered.speaker, '路人', reason: '抓小偷事件原文明确为路人，必须保留');
        } else {
          expect(
            rendered.speaker,
            isNotNull,
            reason: '${script.id}/${command.address}',
          );
          expect(
            rendered.speaker,
            isNot('路人'),
            reason: '${script.id}/${command.address}',
          );
          expect(rendered.speaker!.contains('Npc'), false);
          expect(rendered.speaker!.contains('goods'), false);
        }
        expect(
          rendered.text,
          explicit == null
              ? command.string
              : command.string.substring(explicit.end),
        );
        expect(op.text, command.string);
        expect(op.start, 0);
        expect(op.next, command.string.length);
        dialogues++;
      }
    }
    expect(dialogues, 632);
    expect(unprefixed, 98);
    expect(unattributed, 1);
    expect(jsonEncode(game.snapshot()), before, reason: '署名展示不能修改存档、物品或剧情');
  });

  test('全部23家常规商店的真实柜台对话与购买出售入口均可达', () {
    final stores = data.scripts.values
        .where(
          (script) =>
              script.id != '2:52' &&
              script.commands.any((c) => c.opcode == 28 || c.opcode == 45),
        )
        .toList();
    expect(stores, hasLength(23));
    for (final script in stores) {
      for (final wide in [true, false]) {
        final game = engine()..setPreference('wideView', wide);
        game.npcs.clear();
        game.inventory['9:1'] = 2;
        game.cursor = ScriptCursor(script);
        for (var tick = 0; tick < 80; tick++) {
          game.update();
          if (game.cursor?.running == false && game.operation == null) break;
        }
        expect(game.triggerEvent(42), true, reason: script.id);
        final title = script.name.contains('武器')
            ? '武器店掌柜'
            : script.name.contains('当铺')
            ? '当铺掌柜'
            : script.name.contains('杂货铺')
            ? '杂货铺掌柜'
            : script.name.contains('杂货')
            ? '杂货店掌柜'
            : script.name.contains('药铺')
            ? '药铺掌柜'
            : script.name.contains('药店')
            ? '药店掌柜'
            : '药房掌柜';
        final seen = <String?>{};
        for (var tick = 0; tick < 240; tick++) {
          game.update();
          final op = game.operation;
          if (op?.kind == 'dialogue') {
            seen.add(DialoguePresentation.from(game, op!).speaker);
            game.press(GameKey.confirm);
          }
          if (game.menus.isNotEmpty) break;
        }
        expect(game.error, isEmpty, reason: script.id);
        expect(seen, {title}, reason: '${script.id} ${script.name}');
        expect(game.menus.last.kind, 'inventory', reason: script.id);
        expect(
          game.menus.last.mode,
          script.commands.any((c) => c.opcode == 45) ? 'sell' : 'buy',
        );
        expect(game.menus.last.items, isNotEmpty, reason: script.id);
      }
    }
  });

  test('各客栈掌柜与游人分开署名，跨页保留正文且不继承其他场景的路人', () {
    final game = engine();
    for (final sample in [
      ('7:2', '建业客栈掌柜'),
      ('9:5', '客栈掌柜'),
      ('11:4', '小客栈掌柜'),
    ]) {
      final script = data.scripts[sample.$1]!;
      for (final command in script.commands.where(
        (c) => c.opcode == 13 && c.arg(0) == 0,
      )) {
        final op =
            GameOperation('dialogue', args: command.args, text: command.string)
              ..scriptId = script.id
              ..address = command.address
              ..next = command.string.length
              ..speakerName = '路人';
        final first = DialoguePresentation.from(game, op);
        expect(
          first.speaker,
          command.string.startsWith('游人:') ? '游人' : sample.$2,
        );
        op.start = command.string.length ~/ 2;
        final next = DialoguePresentation.from(game, op);
        expect(next.speaker, first.speaker);
        expect(next.text, command.string.substring(op.start));
      }
    }
  });
}

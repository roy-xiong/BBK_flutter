import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bbk_flutter/games/fmj/data/game_data.dart';
import 'package:bbk_flutter/games/fmj/engine/game_actor.dart';
import 'package:bbk_flutter/games/fmj/engine/game_engine.dart';
import 'package:bbk_flutter/games/fmj/ui/game_view_model.dart';
import 'package:bbk_flutter/games/fmj/ui/modern_game_view.dart';
import 'package:bbk_flutter/games/fmj/ui/system_font_layout.dart';
import 'game_engine_test.dart' show loadData;

/// 直接从真实穿戴菜单验证触屏、翻页、换装归属，不能只切标题不切操作目标。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GameData data;
  setUpAll(() async => data = await loadData());
  GameEngine game({int count = 3}) {
    final g = GameEngine(data, textLayout: FlutterSystemFontLayout())
      ..screen = 'play'
      ..intro = null;
    g.preferences['modernUi'] = true;
    for (var id = 1; id <= count; id++) {
      g.players.add(GameActor.load(data, 1, id)!);
    }
    g.equip(g.players[0], '7:1', fromBag: false);
    if (count >= 2) g.equip(g.players[1], '7:24', fromBag: false);
    if (count >= 3) g.equip(g.players[2], '7:15', fromBag: false);
    g.openEquipment(0);
    return g;
  }

  test('翻页遍历三个人物并保留手持槽，确认卸下作用于当前人物', () {
    final g = game();
    g.menus.last.selected = 4;
    final hero = g.players.first.equipment[4];
    g.press(GameKey.pageDown);
    expect(g.menus.last.actor, 1);
    expect(g.menus.last.selected, 4);
    g.press(GameKey.pageDown);
    expect(g.menus.last.actor, 2);
    expect(g.menus.last.selected, 4);
    g.press(GameKey.confirm);
    expect(g.menus.last.kind, 'equipment-action');
    g.selectMenu(g.menus.last, 1);
    expect(g.players[2].equipment[4], isNull);
    expect(g.inventory['7:15'], 1);
    expect(g.players.first.equipment[4], hero);
    g.press(GameKey.pageDown);
    expect(g.menus.last.actor, 0);
    g.press(GameKey.pageUp);
    expect(g.menus.last.actor, 2);
  });

  test('换装归属跟随切换人物，旧页面回调不能越过子菜单切人', () {
    final g = game()..addGoods('7:25');
    final old = g.menus.last;
    expect(g.selectEquipmentActor(old, 1), true);
    expect(g.selectEquipmentActor(old, 2), false);
    final menu = g.menus.last;
    expect(g.selectEquipmentActor(menu, -1), false);
    expect(g.selectEquipmentActor(menu, 3), false);
    g.selectMenu(menu, 4);
    expect(g.selectEquipmentActor(menu, 0), false);
    g.selectMenu(g.menus.last, 0);
    final selection = g.menus.last;
    expect(selection.equipmentOwner, same(g.players[1]));
    g.selectMenu(selection, selection.ids.indexOf('7:25'));
    expect(g.players[1].equipment[4], '7:25');
    expect(g.players.first.equipment[4], '7:1');
    expect(g.players.last.equipment[4], '7:15');
    expect(g.inventory['7:24'], 1);
    expect(g.inventory['7:25'] ?? 0, 0);
  });

  for (final width in [320.0, 390.0, 960.0]) {
    testWidgets('宽度$width穿戴页能点击切换全部队员且不修改物品', (tester) async {
      tester.view.physicalSize = Size(width, width * .6 + 56);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final g = game();
      g.menus.last.selected = 4;
      final before = jsonEncode(g.snapshot());
      final model = GameViewModel()
        ..engine = g
        ..loading = false;
      try {
        await tester.runAsync(model.prepareModernArt);
        await tester.pumpWidget(
          MaterialApp(
            home: AnimatedBuilder(
              animation: model,
              builder: (_, _) => ModernGameView(model: model),
            ),
          ),
        );
        await tester.pump();
        for (final id in [2, 3, 1]) {
          final button = find.byKey(ValueKey('equipment-actor-$id'));
          expect(button, findsOneWidget);
          expect(button.hitTestable(), findsOneWidget);
          await tester.tap(button);
          await tester.pump();
          expect(g.menus.last.actor, id - 1);
          expect(g.menus.last.selected, 4);
          expect(find.text('${g.players[id - 1].name} · 穿戴'), findsOneWidget);
          expect(
            find.text('手持  ${g.goodsName(g.players[id - 1].equipment[4]!)}'),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        }
        expect(jsonEncode(g.snapshot()), before);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        model.dispose();
      }
    });
  }

  testWidgets('战斗保留最下方状态栏金线', (tester) async {
    final g = game()..menus.clear();
    g.battle = GameBattle(
      g,
      monsters: [1],
      background: [2, 2, 2],
      randomFight: true,
    );
    final model = GameViewModel()
      ..engine = g
      ..loading = false;
    try {
      await tester.pumpWidget(MaterialApp(home: ModernGameView(model: model)));
      final band = tester.widget<DecoratedBox>(
        find.byKey(const ValueKey('world-information-band')),
      );
      final decoration = band.decoration as BoxDecoration;
      expect(
        (decoration.border as Border?)?.top.color,
        const Color(0xff997e4f),
      );
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      model.dispose();
    }
  });
}

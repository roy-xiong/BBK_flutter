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

/// 使用真实物品、角色及菜单入口验证 V4，预览不能改变背包、属性或剧情标记。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GameData data;
  setUpAll(() async => data = await loadData());

  GameEngine game() {
    final g = GameEngine(data, textLayout: FlutterSystemFontLayout())
      ..screen = 'play'
      ..intro = null;
    for (final id in [1, 2]) {
      final p = GameActor.load(data, 1, id)!;
      g.players.add(p);
      for (var slot = 0; slot < 8; slot++) {
        g.unequip(p, slot);
      }
    }
    g.inventory.clear();
    g.flags.clear();
    g.preferences['modernUi'] = true;
    return g;
  }

  test('全队不适用的装备仍可查看，队伍变化后也不隐藏', () {
    final g = game()
      ..addGoods('4:4')
      ..addGoods('7:7')
      ..addGoods('7:19')
      ..addGoods('6:18')
      ..addGoods('9:1');
    g.openInventory(mode: 'equip');
    expect(g.menus.last.ids, ['4:4', '7:7', '7:19', '6:18']);
    g.players.removeLast();
    g.refreshMenus();
    expect(g.menus.last.ids, ['4:4', '7:7', '7:19', '6:18']);
    expect(g.menus.last.selected, 0);
  });

  test('已有同名装备的人物不重复参与选人，背包余量不会消失', () {
    final g = game()..addGoods('6:2', 2);
    g.equip(g.players.first, '6:2');
    g.openInventory(mode: 'equip');
    g.press(GameKey.confirm);
    expect(g.menus.last.kind, 'actors');
    expect(g.menus.last.ids, ['2']);
    expect(g.inventory['6:2'], 1);
  });

  test('饰品自动及指定槽位的只读预览与实际换装一致', () {
    final g = game(), p = g.players.first;
    g.equip(p, '6:1', slot: 0, fromBag: false);
    g.inventory.clear();
    g.addGoods('6:2');
    final before = jsonEncode(g.snapshot());
    final automatic = g.equipmentComparisons('6:2', owner: p).single;
    expect(automatic.slot, 1);
    expect(
      automatic.changes,
      containsAll([('灵力', p.spirit, p.spirit + 4), ('吉运', p.luck, p.luck + 2)]),
    );
    final explicit = g.equipmentComparisons('6:2', owner: p, slot: 0).single;
    expect(explicit.slot, 0);
    expect(explicit.changes, contains(('吉运', p.luck, p.luck - 2)));
    expect(jsonEncode(g.snapshot()), before);
    expect(g.equip(p, '6:2', slot: 0), true);
    for (final change in explicit.changes) {
      expect({'灵力': p.spirit, '吉运': p.luck}[change.$1], change.$3);
    }
  });

  test('属性已封顶时不显示零变化，预览不写剧情标记', () {
    final g = game(), p = g.players.first;
    p
      ..attack = 999
      ..defense = 999
      ..speed = 99
      ..spirit = 99
      ..luck = 99
      ..maxHp = 999
      ..maxMp = 999;
    g.addGoods('2:18');
    final before = jsonEncode(g.snapshot());
    expect(g.equipmentComparisons('2:18', owner: p).single.changes, isEmpty);
    expect(jsonEncode(g.snapshot()), before);
  });

  test('另一件防具仍提供免疫时，不误报移除该特效', () {
    final g = game(), p = g.players.last;
    expect(g.equip(p, '1:15', slot: 7, fromBag: false), true);
    expect(g.equip(p, '2:16', slot: 5, fromBag: false), true);
    g.inventory.clear();
    g.addGoods('1:7');
    expect(
      g.equipmentComparisons('1:7', owner: p).single.removedEffects,
      isNot(contains('免疫中毒')),
    );
  });

  test('从人物穿戴页进入时，对比固定在该人物和指定部位', () {
    final g = game()..addGoods('7:24');
    g.openEquipment(1);
    g.selectMenu(g.menus.last, 4);
    g.selectMenu(g.menus.last, 0);
    final menu = g.menus.last;
    expect(menu.equipmentOwner, same(g.players.last));
    expect(menu.equipmentSlot, 4);
    expect(
      g
          .equipmentComparisons(
            '7:24',
            owner: menu.equipmentOwner,
            slot: menu.equipmentSlot,
          )
          .single
          .player,
      same(g.players.last),
    );
  });

  for (final width in [320.0, 390.0, 960.0]) {
    testWidgets('宽度$width的同页对比只展示适用人物及变化项，详情不重复名称图标', (tester) async {
      tester.view.reset();
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, width * .6 + 56);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final g = game();
      final p = g.players.last;
      g.equip(p, '4:1', fromBag: false);
      g.inventory.clear();
      g.addGoods('4:4');
      g.addGoods('7:19');
      g.openInventory(mode: 'equip');
      final before = jsonEncode(g.snapshot());
      final model = GameViewModel()
        ..engine = g
        ..loading = false;
      try {
        await tester.runAsync(() => model.prepareModernArt());
        await tester.pumpWidget(
          MaterialApp(
            home: AnimatedBuilder(
              animation: model,
              builder: (_, _) => ModernGameView(model: model),
            ),
          ),
        );
        await tester.pump();
        expect(find.text('软蛟披风'), findsOneWidget);
        expect(find.byKey(const ValueKey('equip-comparison-1')), findsNothing);
        expect(
          find.byKey(const ValueKey('equip-comparison-2')),
          findsOneWidget,
        );
        final change = tester.widget<Text>(
          find.byKey(const ValueKey('equip-change-2-防御')),
        );
        expect(
          change.textSpan?.toPlainText(),
          '防御 ${p.defense} → ${p.defense + 10}  +10',
        );
        expect(find.byKey(const ValueKey('equip-change-2-攻击')), findsNothing);
        final details = find.byKey(
          const ValueKey('equipment-comparison-details'),
        );
        expect(
          find.descendant(of: details, matching: find.byType(CustomPaint)),
          findsNothing,
        );
        expect(jsonEncode(g.snapshot()), before);
        expect(
          tester
              .getSize(find.byKey(const ValueKey('equipment-selection-frame')))
              .height,
          lessThanOrEqualTo(width * .6 * .78 + 1),
        );
        expect(tester.takeException(), isNull);
        model.action((engine) => engine.menus.last.selected = 1);
        await tester.pump();
        expect(find.text('弯月刀'), findsOneWidget);
        expect(find.text('当前队伍无人可装备'), findsOneWidget);
        expect(find.byKey(const ValueKey('equip-comparison-1')), findsNothing);
        expect(find.byKey(const ValueKey('equip-comparison-2')), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        model.dispose();
      }
    });
  }
}

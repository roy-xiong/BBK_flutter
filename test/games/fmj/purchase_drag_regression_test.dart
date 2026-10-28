import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bbk_flutter/games/fmj/data/game_data.dart';
import 'package:bbk_flutter/games/fmj/engine/game_engine.dart';
import 'package:bbk_flutter/games/fmj/ui/game_page.dart';
import 'package:bbk_flutter/games/fmj/ui/game_view_model.dart';
import 'package:bbk_flutter/games/fmj/ui/modern_game_view.dart';
import 'package:bbk_flutter/games/fmj/ui/system_font_layout.dart';
import 'game_engine_test.dart' show loadData;

/// 覆盖原购买确认交易及真实页面拖动事件；测试不接触用户存档。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GameData data;
  setUpAll(() async => data = await loadData());
  GameEngine engine() {
    final game = GameEngine(data, textLayout: FlutterSystemFontLayout())
      ..restore(
        GameData.decodeObject(
          File(
            'test/games/fmj/fixtures/navigation_start.json',
          ).readAsStringSync(),
        ),
      );
    game.preferences['modernUi'] = true;
    game.inventory.clear();
    game.money = 5000;
    return game;
  }

  void openPurchase(GameEngine game) {
    game.openInventory(mode: 'buy', items: ['9:1']);
    game.press(GameKey.confirm);
  }

  test('选中商品先选择数量，确认三件时才一次性扣钱入库', () {
    final game = engine();
    openPurchase(game);
    expect(game.money, 5000, reason: '打开数量框不能立即买一件');
    expect(game.inventory['9:1'] ?? 0, 0);
    expect(game.menus, hasLength(2));
    for (var i = 0; i < 3; i++) {
      game.press(GameKey.up);
    }
    expect(game.money, 5000, reason: '数量预览不能提前扣钱');
    expect(game.inventory['9:1'] ?? 0, 0);
    game.press(GameKey.confirm);
    expect(game.inventory['9:1'], 3);
    expect(game.money, 5000 - game.goods('9:1')!.word(18) * 3);
    expect(game.menus, hasLength(1));
  });

  test('选择数量后取消，金钱库存和商店选中商品保持不变', () {
    final game = engine();
    openPurchase(game);
    for (var i = 0; i < 4; i++) {
      game.press(GameKey.up);
    }
    game.press(GameKey.cancel);
    expect(game.money, 5000);
    expect(game.inventory['9:1'] ?? 0, 0);
    expect(game.menus, hasLength(1));
    expect(game.menus.last.ids, ['9:1']);
  });

  test('数量为零确认不成交，资金及携带空间限制可购买数量', () {
    final game = engine();
    openPurchase(game);
    game.press(GameKey.confirm);
    expect(game.money, 5000);
    expect(game.inventory['9:1'] ?? 0, 0);
    game.menus.clear();
    game.inventory['9:1'] = 998;
    game.money = game.goods('9:1')!.word(18) * 2;
    openPurchase(game);
    for (var i = 0; i < 5; i++) {
      game.press(GameKey.up);
    }
    game.press(GameKey.confirm);
    expect(game.inventory['9:1'], 999);
    expect(game.money, game.goods('9:1')!.word(18));
  });

  testWidgets('同一帧多次拖动工具栏不丢位移，后续逐帧移动也贴住指针', (tester) async {
    final game = engine();
    final model = GameViewModel()
      ..engine = game
      ..loading = false;
    tester.view.physicalSize = const Size(1000, 700);
    tester.view.devicePixelRatio = 1;
    await tester.runAsync(() => model.prepareModernArt());
    try {
      await tester.pumpWidget(MaterialApp(home: GamePage(viewModel: model)));
      final bar = find
          .ancestor(
            of: find.byTooltip('控制设置'),
            matching: find.byWidgetPredicate(
              (w) => w is GestureDetector && w.onPanUpdate != null,
            ),
          )
          .first;
      final gesture = await tester.startGesture(
        tester.getCenter(find.byTooltip('控制设置')),
      );
      await gesture.moveBy(const Offset(30, 30));
      await tester.pump();
      final before = tester.getTopLeft(bar);
      await gesture.moveBy(const Offset(20, 12));
      await gesture.moveBy(const Offset(20, 12));
      await gesture.moveBy(const Offset(20, 12));
      await tester.pump();
      expect(tester.getTopLeft(bar).dx - before.dx, closeTo(60, .1));
      expect(tester.getTopLeft(bar).dy - before.dy, closeTo(36, .1));
      final second = tester.getTopLeft(bar);
      for (var i = 0; i < 4; i++) {
        await gesture.moveBy(const Offset(13, 7));
        await tester.pump();
      }
      expect(tester.getTopLeft(bar).dx - second.dx, closeTo(52, .1));
      expect(tester.getTopLeft(bar).dy - second.dy, closeTo(28, .1));
      await gesture.up();
      await tester.pump();
      expect(find.byType(BottomSheet), findsNothing, reason: '拖动不能误点控制设置');
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      model.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    }
  });

  testWidgets('彩色数量框在窄屏可增减数量、取消及确认购买', (tester) async {
    final game = engine();
    final vm = GameViewModel()
      ..engine = game
      ..loading = false;
    tester.view.physicalSize = const Size(360, 250);
    tester.view.devicePixelRatio = 1;
    await tester.runAsync(() => vm.prepareModernArt());
    try {
      game.openInventory(mode: 'buy', items: ['9:1']);
      await tester.pumpWidget(
        MaterialApp(
          home: AnimatedBuilder(
            animation: vm,
            builder: (_, _) => ModernGameView(model: vm),
          ),
        ),
      );
      await tester.tap(find.widgetWithText(ListTile, game.goodsName('9:1')));
      await tester.pump();
      expect(find.text('购买数量'), findsOneWidget);
      expect(game.money, 5000);
      await tester.tap(find.byTooltip('增加购买数量'));
      await tester.pump();
      await tester.tap(find.byTooltip('增加购买数量'));
      await tester.pump();
      expect(
        find.text('总价：${game.goods('9:1')!.word(18) * 2}'),
        findsOneWidget,
      );
      await tester.tap(find.text('取消'));
      await tester.pump();
      expect(game.inventory['9:1'] ?? 0, 0);
      expect(game.money, 5000);
      await tester.tap(find.widgetWithText(ListTile, game.goodsName('9:1')));
      await tester.pump();
      await tester.tap(find.byTooltip('增加购买数量'));
      await tester.pump();
      await tester.tap(find.text('确认购买'));
      await tester.pump();
      expect(game.inventory['9:1'], 1);
      expect(game.money, 5000 - game.goods('9:1')!.word(18));
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      vm.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    }
  });
}

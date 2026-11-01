import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bbk_flutter/games/fmj/data/game_data.dart';
import 'package:bbk_flutter/games/fmj/engine/game_actor.dart';
import 'package:bbk_flutter/games/fmj/engine/game_engine.dart';
import 'package:bbk_flutter/games/fmj/ui/game_cheat_panel.dart';
import 'package:bbk_flutter/games/fmj/ui/game_view_model.dart';
import 'package:bbk_flutter/games/fmj/ui/modern_game_view.dart';
import 'package:bbk_flutter/games/fmj/ui/system_font_layout.dart';
import 'game_engine_test.dart' show loadData;

/// 普通数值与数量没有游戏封顶；所有预览、换装、交易和序列化必须守恒。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GameData data;
  setUpAll(() async => data = await loadData());
  GameEngine game() {
    final g = GameEngine(data, textLayout: FlutterSystemFontLayout())
      ..screen = 'play'
      ..intro = null;
    final p = GameActor.load(data, 1, 1)!;
    g.players.add(p);
    for (var slot = 0; slot < 8; slot++) {
      g.unequip(p, slot);
    }
    g.inventory.clear();
    g.preferences['modernUi'] = true;
    return g;
  }

  test('900攻击装备钨龙剑得到1008，卸下仍为900', () {
    final g = game(), p = g.players.first;
    p.attack = 900;
    g.addGoods('7:9');
    final preview = g.equipmentComparisons('7:9', owner: p).single;
    expect(preview.changes, contains(('攻击', 900, 1008)));
    expect(g.equip(p, '7:9'), true);
    expect(p.attack, 1008);
    g.unequip(p, 4);
    expect(p.attack, 900);
  });

  test('灵力身法吉运可突破99，成长与仙药可突破999', () {
    final g = game(), p = g.players.first;
    p
      ..spirit = 98
      ..luck = 98
      ..maxHp = 995
      ..hp = 995
      ..maxMp = 995;
    g.addGoods('6:2');
    g.equip(p, '6:2');
    expect(p.spirit, 102);
    expect(p.luck, 100);
    p.levelUp(data, 2);
    expect(p.maxHp, 1005);
    expect(p.maxMp, 1005);
    p.attack = 999;
    g.addGoods('11:3');
    g.consumeMedicine(p, '11:3');
    expect(p.attack, 1001);
  });

  test('高属性与经验序列化往返不截断，合法当前气血真气保持完整', () {
    final raw = GameActor.load(data, 1, 1)!.toJson()
      ..addAll({
        'maxHp': 3000000,
        'hp': 2000000,
        'maxMp': 2500000,
        'mp': 1500000,
        'attack': 1234567,
        'defense': 2345678,
        'speed': 12345,
        'spirit': 12346,
        'luck': 12347,
        'exp': 4000000,
      });
    final a = GameActor.fromJson(
      jsonDecode(jsonEncode(raw)) as Map<String, dynamic>,
    );
    for (final key in [
      'maxHp',
      'hp',
      'maxMp',
      'mp',
      'attack',
      'defense',
      'speed',
      'spirit',
      'luck',
      'exp',
    ]) {
      expect(a.toJson()[key], raw[key], reason: key);
    }
  });

  test('背包999件外另穿一件，换装退回后成为1000件且不丢失', () {
    final g = game(), p = g.players.first;
    g.equip(p, '7:1', fromBag: false);
    g.addGoods('7:1', 999);
    g.addGoods('7:2');
    g.equip(p, '7:2');
    expect(g.inventory['7:1'], 1000);
  });

  test('已持有999件仍可购买，购买上限只受金钱限制', () {
    final g = game()..addGoods('9:1', 999);
    final price = g.goods('9:1')!.word(18);
    g.money = price * 2000;
    g.openInventory(mode: 'buy', items: ['9:1']);
    g.press(GameKey.confirm);
    expect(g.menus.last.kind, 'buy-quantity');
    expect(g.menus.last.purchase!.limit, 2000);
    g.changePurchaseQuantity(g.menus.last, 1500);
    g.press(GameKey.confirm);
    expect(g.inventory['9:1'], 2499);
    expect(g.money, price * 500);
  });

  test('零售价商品数量无上限，出售超过999件也保持钱物守恒', () {
    final g = game();
    g.openInventory(mode: 'buy', items: ['1:6']);
    g.press(GameKey.confirm);
    expect(g.menus.last.purchase!.limit, isNull);
    g.changePurchaseQuantity(g.menus.last, 10001);
    g.press(GameKey.confirm);
    expect(g.inventory['1:6'], 10001);
    g.menus.clear();
    g.addGoods('9:1', 2000);
    g.openInventory(mode: 'sell', items: ['9:1']);
    g.press(GameKey.confirm);
    expect(g.menus.last.purchase!.limit, 2000);
    g.changePurchaseQuantity(g.menus.last, 1500);
    g.press(GameKey.confirm);
    expect(g.inventory['9:1'], 500);
    expect(g.money, 1500 * g.goods('9:1')!.word(20));
  });

  test('四种复活药恢复对应比例气血，不错误恢复真气', () {
    for (final sample in [(1, 30), (2, 60), (3, 100), (4, 200)]) {
      final g = game(), p = g.players.first;
      p
        ..maxHp = 200
        ..hp = 0
        ..maxMp = 100
        ..mp = 10;
      final id = '10:${sample.$1}';
      g.addGoods(id);
      expect(g.consumeMedicine(p, id), true);
      expect(p.hp, sample.$2);
      expect(p.mp, 10);
      expect(g.inventory[id] ?? 0, 0);
    }
  });

  test('战斗致死保留负气血时，复活药仍能按最大气血比例复活', () {
    final g = game(), p = g.players.first;
    p
      ..maxHp = 200
      ..hp = -500
      ..maxMp = 100
      ..mp = 10;
    g.addGoods('10:1');
    g.consumeMedicine(p, '10:1');
    expect(p.hp, 30);
    expect(p.mp, 10);
    expect(p.alive, true);
  });

  test('经典背包的超长数量完整记录，不截成下一页', () {
    final g = game();
    g.setPreference('modernUi', false);
    g.setPreference('wideView', true);
    g.addGoods('9:1', 1234567890123456789);
    g.openInventory();
    g.render();
    expect(
      g.surface.textRuns.map((run) => run.text),
      contains('数量:1234567890123456789'),
    );
  });

  testWidgets('高数值人物状态页显示全部七行及末尾状态', (tester) async {
    final g = game(), p = g.players.first;
    p
      ..maxHp = 12345678
      ..hp = 1234567
      ..maxMp = 23456789
      ..mp = 2345678
      ..attack = 34567890
      ..defense = 45678901
      ..speed = 56789012
      ..spirit = 67890123
      ..luck = 78901234
      ..exp = 89012345;
    g.openState();
    final vm = GameViewModel()
      ..engine = g
      ..loading = false;
    await tester.runAsync(vm.prepareModernArt);
    try {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 290);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(home: ModernGameView(model: vm)));
      final summary = find.byWidgetPredicate(
        (w) =>
            w is Text &&
            w.data?.contains('生命') == true &&
            w.data?.contains('状态') == true,
      );
      expect(summary, findsOneWidget);
      final text = tester.widget<Text>(summary);
      expect(text.data, contains('幸运 78901234'));
      expect(text.data, contains('状态 正常'));
      expect(
        tester.renderObject<RenderParagraph>(summary).didExceedMaxLines,
        false,
      );
      final frame = tester
          .getRect(find.byKey(const ValueKey('fmj-native-menu')))
          .inflate(.5);
      final textRect = tester.getRect(summary);
      expect(
        frame.contains(textRect.topLeft) &&
            frame.contains(textRect.bottomRight),
        true,
      );
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      vm.dispose();
    }
  });

  testWidgets('作弊只把低于999的七项属性提至999，不降低正常高属性', (tester) async {
    final g = game(), p = g.players.first;
    p.attack = 1500;
    final vm = GameViewModel()
      ..engine = g
      ..loading = false;
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: GameCheatPanel(model: vm)),
        ),
      );
      await tester.ensureVisible(find.text('全队属性拉满'));
      await tester.tap(find.text('全队属性拉满'));
      expect(p.attack, 1500);
      expect(p.maxHp, 999);
      expect(p.maxMp, 999);
      expect(p.hp, p.maxHp);
      expect(p.mp, p.maxMp);
      expect(p.speed, 999);
      expect(p.spirit, 999);
      expect(p.luck, 999);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      vm.dispose();
    }
  });

  testWidgets('超长气血真气与数量完整显示，状态栏各列不溢出或跳位', (tester) async {
    final g = game(), p = g.players.first;
    p
      ..maxHp = 12345678
      ..hp = 1234567
      ..maxMp = 23456789
      ..mp = 2345678
      ..exp = 345678901234;
    final vm = GameViewModel()
      ..engine = g
      ..loading = false;
    await tester.runAsync(vm.prepareModernArt);
    try {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 290);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(home: ModernGameView(model: vm)));
      final hpRect = tester.getRect(
        find.byKey(const ValueKey('world-row-0-hp')),
      );
      expect(find.text('12345678'), findsOneWidget);
      expect(find.text('23456789'), findsOneWidget);
      expect(find.text('345678901234'), findsOneWidget);
      for (final value in ['12345678', '23456789', '345678901234']) {
        expect(
          tester
              .renderObject<RenderParagraph>(find.text(value))
              .didExceedMaxLines,
          false,
        );
      }
      expect(tester.takeException(), isNull);
      p.hp = 999;
      await tester.pumpWidget(MaterialApp(home: ModernGameView(model: vm)));
      expect(
        tester.getRect(find.byKey(const ValueKey('world-row-0-hp'))),
        hpRect,
      );
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      vm.dispose();
    }
  });
}

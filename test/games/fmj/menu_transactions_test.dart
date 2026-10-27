import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:bbk_flutter/games/fmj/data/game_data.dart';
import 'package:bbk_flutter/games/fmj/engine/game_actor.dart';
import 'package:bbk_flutter/games/fmj/engine/game_engine.dart';
import 'package:bbk_flutter/games/fmj/ui/system_font_layout.dart';
import 'game_engine_test.dart' show loadData;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GameData data;
  setUpAll(() async => data = await loadData());
  GameEngine engine() {
    final game = GameEngine(
      data,
      textLayout: FlutterSystemFontLayout(),
      random: math.Random(24),
    );
    game.screen = 'play';
    game.intro = null;
    game.preferences['modernUi'] = true;
    for (final id in [1, 2, 3]) {
      final actor = GameActor.load(data, 1, id)!;
      game.players.add(actor);
      for (var slot = 0; slot < 8; slot++) {
        game.unequip(actor, slot);
      }
    }
    game.inventory.clear();
    game.flags.clear();
    return game;
  }

  void choose(GameEngine game, int index) {
    expect(game.menus, isNotEmpty);
    game.menus.last.selected = index;
    game.press(GameKey.confirm);
  }

  void chooseOwnerIfShown(GameEngine game, [int index = 0]) {
    if (game.menus.lastOrNull?.kind == 'actors') choose(game, index);
  }

  test('最后一件装备穿上后移出装备列表，换下的旧装备返回列表', () {
    final game = engine();
    // 采用真实武器，经过与键盘相同的物品、人物菜单确认链。
    game.equip(game.players.first, '7:1', slot: 4, fromBag: false);
    game.inventory.clear();
    game.addGoods('7:2');
    game.openInventory(mode: 'equip');
    choose(game, 0);
    chooseOwnerIfShown(game);
    final menu = game.menus.last;
    expect(game.inventory['7:2'] ?? 0, 0);
    expect(menu.ids, isNot(contains('7:2')));
    expect(menu.ids, contains('7:1'));
  });

  test('多份装备只移走一份，列表仍保留剩余库存', () {
    final game = engine();
    game.addGoods('1:1', 2);
    game.openInventory(mode: 'equip');
    choose(game, 0);
    chooseOwnerIfShown(game);
    expect(game.inventory['1:1'], 1);
    expect(game.menus.last.ids, contains('1:1'));
  });

  test('装备人物按原始角色位标记筛选，女装不向柳清风提供', () {
    final game = engine();
    game.addGoods('2:13');
    game.openInventory(mode: 'equip');
    choose(game, 0);
    expect(game.menus.last.kind, 'actors');
    expect(
      game.menus.last.items,
      game.players.skip(1).map((p) => p.name).toList(),
    );
  });

  test('指定更换第一饰品槽，不得被自动放入第二饰品槽', () {
    final game = engine(), p = game.players.first;
    game.equip(p, '6:1', slot: 0, fromBag: false);
    game.inventory.clear();
    game.addGoods('6:2');
    expect(game.equip(p, '6:2', slot: 0), isTrue);
    expect(p.equipment[0], '6:2');
    expect(p.equipment[1], isNull);
    expect(game.inventory['6:1'], 1);
  });

  test('同一人物不能重复穿戴同名饰品刷属性', () {
    final game = engine(), p = game.players.first;
    game.addGoods('6:1', 2);
    expect(game.equip(p, '6:1'), isTrue);
    final defense = p.defense;
    expect(game.equip(p, '6:1'), isFalse);
    expect(p.defense, defense);
    expect(game.inventory['6:1'], 1);
  });

  test('吃完最后一份药后物品列表移除，旧索引不会再次消耗', () {
    final game = engine();
    game.players.first
      ..maxHp = 100
      ..hp = 10;
    game.addGoods('9:1');
    game.openInventory();
    choose(game, 0);
    chooseOwnerIfShown(game);
    expect(game.players.first.hp, 60);
    expect(game.inventory['9:1'] ?? 0, 0);
    expect(game.menus.last.ids, isNot(contains('9:1')));
    game.press(GameKey.confirm);
    expect(game.players.first.hp, 60);
  });

  test('场外全体药作用于全队，只消耗一份', () {
    final game = engine();
    for (final p in game.players) {
      p
        ..maxHp = 1000
        ..hp = 100;
    }
    game.addGoods('9:7');
    game.openInventory();
    choose(game, 0);
    chooseOwnerIfShown(game);
    expect(game.players.map((p) => p.hp).toList(), [400, 400, 400]);
    expect(game.inventory['9:7'] ?? 0, 0);
  });

  test('战斗全体药不得按目标人数重复扣除库存', () {
    final game = engine();
    game.addGoods('9:7', 5);
    final battle = GameBattle(
      game,
      monsters: [10],
      background: [2, 2, 2],
      randomFight: true,
    );
    game.battle = battle;
    for (final p in game.players) {
      p
        ..maxHp = 1000
        ..hp = 100;
    }
    battle.phase = 'perform';
    battle.queue.add(
      BattleAction(game.players.first, game.players, 'item', resource: '9:7'),
    );
    game.update();
    expect(game.inventory['9:7'], 4);
    expect(game.players.map((p) => p.hp).toList(), [400, 400, 400]);
  });

  test('非药品不能经过用药接口扣掉任务物品', () {
    final game = engine();
    game.addGoods('14:5');
    game.consumeMedicine(game.players.first, '14:5');
    expect(game.inventory['14:5'], 1);
  });

  test('商店按脚本的编号和类型解析，空背包也必须显示商品', () {
    final game = engine();
    final script = data.scripts['3:2']!;
    game.cursor = ScriptCursor(script)
      ..pointer = script.commands.indexWhere((c) => c.opcode == 28);
    game.update();
    expect(game.menus.last.mode, 'buy');
    expect(game.menus.last.ids.take(3).toList(), ['7:1', '7:2', '7:15']);
  });

  test('所有原始商品清单含不点点隐藏商店均能打开非空货架', () {
    for (final script in data.scripts.values) {
      for (var index = 0; index < script.commands.length; index++) {
        final command = script.commands[index];
        if (command.opcode != 28) continue;
        final game = engine();
        game.cursor = ScriptCursor(script)..pointer = index;
        game.update();
        expect(game.error, isEmpty);
        expect(
          game.menus.lastOrNull?.ids,
          isNotEmpty,
          reason: '${script.id}@${command.address}',
        );
      }
    }
  });

  test('满库存购买不扣钱，出售最后一件后刷新列表', () {
    final game = engine();
    game.addGoods('9:1', 999);
    game.money = 5000;
    game.openInventory(mode: 'buy', items: ['9:1']);
    choose(game, 0);
    expect(game.money, 5000);
    expect(game.inventory['9:1'], 999);
    game.menus.clear();
    game.inventory.clear();
    game.addGoods('9:1');
    game.openInventory(mode: 'sell');
    choose(game, 0);
    expect(game.inventory['9:1'] ?? 0, 0);
    expect(game.menus.last.ids, isEmpty);
  });

  test('任务卡片不能出售，空存档和剧情副本不产生坏存档', () {
    final game = engine();
    game.addGoods('14:5');
    game.openInventory(mode: 'sell');
    choose(game, 0);
    expect(game.inventory['14:5'], 1);
    game.menus.clear();
    game.openSaveMenu(load: true);
    choose(game, 0);
    expect(game.saves[0], isNull);
    game.menus.clear();
    game.map = data.maps['1:31'];
    game.cursor = ScriptCursor(data.scripts['2:52']!)
      ..running = false
      ..previous = ScriptCursor(data.scripts['2:2']!);
    game.openSaveMenu();
    expect(game.menus, isEmpty);
    expect(game.canSave, isFalse);
  });
}

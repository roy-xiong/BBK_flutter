import 'dart:math' as math;
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bbk_flutter/games/fmj/data/game_data.dart';
import 'package:bbk_flutter/games/fmj/data/save_repository.dart';
import 'package:bbk_flutter/games/fmj/engine/game_actor.dart';
import 'package:bbk_flutter/games/fmj/engine/game_engine.dart';
import 'package:bbk_flutter/games/fmj/ui/game_cheat_panel.dart';
import 'package:bbk_flutter/games/fmj/ui/game_controls.dart';
import 'package:bbk_flutter/games/fmj/ui/game_view_model.dart';
import 'package:bbk_flutter/games/fmj/ui/system_font_layout.dart';
import 'package:bbk_flutter/games/fmj/ui/weapon_cheat_dialog.dart';
import 'game_engine_test.dart' show loadData;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GameData data;
  setUpAll(() async => data = await loadData());
  GameEngine game() =>
      GameEngine(
          data,
          textLayout: FlutterSystemFontLayout(),
          random: math.Random(24),
        )
        ..screen = 'play'
        ..intro = null
        ..players.add(GameActor.load(data, 1, 1)!);
  GameBattle battle(GameEngine g) => g.battle = GameBattle(
    g,
    monsters: [1, 2, 3],
    background: [2, 2, 2],
    randomFight: true,
  );

  test('敌人封乱毒开关默认关闭且只接受布尔值', () {
    final g = game();
    expect(g.preferences['enemyDebuffs'], false);
    g.setPreference('enemyDebuffs', true);
    expect(g.preferences['enemyDebuffs'], true);
    g.setPreference('enemyDebuffs', 'true');
    expect(g.preferences['enemyDebuffs'], true);
  });

  test('开启后敌人攻击自己并结算毒伤，我方不受影响', () {
    final g = game();
    final b = battle(g), enemy = b.monsters.first;
    enemy
      ..hp = 800
      ..maxHp = 1000
      ..attack = 80
      ..defense = 0
      ..immunity = 15;
    g.setPreference('enemyDebuffs', true);
    final heroHp = g.player!.hp;
    b
      ..phase = 'perform'
      ..current = BattleAction(enemy, [g.player!], 'attack');
    b.update();
    expect(b.current!.kind, 'self');
    expect(b.current!.targets, [enemy]);
    final afterSelfHit = enemy.hp;
    for (var i = 0; b.current != null && i < 1000; i++) {
      b.update();
    }
    expect(enemy.hp, (afterSelfHit * .75).truncate());
    expect(g.player!.hp, heroHp);
    expect(g.player!.status, 0);
  });

  test('关闭作弊保留正常状态和持续回合，不污染存档人物', () {
    final g = game(), b = battle(g), enemy = b.monsters.first;
    enemy
      ..status = 10
      ..permanentStatus = 2;
    enemy.statusRounds[8] = 5;
    final before = enemy.toJson();
    g.setPreference('enemyDebuffs', true);
    expect(b.statusFor(enemy), 14);
    expect(enemy.toJson(), before);
    expect(b.statusFor(g.player!), 0);
    g.setPreference('enemyDebuffs', false);
    expect(b.statusFor(enemy), 10);
    expect(enemy.statusRounds[8], 5);
    expect(enemy.permanentStatus, 2);
    final next = battle(g);
    expect(next.statusFor(next.monsters.first), 0);
    g.setPreference('enemyDebuffs', true);
    expect(
      next.monsters.where((m) => m.alive).map(next.statusFor),
      everyElement(14),
    );
    next.monsters.first.hp = 0;
    expect(next.statusFor(next.monsters.first), 0);
  });

  test('隐藏剧情占位和阵亡敌人不受作弊状态影响', () {
    final g = game()..setPreference('enemyDebuffs', true);
    final b = g.battle = GameBattle(
      g,
      monsters: [10],
      background: [2, 2, 2],
      randomFight: false,
    );
    expect(b.monsters, hasLength(2));
    expect(b.statusFor(b.monsters.first), 0);
    expect(b.statusFor(b.presentationEnemies.single), 14);
    b.presentationEnemies.single.hp = 0;
    expect(b.statusFor(b.presentationEnemies.single), 0);
  });

  test('敌人作弊开关经实际设置写盘并重开后保留', () async {
    final directory = await Directory.systemTemp.createTemp('fmj-enemy-cheat-');
    final repository = SaveRepository(directory: directory);
    final model = GameViewModel(repository: repository)
      ..engine = game()
      ..loading = false;
    GameViewModel? reopened;
    try {
      model.engine!.setPreference('enemyDebuffs', true);
      await model.persist(rethrowOnFailure: true);
      reopened = GameViewModel(repository: repository);
      await reopened.initialize();
      expect(reopened.engine!.preferences['enemyDebuffs'], true);
      final b = battle(reopened.engine!);
      expect(b.monsters.map(b.statusFor), everyElement(14));
    } finally {
      reopened?.dispose();
      model.dispose();
      await repository.flush();
      await directory.delete(recursive: true);
    }
  });

  test('全部33把武器排序采用真实攻击加成，发放可超过999且拒绝非武器', () {
    final g = game(), ids = g.cheatWeaponIds;
    expect(ids, hasLength(33));
    expect(ids.take(6), ['7:33', '7:13', '7:14', '7:31', '7:22', '7:23']);
    for (var i = 1; i < ids.length; i++) {
      expect(
        g.goods(ids[i - 1])!.byte(25),
        greaterThanOrEqualTo(g.goods(ids[i])!.byte(25)),
      );
    }
    for (final id in ids) {
      expect(g.grantCheatWeapon(id), true);
      expect(g.inventory[id], 999);
    }
    g.grantCheatWeapon('7:14');
    expect(g.inventory['7:14'], 1998);
    expect(g.grantCheatWeapon('9:1'), false);
    expect(g.grantCheatWeapon('7:999'), false);
    expect(g.inventory, hasLength(33));
  });

  testWidgets('手机横屏键盘弹起搜索不溢出', (tester) async {
    tester.view.physicalSize = const Size(640, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<String>(
                context: context,
                builder: (_) => WeaponCheatDialog(game: game()),
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 200);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '九龙');
    await tester.pumpAndSettle();
    expect(find.text('九龙道剑'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('武器弹窗按攻击降序、搜索选择得999把，取消不发放', (tester) async {
    final g = game();
    g.addGoods('7:9', 12);
    final model = GameViewModel()
      ..engine = g
      ..loading = false;
    addTearDown(model.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: GameCheatPanel(model: model)),
      ),
    );
    final open = find.text('获取999把武器');
    await tester.scrollUntilVisible(open, 200);
    await tester.tap(open);
    await tester.pumpAndSettle();
    expect(find.text('嗜血剑'), findsOneWidget);
    expect(find.text('九龙道剑'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('嗜血剑')).dy,
      lessThan(tester.getTopLeft(find.text('九龙道剑')).dy),
    );
    await tester.enterText(find.byType(TextField), '钨龙');
    await tester.pumpAndSettle();
    expect(find.text('嗜血剑'), findsNothing);
    await tester.tap(find.text('钨龙剑'));
    // 退场前再次点击同一行也不能再次发放或关闭下面的作弊页。
    await tester.tap(find.text('钨龙剑'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(g.inventory['7:9'], 1011);
    await tester.tap(open);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '根本不存在的武器');
    await tester.pumpAndSettle();
    expect(find.text('没有匹配的武器'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(g.inventory, {'7:9': 1011});
  });

  for (final portrait in [true, false]) {
    testWidgets('${portrait ? '竖' : '横'}屏删除技能合击快捷键，保留投掷和直达', (tester) async {
      final inputs = <GameControl>[];
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: portrait ? 390 : 800,
            height: portrait ? 500 : 400,
            child: portrait
                ? PortraitGameControlsPanel(
                    onInput: inputs.add,
                    hapticsEnabled: false,
                    showBattleButtons: true,
                    battleButtonsEnabled: true,
                  )
                : GameControlsOverlay(
                    onInput: inputs.add,
                    hapticsEnabled: false,
                    showBattleButtons: true,
                    battleButtonsEnabled: true,
                  ),
          ),
        ),
      );
      expect(find.byKey(const ValueKey('fmj-battle-magic')), findsNothing);
      expect(find.byKey(const ValueKey('fmj-battle-coop')), findsNothing);
      expect(
        find.byKey(const ValueKey('fmj-quick-travel-large')),
        findsOneWidget,
      );
      final toss = find.byKey(const ValueKey('fmj-battle-throw'));
      await tester.tap(toss);
      expect(inputs, [GameControl.quickThrow]);
    });
  }
}

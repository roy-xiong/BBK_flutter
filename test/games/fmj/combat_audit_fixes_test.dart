import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:bbk_flutter/games/fmj/ui/modern_art.dart';
import 'package:bbk_flutter/games/fmj/ui/modern_scene.dart';
import 'package:bbk_flutter/games/fmj/ui/modern_battle_layout.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bbk_flutter/games/fmj/data/game_data.dart';
import 'package:bbk_flutter/games/fmj/engine/game_actor.dart';
import 'package:bbk_flutter/games/fmj/engine/game_engine.dart';
import 'package:bbk_flutter/games/fmj/engine/pixel_surface.dart';
import 'game_engine_test.dart' show loadData;

final class _TextLayout implements SystemTextLayout {
  const _TextLayout();
  @override
  TextPage fit(String text, int start, int width, int height) =>
      TextPage(text.substring(start), text.length);
}

final class _ZeroRandom implements Random {
  const _ZeroRandom();
  @override
  bool nextBool() => false;
  @override
  int nextInt(int max) => 0;
  @override
  double nextDouble() => 0;
}

/// 使用真实ROM和生产动作入口，锁住战斗审计F02至F10的可见行为。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GameData data;
  setUpAll(() async => data = await loadData());

  GameEngine game(int count) {
    final g =
        GameEngine(
            data,
            textLayout: const _TextLayout(),
            random: const _ZeroRandom(),
          )
          ..screen = 'play'
          ..intro = null;
    for (var id = 1; id <= count; id++) {
      final p = GameActor.load(data, 1, id)!;
      p.equipment.fillRange(0, 8, null);
      p.maxHp = p.hp = 200;
      p.maxMp = p.mp = 999;
      p.attack = 10;
      p.attackStatus = 0;
      p.speed = 99;
      g.players.add(p);
    }
    return g;
  }

  GameBattle battle(GameEngine g) {
    final b = GameBattle(
      g,
      monsters: [1],
      background: [2, 2, 2],
      randomFight: true,
    );
    g.battle = b;
    b.monsters.single
      ..maxHp = 999
      ..hp = 999
      ..defense = 0
      ..status = 0
      ..spirit = 0
      ..speed = 0;
    return b;
  }

  BattleAction begin(
    GameBattle b,
    GameActor p,
    String kind, {
    String? resource,
  }) {
    final a = BattleAction(p, [b.monsters.single], kind, resource: resource);
    b
      ..phase = 'perform'
      ..current = a;
    b.update();
    return a;
  }

  void finish(GameBattle b) {
    for (var tick = 0; b.current != null && tick < 3000; tick++) {
      b.update();
    }
    expect(b.current, isNull);
  }

  test('F02 word使用补码，byte保留符号绝对值格式', () {
    expect(data.record(4, 1, 11)!.signedWord(18), -300);
    expect(data.record(6, 8, 29)!.signedWord(22), -180);
    expect(data.record(6, 8, 30)!.signedWord(24), -250);
    final iron = data.offsets.entries
        .where((e) => e.key.startsWith('6:'))
        .map((e) => GameRecord(data, e.value))
        .singleWhere((r) => r.text(6) == '玄铁剑');
    expect(iron.signedByte(27), -10);
    final samples = Uint8List.fromList([
      0,
      0,
      0xff,
      0x7f,
      0,
      0x80,
      0xff,
      0xff,
      0x8a,
    ]);
    final bytes = Uint8List(0x2003)..setAll(0, samples);
    bytes[16] = 255;
    final record = GameRecord(
      GameData(
        bytes: bytes,
        encoding: GameEncoding({}),
        guide: {'maps': [], 'scripts': []},
        stages: [],
      ),
      0,
    );

    expect(
      [
        for (final at in [0, 2, 4, 6]) record.signedWord(at),
      ],
      [0, 32767, -32768, -1],
    );
    expect(record.signedByte(8), -10);
  });

  for (final initiator in [1, 2]) {
    test('F05 第${initiator + 1}人发起合击使用自己的平安符', () {
      final g = game(3), b = battle(g);
      g.players[initiator].equipment[0] = '6:1';
      final a = begin(b, g.players[initiator], 'coop');
      expect(a.movie?.id, '2:${data.record(4, 1, 26)!.byte(5)}');
    });
  }

  test('F03 天心灯单选合击伤敌并向每个实际参与者吸血', () {
    final g = game(2), b = battle(g);
    g.players.first.equipment[0] = '6:14';
    for (final p in g.players) {
      p.hp = 100;
    }
    b.monsters.single.maxHp = b.monsters.single.hp = 3000;
    final a = begin(b, g.players.first, 'coop');
    expect(b.monsters.single.hp, lessThan(3000));
    expect(g.players.map((p) => p.hp), everyElement(greaterThan(100)));
    expect(a.changes[b.monsters.single], lessThan(0));
    expect(g.players.map((p) => p.mp), everyElement(greaterThanOrEqualTo(0)));
  });

  for (final count in [2, 3]) {
    test('F03 $count人天心灯首击击杀后仍为全部参与者扣费吸血', () {
      final g = game(count), b = battle(g);
      g.players.first.equipment[0] = '6:14';
      for (final p in g.players) {
        p.hp = 100;
      }
      b.monsters.single
        ..level = 2
        ..hp = 200;
      final a = begin(b, g.players.first, 'coop');
      expect(b.monsters.single.hp, 200 - count * 300);
      expect(g.players.map((p) => p.hp), everyElement(200));
      expect(g.players.map((p) => p.mp), everyElement(998));
      expect(a.changes[b.monsters.single], -count * 300);
    });

    test('F04 $count人物理合击首击击杀后仍完成全员攻击', () {
      final g = game(count), b = battle(g);
      b.monsters.single.hp = 1;
      begin(b, g.players.first, 'coop');
      expect(b.monsters.single.hp, 1 - count * 16);
    });
  }

  test('合击开始前排除前序动作已杀死的目标和隐藏占位', () {
    final g = game(2);
    final b = GameBattle(
      g,
      monsters: [1],
      background: [2, 2, 2],
      randomFight: false,
    );
    g.battle = b;
    final ghost = b.monsters.first;
    final target = b.monsters.last
      ..defense = 0
      ..hp = 1000
      ..maxHp = 1000;
    final dead = GameActor.load(data, 3, 2)!..hp = -5;
    b.monsters.add(dead);
    final a = BattleAction(g.players.first, [ghost, dead, target], 'coop');
    b
      ..phase = 'perform'
      ..current = a;
    b.update();
    expect(ghost.hp, -1);
    expect(dead.hp, -5);
    expect(target.hp, 968);
    expect(a.targets, [target]);
  });

  test('F04 阵亡队员不贡献合击伤害、扣费或动画', () {
    final g = game(3), b = battle(g);
    final dead = g.players[2]
      ..hp = 0
      ..attack = 100;
    final a = begin(b, g.players.first, 'coop');
    expect(999 - b.monsters.single.hp, 32);
    expect(a.cooperativeOrigins.containsKey(dead), isFalse);
    final origin = (dead.combatX, dead.combatY);
    for (var i = 0; i < 12; i++) {
      b.update();
    }
    expect((dead.combatX, dead.combatY), origin);
    expect(dead.mp, 999);
  });

  test('F06 每个合击参与者分别结算饰品、毒伤、倒计时', () {
    final g = game(2), b = battle(g);
    final ally = g.players[1]
      ..hp = 100
      ..status = 8;
    ally.equipment[0] = '6:17';
    ally.statusRounds[8] = 3;
    begin(b, g.players.first, 'coop');
    finish(b);
    expect(ally.hp, 97);
    expect(ally.statusRounds[8], 2);
    expect(b.visibleRaises.any((r) => identical(r.actor, ally)), isTrue);
  });

  test('F07 一名清醒队员不能从快捷或普通入口选择合击', () {
    final g = game(2), b = battle(g);
    g.players[1].status = 1;
    b.quickCoop();
    expect(b.targetKind, isEmpty);
    b.icon = 4;
    b.key(GameKey.confirm, false);
    expect(b.targetKind, isEmpty);
    expect(b.queue, isEmpty);
  });

  test('F07 执行前重新检查两名可行动者', () {
    final g = game(2), b = battle(g);
    g.players[1].status = 1;
    g.players[1].statusRounds[1] = 2;
    begin(b, g.players.first, 'coop');
    expect(b.monsters.single.hp, 999);
    expect(g.players.map((p) => p.mp), everyElement(999));
  });

  test('F07 发起者中途阵亡不能由队友代替发动合击', () {
    final g = game(3), b = battle(g);
    g.players.first.hp = 0;
    begin(b, g.players.first, 'coop');
    expect(b.monsters.single.hp, 999);
  });

  test('F04/F07 选招保存名单后，执行前阵亡或睡眠会重新过滤', () {
    final g = game(3), b = battle(g);
    b.quickCoop();
    b.key(GameKey.confirm, false);
    final selected = b.queue.firstWhere((a) => a.kind == 'coop');
    g.players[2].hp = 0;
    g.players[1].status = 1;
    g.players[1].statusRounds[1] = 2;
    b.update();
    expect(b.monsters.single.hp, 999);
    expect(selected.cooperativeActors, [g.players.first]);
    expect(g.players[1].statusRounds[1], 1);
  });

  test('F06 睡眠队友不出手不移动但仍递减异常，避免合击冻结睡眠', () {
    final g = game(3), b = battle(g);
    final sleeping = g.players[2]
      ..status = 1
      ..attack = 100;
    sleeping.statusRounds[1] = 2;
    final a = begin(b, g.players.first, 'coop');
    expect(999 - b.monsters.single.hp, 32);
    expect(a.cooperativeOrigins.containsKey(sleeping), isFalse);
    finish(b);
    expect(sleeping.statusRounds[1], 1);
  });

  test('F07 合击被取消时全队也有状态收尾机会', () {
    final g = game(2), b = battle(g);
    g.players[1].status = 1;
    g.players[1].statusRounds[1] = 2;
    begin(b, g.players.first, 'coop');
    expect(b.monsters.single.hp, 999);
    expect(g.players[1].statusRounds[1], 1);
  });

  test('F08 新战斗清理异常和临时加成，同时保留装备免疫', () {
    final g = game(1), p = g.players.single;
    p
      ..status = 9
      ..permanentStatus = 8
      ..immunity = 8;
    p.statusRounds.addAll({1: 2, 8: 0});
    p.modifiers[32] = (25, 3);
    battle(g);
    expect(p.status, 0);
    expect(p.permanentStatus, 0);
    expect(p.statusRounds, isEmpty);
    expect(p.modifiers, isEmpty);
    expect(p.immunity, 8);
  });

  for (final exit in ['victory', 'flee']) {
    test('F08 $exit后再次遇敌清除永久毒和异常计时', () {
      final g = game(2), b = battle(g), p = g.players.first;
      p
        ..status = 8
        ..permanentStatus = 8;
      p.statusRounds[8] = 0;
      if (exit == 'victory') {
        b.forceWin();
      } else {
        b
          ..phase = 'perform'
          ..current = BattleAction(p, [], 'flee', fleeSucceeded: true);
      }
      for (var tick = 0; g.battle != null && tick < 1000; tick++) {
        b.key(GameKey.confirm, false);
        b.update();
      }
      expect(g.battle, isNull);
      battle(g);
      expect(p.status, 0);
      expect(p.permanentStatus, 0);
      expect(p.statusRounds, isEmpty);
    });
  }

  test('F09 取消没有前一个存活队员时保持当前指令和索引', () {
    final g = game(3), b = battle(g);
    g.players[0].hp = g.players[1].hp = 0;
    b.actorIndex = 2;
    b.key(GameKey.cancel, false);
    expect(b.actorIndex, 2);
  });

  test('F09 取消跳过尸体且只移除前一存活队员指令', () {
    final g = game(3), b = battle(g);
    g.players[1].hp = 0;
    b.queue.add(BattleAction(g.players.first, [b.monsters.single], 'attack'));
    b.actorIndex = 2;
    b.key(GameKey.cancel, false);
    expect(b.actorIndex, 0);
    expect(b.queue, isEmpty);
  });

  for (final kind in ['attack', 'magic']) {
    test('F10 $kind闪避保留可见MISS，并由经典画面绘制', () {
      final g = game(1)..allowMiss = true, b = battle(g);
      final a = begin(
        b,
        g.players.single,
        kind,
        resource: kind == 'magic' ? '1:1' : null,
      );
      expect(b.monsters.single.hp, 999);
      expect(a.raises.any((r) => r.showing), isTrue);
      a
        ..frame = 6
        ..stage = 2;
      b.draw();
      expect(g.surface.textRuns.any((r) => r.text == 'MISS'), isTrue);
    });
  }

  test('合击发起者优先的同一出手名单驱动彩色阵型', () {
    final g = game(3), b = battle(g);
    final p = g.players[1];
    final a = begin(b, p, 'coop');
    for (var i = 0; i < 10; i++) {
      b.update();
    }
    expect(a.cooperativeActors.first, same(p));
    expect(ModernBattleLayout(b).point(p), const ui.Offset(384, 248));
  });

  testWidgets('F10 彩色画面真实绘制MISS上浮，不依赖零伤害数字', (tester) async {
    await tester.runAsync(() async {
      final art = await ModernArt.load();
      final g = game(1)..allowMiss = true, b = battle(g);
      final a = begin(b, g.players.single, 'attack')
        ..frame = 6
        ..stage = 2;
      Future<Uint8List> render() async {
        final recorder = ui.PictureRecorder();
        ModernScenePainter(
          g,
          art,
        ).paint(ui.Canvas(recorder), const ui.Size(640, 384));
        final picture = recorder.endRecording();
        final image = await picture.toImage(640, 384);
        try {
          return (await image.toByteData())!.buffer.asUint8List();
        } finally {
          image.dispose();
          picture.dispose();
        }
      }

      try {
        final visible = await render();
        for (final r in a.raises) {
          r.showing = false;
        }
        final hidden = await render();
        var changed = 0;
        for (var i = 0; i < visible.length; i++) {
          if (visible[i] != hidden[i]) changed++;
        }
        expect(changed, greaterThan(80));
      } finally {
        art.dispose();
      }
    });
  });

  test('单目标合击与明确全体动作保持各自目标模式', () {
    final g = game(2), b = battle(g);
    final p = g.players.first
      ..maxMp = 2000
      ..mp = 1500;
    p.equipment[0] = '6:1';
    final a = BattleAction(p, [b.monsters.single], 'coop', targetsAll: true);
    b
      ..phase = 'perform'
      ..current = a;
    b.update();
    expect(a.targetsAll, isTrue);
    expect(a.movie?.id, '2:242');
    expect(p.mp, 1500 - data.record(4, 1, 26)!.byte(4));
    expect(p.maxMp, 2000);
  });

  test('普通成长超过999后战斗不会截断属性和吸血回复', () {
    final g = game(2), b = battle(g);
    g.players.first
      ..maxHp = 5000
      ..hp = 3000
      ..attack = 1200;
    b.monsters.single.maxHp = b.monsters.single.hp = 10000;
    begin(b, g.players.first, 'coop');
    expect(g.players.first.attack, 1200);
    expect(g.players.first.hp, 3000);
    expect(b.monsters.single.hp, lessThan(9000));
  });
}

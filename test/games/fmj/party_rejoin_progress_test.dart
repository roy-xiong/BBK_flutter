import 'dart:convert';
import 'dart:io';
import 'package:bbk_flutter/games/fmj/data/save_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bbk_flutter/games/fmj/data/game_data.dart';
import 'package:bbk_flutter/games/fmj/engine/game_engine.dart';
import 'package:bbk_flutter/games/fmj/engine/game_actor.dart';
import 'package:bbk_flutter/games/fmj/ui/system_font_layout.dart';
import 'game_engine_test.dart' show loadData;

/// 经原剧情离队/重逢入口复现，1000倍经验由真实战斗胜利发放，不用作弊写满级掩盖问题。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GameData data;
  setUpAll(() async => data = await loadData());
  GameEngine game() => GameEngine(data, textLayout: FlutterSystemFontLayout())
    ..screen = 'play'
    ..intro = null
    ..map = data.maps['2:7']
    ..screenX = 7
    ..screenY = 5
    ..players.add(
      GameActor.load(data, 1, 1)!
        ..x = 11
        ..y = 8,
    )
    ..cursor = (ScriptCursor(data.scripts['2:2']!)..running = false);
  void execute(GameEngine g, String script, int address) {
    g.battle = null;
    g.operation = null;
    g.menus.clear();
    final s = data.scripts[script]!;
    g.cursor = ScriptCursor(s)..pointer = s.addresses[address]!;
    g.update();
    expect(g.error, isEmpty);
    g.operation = null;
    g.battle = null;
    g.cursor!.running = false;
  }

  void train(GameEngine g) {
    g.addGoods('7:33');
    g.equip(g.player!, '7:33');
    g.setPreference('ringBlade', {'experienceMultiplier': 1000});
    final b = g.battle = GameBattle(
      g,
      monsters: [1],
      background: [2, 2, 2],
      randomFight: true,
    )..totalExp = 1000;
    b.forceWin();
    g.battle = null;
  }

  Map<String, dynamic> progress(GameActor p) {
    final row = p.toJson();
    for (final key in ['x', 'y', 'direction', 'step']) {
      row.remove(key);
    }
    return row;
  }

  test('小梅初次入队后1000倍打满级，真实离队再重逢仍保留全部成长', () {
    final g = game();
    execute(g, '3:9', 694);
    train(g);
    final x = g.players.singleWhere((p) => p.index == 2);
    expect(x.level, 60);
    g.addGoods('7:31');
    g.equip(x, '7:31');
    g.addGoods('11:16');
    g.consumeMedicine(x, '11:16');
    x.extraMagic.add('1:11');
    final before = progress(x);
    execute(g, '3:12', 362);
    expect(g.players.map((p) => p.index), [1]);
    execute(g, '3:11', 391);
    final after = g.players.singleWhere((p) => p.index == 2);
    expect(after.level, 60);
    expect(progress(after), before);
  });
  test('离队中间保存重开后，重新邀请小梅仍用原队员而非ROM初始值', () {
    final g = game();
    execute(g, '3:9', 694);
    train(g);
    final before = progress(g.players.last);
    execute(g, '3:12', 362);
    final save = GameData.decodeObject(jsonEncode(g.snapshot()));
    final next = game();
    next.restore(save);
    execute(next, '3:11', 391);
    expect(progress(next.players.singleWhere((p) => p.index == 2)), before);
  });
  test('袁萍芷钟山离队后在摄魂阵救回，也不能重置等级装备和额外法术', () {
    final g = game();
    execute(g, '3:9', 694);
    execute(g, '8:11', 100);
    train(g);
    final yuan = g.players.last;
    g.addGoods('7:33');
    g.equip(yuan, '7:33');
    yuan.extraMagic.add('3:8');
    final before = progress(yuan);
    execute(g, '8:12', 1152);
    expect(g.players.any((p) => p.index == 3), false);
    execute(g, '9:13', 2375);
    expect(progress(g.players.singleWhere((p) => p.index == 3)), before);
  });
  test('重复入队指令不会复制角色；显式新游戏清掉上轮离队缓存', () {
    final g = game();
    execute(g, '3:9', 694);
    train(g);
    execute(g, '3:11', 391);
    expect(g.players.where((p) => p.index == 2), hasLength(1));
    execute(g, '3:12', 362);
    g.startNewGame();
    for (var i = 0; i < 200; i++) {
      g.update();
      if (g.operation != null) g.press(GameKey.confirm);
      if (g.players.isNotEmpty) break;
    }
    execute(g, '3:9', 694);
    expect(g.players.singleWhere((p) => p.index == 2).level, 4);
  });
  test('离队数据类型错误或身份重复时读档原子失败，正常旧档可读取', () {
    final g = game();
    execute(g, '3:9', 694);
    train(g);
    execute(g, '3:12', 362);
    final saved = GameData.decodeObject(jsonEncode(g.snapshot()));
    expect((saved['partyReserve'] as Map).keys, ['2']);
    final baseline = jsonEncode(g.snapshot());
    for (final change in ['type', 'number', 'duplicate']) {
      final bad = GameData.decodeObject(jsonEncode(saved));
      if (change == 'type') {
        bad['partyReserve'] = [];
      }
      if (change == 'number') {
        ((bad['partyReserve'] as Map)['2'] as Map)['level'] = '60';
      }
      if (change == 'duplicate') {
        (bad['players'] as List).add((bad['partyReserve'] as Map)['2']);
      }
      expect(() => g.restore(bad), throwsFormatException);
      expect(jsonEncode(g.snapshot()), baseline);
    }
    final old = GameData.decodeObject(jsonEncode(saved))
      ..remove('partyReserve');
    g.restore(old);
    expect(g.error, isEmpty);
  });
  test('剧情离队与选关缓存统一保留培养，退包的装备不会在再次入队时复制', () {
    final g = game();
    execute(g, '3:9', 694);
    train(g);
    final x = g.players.last;
    g.addGoods('7:33');
    g.equip(x, '7:33');
    final attack = x.attack;
    g.selectStage(data.stages.singleWhere((s) => s['id'] == 'stage-001'));
    expect(g.inventory['7:33'], 1, reason: '只有小梅卸下的一把退回背包');
    execute(g, '3:11', 391);
    final returned = g.players.singleWhere((p) => p.index == 2);
    expect(returned.level, 60);
    expect(returned.attack, attack - 500);
    expect(returned.equipment[4], null);
    expect(g.inventory['7:33'], 1);
    expect(g.equip(returned, '7:33'), true);
    expect(returned.attack, attack);
  });
  test('自动档和手动档写盘重开均保留离队名册，旧格式袁萍芷备份兼容迁移', () async {
    final directory = await Directory.systemTemp.createTemp(
      'fmj-party-roster-',
    );
    final repository = SaveRepository(directory: directory);
    try {
      final g = game();
      execute(g, '3:9', 694);
      train(g);
      final before = progress(g.players.last);
      execute(g, '3:12', 362);
      final snapshot = g.snapshot();
      await repository.write({
        'schema': 1,
        'autosave': snapshot,
        'slots': [snapshot, null, null],
      });
      final contents = await SaveRepository(directory: directory).read();
      for (final raw in [
        contents!['autosave'],
        (contents['slots'] as List).first,
      ]) {
        final restored = game();
        restored.restore(Map<String, dynamic>.from(raw as Map));
        execute(restored, '3:11', 391);
        expect(progress(restored.players.last), before);
      }
      final yuan = game();
      execute(yuan, '8:11', 100);
      train(yuan);
      final beforeYuan = progress(yuan.players.last);
      execute(yuan, '8:12', 1152);
      final legacy = GameData.decodeObject(jsonEncode(yuan.snapshot()))
        ..remove('partyReserve');
      final loaded = game();
      loaded.restore(legacy);
      execute(loaded, '9:13', 2375);
      expect(progress(loaded.players.last), beforeYuan);
    } finally {
      await repository.flush();
      await directory.delete(recursive: true);
    }
  });
}

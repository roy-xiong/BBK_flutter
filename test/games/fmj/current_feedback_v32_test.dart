import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bbk_flutter/games/fmj/data/game_data.dart';
import 'package:bbk_flutter/games/fmj/engine/game_actor.dart';
import 'package:bbk_flutter/games/fmj/engine/game_engine.dart';
import 'package:bbk_flutter/games/fmj/ui/game_controls.dart';
import 'package:bbk_flutter/games/fmj/ui/modern_art.dart';
import 'package:bbk_flutter/games/fmj/ui/modern_battle_effects.dart';
import 'package:bbk_flutter/games/fmj/ui/modern_battle_layout.dart';
import 'package:bbk_flutter/games/fmj/ui/modern_effect_shape.dart';
import 'package:bbk_flutter/games/fmj/ui/modern_scene.dart';
import 'package:bbk_flutter/games/fmj/ui/modern_world_objects.dart';
import 'package:bbk_flutter/games/fmj/ui/system_font_layout.dart';
import 'game_engine_test.dart' show loadData;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('特效连续轮廓使用曲线且弱键缓存，不再把每个像素画成矩形', () {
    final pixels = Uint32List(144);
    for (var y = 2; y < 10; y++) {
      for (var x = 2; x < 10; x++) {
        if ((x + y).isEven) pixels[y * 12 + x] = 0xff000000;
      }
    }
    final before = pixels.toList(), bitmap = GameBitmap(12, 12, pixels);
    final shape = ModernEffectShape.of(bitmap);
    expect(identical(shape, ModernEffectShape.of(bitmap)), true);
    expect(
      shape.path.contains(const Offset(6, 6)),
      true,
      reason: '旧棋盘抖动应重建为连续材质',
    );
    final metrics = shape.path.computeMetrics().toList();
    expect(metrics, isNotEmpty);
    var curved = false;
    for (final metric in metrics) {
      for (var t = 0.01; t < 1; t += .01) {
        final v = metric.getTangentForOffset(metric.length * t)?.vector;
        curved |= v != null && v.dx.abs() > .05 && v.dy.abs() > .05;
      }
    }
    expect(curved, true, reason: '外沿不能仍是原方块的水平/垂直边');
    expect(pixels, before, reason: '不修改原版黑白位图');
  });

  testWidgets('小屏快捷前往保持大触控区域，短按与长按入口仍可用', (tester) async {
    tester.view.physicalSize = const Size(320, 330);
    tester.view.devicePixelRatio = 1;
    final inputs = <GameControl>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: PortraitGameControlsPanel(onInput: inputs.add)),
      ),
    );
    final button = find.byKey(const ValueKey('fmj-quick-travel-large'));
    final rect = tester.getRect(button);
    expect(rect.height, greaterThanOrEqualTo(56));
    expect(rect.width, greaterThanOrEqualTo(250));
    await tester.tap(button);
    await tester.pump();
    expect(inputs, [GameControl.quickTravel]);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  testWidgets('全部68战斗和7状态动画均有细化表现，原SRS时间/叠帧只读', (tester) async {
    await tester.runAsync(() async {
      final data = await loadData();
      final keys = data.offsets.keys
          .where((k) => k.startsWith('5:2:'))
          .toList();
      expect(keys, hasLength(68));
      final recorder = ui.PictureRecorder(),
          statusRecorder = ui.PictureRecorder();
      final canvas = Canvas(statusRecorder);
      // 独立画布只用于完整画面拼图，生产绘制函数逐套调用。
      final outputCanvas = Canvas(recorder);
      final families = <String>{};
      for (var i = 0; i < keys.length; i++) {
        final key = keys[i], id = int.parse(key.split(':').last);
        final movie = GameMovie(data, 2, id)..iterations = 2;
        final timing = GameMovie(data, 2, id)..iterations = 2;
        var duration = 0;
        while (timing.update() && duration < 1000) {
          duration++;
        }
        for (var tick = 0; tick < duration ~/ 2; tick++) {
          movie.update();
        }
        final before = movie.active.map((a) => List<int>.of(a)).toList();
        families.add(ModernBattleEffects.visualFamily(movie.id));
        outputCanvas.save();
        outputCanvas.translate((i % 4) * 240.0, (i ~/ 4) * 160.0);
        outputCanvas.drawRect(
          const Rect.fromLTWH(0, 0, 240, 160),
          Paint()..color = const Color(0xff1d343b),
        );
        outputCanvas.save();
        outputCanvas.scale(.375);
        ModernBattleEffects.drawMovie(
          outputCanvas,
          movie,
          anchor: const Offset(320, 192),
        );
        outputCanvas.restore();
        final text = TextPainter(
          text: TextSpan(
            text: 'SRS 2:$id  ${ModernBattleEffects.visualFamily(movie.id)}',
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        text.paint(outputCanvas, const Offset(8, 142));
        text.dispose();
        outputCanvas.restore();
        expect(movie.active, before, reason: key);
      }
      expect(families.length, greaterThanOrEqualTo(15));
      for (var id = 240; id <= 246; id++) {
        final movie = GameMovie(data, 1, id)..iterations = 1;
        ModernBattleEffects.drawMovie(
          canvas,
          movie,
          anchor: const Offset(320, 192),
        );
      }
      statusRecorder.endRecording().dispose();
      final picture = recorder.endRecording();
      try {
        if (Platform.environment['FMJ_EXPORT_APPROVED_ART'] == '1') {
          final image = await picture.toImage(
            960,
            ((keys.length + 3) ~/ 4) * 160,
          );
          try {
            final png = await image.toByteData(format: ui.ImageByteFormat.png);
            final folder = Directory('build/validation/current-feedback-v32')
              ..createSync(recursive: true);
            File(
              '${folder.path}/all-effects.png',
            ).writeAsBytesSync(png!.buffer.asUint8List());
          } finally {
            image.dispose();
          }
        }
      } finally {
        picture.dispose();
      }
    });
  });

  test('普通攻击刀光和受击火花在实际绘制入口可用', () async {
    final data = await loadData();
    final game = GameEngine(data, textLayout: FlutterSystemFontLayout())
      ..screen = 'play'
      ..intro = null;
    game.players.add(GameActor.load(data, 1, 3)!);
    final battle = GameBattle(
      game,
      monsters: [44],
      background: [2, 2, 2],
      randomFight: true,
    );
    game.battle = battle;
    final action = BattleAction(game.players.first, battle.monsters, 'attack')
      ..started = true
      ..frame = 3;
    battle.current = action;
    final recorder = ui.PictureRecorder();
    final actualCanvas = Canvas(recorder);
    ModernBattleEffects.draw(actualCanvas, game, ModernBattleLayout(battle));
    action.frame = 6;
    action.raises.add(
      BattleRaise(
        data,
        battle.monsters.first.combatX,
        battle.monsters.first.combatY,
        -10,
        0,
        actor: battle.monsters.first,
      ),
    );
    ModernBattleEffects.draw(actualCanvas, game, ModernBattleLayout(battle));
    recorder.endRecording().dispose();
  });

  testWidgets('南北村门和名牌分层，白无常仅在酆都复用战斗身份', (tester) async {
    await tester.runAsync(() async {
      final data = await loadData(), art = await ModernArt.load();
      final game = GameEngine(data, textLayout: FlutterSystemFontLayout())
        ..screen = 'play'
        ..intro = null;
      final white = GameActor.load(data, 2, 30)!;
      game.map = data.maps['1:43'];
      expect(
        ModernWorldObjects.usesWhiteImpermanenceIdentity(game, white),
        true,
      );
      game.map = data.maps['1:39'];
      expect(
        ModernWorldObjects.usesWhiteImpermanenceIdentity(game, white),
        false,
      );
      game.map = data.maps['1:23'];
      game.sceneName = '南北村';
      game.players.add(
        GameActor.load(data, 1, 1)!
          ..x = 10
          ..y = 9,
      );
      game.npcs[1] = GameActor.load(data, 4, 19)!
        ..x = 10
        ..y = 7
        ..step = 1;
      game.npcs[2] = GameActor.load(data, 4, 20)!
        ..x = 10
        ..y = 6;
      final bounds = ModernWorldObjects.closedEntranceBounds(
        const Offset(0, 0),
        32,
      );
      expect(bounds.height, lessThan(32));
      expect(bounds.bottom, lessThan(32));
      try {
        if (Platform.environment['FMJ_EXPORT_APPROVED_ART'] == '1') {
          final recorder = ui.PictureRecorder();
          ModernScenePainter(
            game,
            art,
          ).paint(Canvas(recorder), const Size(640, 384));
          final picture = recorder.endRecording();
          final image = await picture.toImage(640, 384);
          try {
            final png = await image.toByteData(format: ui.ImageByteFormat.png);
            final folder = Directory('build/validation/current-feedback-v32')
              ..createSync(recursive: true);
            File(
              '${folder.path}/nanbei-closed-inn.png',
            ).writeAsBytesSync(png!.buffer.asUint8List());
          } finally {
            image.dispose();
            picture.dispose();
          }
        }
      } finally {
        art.dispose();
      }
    });
  });
}

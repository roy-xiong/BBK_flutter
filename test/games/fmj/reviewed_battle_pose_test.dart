import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bbk_flutter/games/fmj/engine/game_actor.dart';
import 'package:bbk_flutter/games/fmj/engine/game_engine.dart';
import 'package:bbk_flutter/games/fmj/ui/modern_art.dart';
import 'package:bbk_flutter/games/fmj/ui/modern_battle_pose.dart';
import 'package:bbk_flutter/games/fmj/ui/modern_scene.dart';
import 'package:bbk_flutter/games/fmj/ui/system_font_layout.dart';
import 'game_engine_test.dart' show loadData;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('三主角虚弱真实低头屈膝、防御举剑；正式姿态入口只读', (tester) async {
    await tester.runAsync(() async {
      final data = await loadData(), art = await ModernArt.load();
      final random = _ObservedRandom();
      final game = GameEngine(
        data,
        textLayout: FlutterSystemFontLayout(),
        random: random,
      )..intro = null;
      final sheetRecorder = ui.PictureRecorder(), sheet = Canvas(sheetRecorder);
      sheet.drawColor(const Color(0xff203238), BlendMode.src);
      const target = Rect.fromLTWH(60, 18, 192, 192);
      Future<Uint8List> pixels(
        GameActor actor, {
        bool guard = false,
        bool addToSheet = true,
      }) async {
        final recorder = ui.PictureRecorder(), canvas = Canvas(recorder);
        if (!ModernBattlePose.draw(
          canvas,
          art,
          actor,
          target,
          defending: guard,
          ticks: game.ticks,
          filterQuality: FilterQuality.medium,
        )) {
          art.drawSprite(
            canvas,
            'battle:hero:${actor.index}/${actor.combatFrame - 1}',
            target,
            Paint()..filterQuality = FilterQuality.medium,
          );
        }
        final picture = recorder.endRecording();
        final image = await picture.toImage(320, 224);
        try {
          if (addToSheet) {
            sheet.save();
            sheet.translate(
              (guard
                      ? 2
                      : actor.hp == 1
                      ? 1
                      : 0) *
                  320.0,
              (actor.index - 1) * 224.0,
            );
            sheet.drawImage(image, Offset.zero, Paint());
            sheet.restore();
          }
          return (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!.buffer.asUint8List();
        } finally {
          image.dispose();
          picture.dispose();
        }
      }

      try {
        for (var id = 1; id <= 3; id++) {
          game.ticks = 0;
          final actor = GameActor.load(data, 1, id)!
            ..maxHp = 999
            ..hp = 800;
          game.players.add(actor);
          final idle = await pixels(actor);
          actor.hp = 1;
          actor.combatFrame = 11;
          final before = [
            actor.hp,
            actor.mp,
            actor.status,
            actor.combatX,
            actor.combatY,
            actor.combatFrame,
            game.ticks,
          ];
          final calls = random.calls;
          final weak = await pixels(actor);
          expect(
            _differentPixels(idle, weak),
            greaterThan(1800),
            reason: '$id 低血不能继续复用完整站立轮廓',
          );
          expect(
            _inkTop(weak),
            greaterThan(_inkTop(idle) + 8),
            reason: '$id 必须低头并降低身体重心',
          );
          expect([
            actor.hp,
            actor.mp,
            actor.status,
            actor.combatX,
            actor.combatY,
            actor.combatFrame,
            game.ticks,
          ], before);
          expect(random.calls, calls, reason: '绘图不能消耗战斗随机数');
          game.ticks = 12;
          final breathing = await pixels(actor, addToSheet: false);
          expect(
            _differentPixels(weak, breathing),
            greaterThan(80),
            reason: '$id 虚弱呼吸必须可见且只读取原时钟',
          );
          actor.hp = 800;
          actor.combatFrame = 1;
          final guard = await pixels(actor, guard: true);
          expect(
            _differentPixels(idle, guard),
            greaterThan(1800),
            reason: '$id 防御必须举臂持剑，不能只改变颜色',
          );
        }

        final battle = GameBattle(
          game,
          monsters: [44],
          background: [2, 2, 2],
          randomFight: true,
        );
        game.battle = battle;
        for (var column = 0; column < 3; column++) {
          for (final actor in game.players) {
            actor.hp = column == 1 ? 1 : 800;
            actor.combatFrame = column == 1 ? 11 : 1;
          }
          battle.defending.clear();
          if (column == 2) battle.defending.addAll(game.players);
          final before = game.players
              .map((a) => (a.hp, a.combatFrame, a.combatX, a.combatY))
              .toList();
          final calls = random.calls;
          sheet.save();
          sheet.translate(column * 320.0, 700);
          sheet.scale(.5);
          ModernScenePainter(game, art).paint(sheet, const Size(640, 384));
          sheet.restore();
          expect(
            game.players
                .map((a) => (a.hp, a.combatFrame, a.combatX, a.combatY))
                .toList(),
            before,
          );
          expect(random.calls, calls);
        }
        for (var column = 0; column < 3; column++) {
          final label = TextPainter(
            text: TextSpan(
              text: const [
                'Idle',
                'Weak: head / knees',
                'Defend: raised sword',
              ][column],
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          label.paint(sheet, Offset(column * 320.0 + 16, 675));
          label.dispose();
        }
        final picture = sheetRecorder.endRecording();
        try {
          if (Platform.environment['FMJ_EXPORT_APPROVED_ART'] == '1') {
            final image = await picture.toImage(960, 900);
            try {
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final folder = Directory('build/validation/current-feedback-v32')
                ..createSync(recursive: true);
              File(
                '${folder.path}/reviewed-poses.png',
              ).writeAsBytesSync(bytes!.buffer.asUint8List());
            } finally {
              image.dispose();
            }
          }
        } finally {
          picture.dispose();
        }
      } finally {
        if (sheetRecorder.isRecording) sheetRecorder.endRecording().dispose();
        art.dispose();
      }
    });
  });

  testWidgets('普通、出手、受击、死亡与原异常状态不被新姿态覆盖', (tester) async {
    await tester.runAsync(() async {
      final data = await loadData(), art = await ModernArt.load();
      try {
        for (var id = 1; id <= 3; id++) {
          final actor = GameActor.load(data, 1, id)!
            ..maxHp = 999
            ..hp = 1;
          for (var frame = 1; frame <= 12; frame++) {
            actor.combatFrame = frame;
            for (final guard in [false, true]) {
              if (frame == 11 || guard && frame == 1) continue;
              final recorder = ui.PictureRecorder();
              expect(
                ModernBattlePose.draw(
                  Canvas(recorder),
                  art,
                  actor,
                  const Rect.fromLTWH(0, 0, 144, 144),
                  defending: guard,
                  ticks: 0,
                  filterQuality: FilterQuality.medium,
                ),
                false,
                reason: '$id / $frame 必须保留原帧',
              );
              final picture = recorder.endRecording();
              final image = await picture.toImage(144, 144);
              final rgba = await image.toByteData(
                format: ui.ImageByteFormat.rawRgba,
              );
              expect(
                rgba!.buffer.asUint8List().every((v) => v == 0),
                true,
                reason: '回退原分支前不能向Canvas画入任何像素',
              );
              image.dispose();
              picture.dispose();
            }
          }
          for (final status in [1, 2, 4, 8]) {
            actor.status = status;
            actor.combatFrame = 11;
            final recorder = ui.PictureRecorder();
            expect(
              ModernBattlePose.draw(
                Canvas(recorder),
                art,
                actor,
                const Rect.fromLTWH(0, 0, 144, 144),
                defending: true,
                ticks: 0,
                filterQuality: FilterQuality.medium,
              ),
              false,
            );
            recorder.endRecording().dispose();
          }
        }
      } finally {
        art.dispose();
      }
    });
  });

  testWidgets('320和390手机画布的虚弱轮廓接近高分辨率预滤波参考', (tester) async {
    await tester.runAsync(() async {
      final data = await loadData(), art = await ModernArt.load();
      final recorder = ui.PictureRecorder(), gallery = Canvas(recorder);
      gallery.drawColor(const Color(0xff203238), BlendMode.src);
      const target = Rect.fromLTWH(32, 24, 144, 144);
      final metrics = <Map<String, Object>>[];
      Future<ui.Image> render(GameActor actor, double scale, int extent) async {
        final recorder = ui.PictureRecorder(), canvas = Canvas(recorder);
        canvas.scale(scale);
        expect(
          ModernBattlePose.draw(
            canvas,
            art,
            actor,
            target,
            defending: false,
            ticks: 0,
            filterQuality: FilterQuality.medium,
          ),
          true,
        );
        final picture = recorder.endRecording();
        try {
          return await picture.toImage(extent, extent);
        } finally {
          picture.dispose();
        }
      }

      try {
        for (var id = 1; id <= 3; id++) {
          final actor = GameActor.load(data, 1, id)!
            ..maxHp = 999
            ..hp = 1
            ..combatFrame = 11;
          for (var column = 0; column < 2; column++) {
            final screenWidth = column == 0 ? 320 : 390;
            final scale = screenWidth / 640;
            final extent = (224 * scale).ceil();
            final actual = await render(actor, scale, extent);
            final large = await render(actor, scale * 8, extent * 8);
            final referenceRecorder = ui.PictureRecorder();
            final referenceCanvas = Canvas(referenceRecorder);
            referenceCanvas.drawImageRect(
              large,
              Rect.fromLTWH(
                0,
                0,
                large.width.toDouble(),
                large.height.toDouble(),
              ),
              Rect.fromLTWH(0, 0, extent.toDouble(), extent.toDouble()),
              Paint()..filterQuality = FilterQuality.medium,
            );
            final referencePicture = referenceRecorder.endRecording();
            final reference = await referencePicture.toImage(extent, extent);
            try {
              final a = (await actual.toByteData(
                format: ui.ImageByteFormat.rawRgba,
              ))!.buffer.asUint8List();
              final b = (await reference.toByteData(
                format: ui.ImageByteFormat.rawRgba,
              ))!.buffer.asUint8List();
              var partial = 0, referencePartial = 0, visible = 0;
              var difference = 0.0;
              for (var p = 0; p < a.length; p += 4) {
                final alpha = a[p + 3], referenceAlpha = b[p + 3];
                if (alpha >= 16 && alpha <= 239) partial++;
                if (referenceAlpha >= 16 && referenceAlpha <= 239) {
                  referencePartial++;
                }
                if (math.max(alpha, referenceAlpha) <= 16) continue;
                visible++;
                difference += (alpha - referenceAlpha).abs();
                for (var channel = 0; channel < 3; channel++) {
                  difference +=
                      (a[p + channel] * alpha / 255 -
                              b[p + channel] * referenceAlpha / 255)
                          .abs();
                }
              }
              final error = difference / (4 * math.max(visible, 1));
              metrics.add({
                'hero': id,
                'screenWidth': screenWidth,
                'edgePixels': partial,
                'referenceEdgePixels': referencePartial,
                'premultipliedError': error,
              });
              expect(
                referencePartial,
                greaterThan(30),
                reason: '参考必须包含可测量的平滑轮廓',
              );
              expect(
                partial,
                greaterThanOrEqualTo(referencePartial * .65),
                reason: '$id / $screenWidth 缩小后不能丢失大部分轮廓覆盖率',
              );
              expect(
                partial,
                lessThanOrEqualTo(referencePartial * 1.5),
                reason: '$id / $screenWidth 不能依赖过度模糊掩盖锯齿',
              );
              expect(
                error,
                lessThan(16),
                reason: '$id / $screenWidth 要接近8倍分辨率过滤后的可见细节',
              );
              for (var side = 0; side < 2; side++) {
                final image = side == 0 ? actual : reference;
                gallery.drawImageRect(
                  image,
                  Rect.fromLTWH(0, 0, extent.toDouble(), extent.toDouble()),
                  Rect.fromLTWH(
                    (column * 2 + side) * 224.0,
                    id * 224.0,
                    224,
                    224,
                  ),
                  Paint()..filterQuality = FilterQuality.none,
                );
              }
            } finally {
              actual.dispose();
              large.dispose();
              reference.dispose();
              referencePicture.dispose();
            }
          }
        }
        for (var column = 0; column < 4; column++) {
          final label = TextPainter(
            text: TextSpan(
              text:
                  '${column < 2 ? 320 : 390}px ${column.isEven ? 'actual' : '8x reference'}',
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          label.paint(gallery, Offset(column * 224.0 + 8, 200));
          label.dispose();
        }
        final picture = recorder.endRecording();
        try {
          if (Platform.environment['FMJ_EXPORT_APPROVED_ART'] == '1') {
            final image = await picture.toImage(896, 896);
            try {
              final png = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final folder = Directory('build/validation/current-feedback-v32')
                ..createSync(recursive: true);
              File(
                '${folder.path}/reviewed-poses-small.png',
              ).writeAsBytesSync(png!.buffer.asUint8List());
              File(
                '${folder.path}/reviewed-poses-small-metrics.json',
              ).writeAsStringSync(
                const JsonEncoder.withIndent('  ').convert(metrics),
              );
            } finally {
              image.dispose();
            }
          }
        } finally {
          picture.dispose();
        }
      } finally {
        if (recorder.isRecording) recorder.endRecording().dispose();
        art.dispose();
      }
    });
  });

  test('真实防御仍在原两次update结束，表现标记保留到既有回合清空点', () async {
    final data = await loadData();
    for (var id = 1; id <= 3; id++) {
      final game = GameEngine(data, textLayout: FlutterSystemFontLayout())
        ..intro = null;
      final actor = GameActor.load(data, 1, id)!;
      actor.equipment.fillRange(0, actor.equipment.length, null);
      game.players.add(actor);
      final battle = GameBattle(
        game,
        monsters: [44],
        background: [2, 2, 2],
        randomFight: true,
      );
      game.battle = battle;
      final hp = actor.hp;
      final action = BattleAction(actor, [actor], 'defend');
      battle.phase = 'perform';
      battle.queue.add(action);
      battle.update();
      expect(battle.current, same(action));
      expect(battle.defending, contains(actor));
      battle.update();
      expect(battle.current, isNull);
      expect(action.tick, 1);
      expect(action.frame, 0);
      expect(actor.hp, hp, reason: '防御标记不能修改伤害或生命值');
      expect(battle.defending, contains(actor), reason: '末帧600ms仍显示防御姿态');
      battle.update();
      expect(battle.phase, 'select');
      expect(battle.defending, isEmpty);
    }
  });
}

int _differentPixels(Uint8List a, Uint8List b) {
  var count = 0;
  for (var i = 0; i < a.length; i += 4) {
    if (a[i] != b[i] ||
        a[i + 1] != b[i + 1] ||
        a[i + 2] != b[i + 2] ||
        a[i + 3] != b[i + 3]) {
      count++;
    }
  }
  return count;
}

int _inkTop(Uint8List rgba) {
  for (var i = 3; i < rgba.length; i += 4) {
    if (rgba[i] > 128) return i ~/ 4 ~/ 320;
  }
  return 224;
}

/// 观察真正的Random调用，不能在姿态入口消耗随机数改变原战斗结果。
final class _ObservedRandom implements math.Random {
  final math.Random _delegate = math.Random(32);
  int calls = 0;
  @override
  bool nextBool() {
    calls++;
    return _delegate.nextBool();
  }

  @override
  double nextDouble() {
    calls++;
    return _delegate.nextDouble();
  }

  @override
  int nextInt(int max) {
    calls++;
    return _delegate.nextInt(max);
  }
}

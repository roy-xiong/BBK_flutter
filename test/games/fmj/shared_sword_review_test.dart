import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bbk_flutter/games/fmj/data/game_data.dart';
import 'package:bbk_flutter/games/fmj/ui/modern_battle_effects.dart';
import 'package:bbk_flutter/games/fmj/ui/modern_battle_semantics.dart';
import 'game_engine_test.dart' show loadData;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('九套剑体共享造型；所有活动帧中心与原版wide公式一致，绘制不改SRS', (tester) async {
    await tester.runAsync(() async {
      final data = await loadData();
      final recorder = ui.PictureRecorder(), canvas = Canvas(recorder);
      var row = 0;
      for (final id in ModernBattleSwords.movieIds) {
        final number = int.parse(id.split(':').last);
        final movie = GameMovie(data, 2, number)..iterations = 2;
        var duration = 0;
        while (movie.update()) {
          duration++;
          expect(duration, lessThan(1000));
        }
        final samples = [for (var i = 1; i <= 4; i++) duration * i ~/ 5];
        final animation = GameMovie(data, 2, number)..iterations = 2;
        var tick = 0, column = 0;
        while (animation.active.isNotEmpty) {
          final first = animation.headers.first,
              reference = animation.bitmaps[first[4]];
          for (final active in animation.active) {
            final h = animation.headers[active[0]],
                image = animation.bitmaps[h[4]];
            // 直接采用game_render.dart的原wide位图左上角+半尺寸，再放大到640，
            // 与新的共同参考点比较；不是用当前图片尺寸逐帧重新居中。
            double classicCenter(int coordinate, int size) =>
                ((coordinate * 2 + size / 2).round() + size / 2) * 2;
            for (final full in [true, false]) {
              const anchor = Offset(320, 180);
              final origin = ModernBattleSwords.frameOrigin(
                animation,
                active[0],
                anchor,
                fullScreen: full,
              );
              final actual = origin + Offset(image.width * 2, image.height * 2);
              final expected =
                  Offset(
                    classicCenter(h[0], image.width),
                    classicCenter(h[1], image.height),
                  ) -
                  (full
                      ? Offset.zero
                      : Offset(
                          classicCenter(first[0], reference.width),
                          classicCenter(first[1], reference.height),
                        )) +
                  (full ? Offset.zero : anchor);
              expect(
                actual.dx,
                closeTo(expected.dx, .001),
                reason: '$id ${active[0]} X',
              );
              expect(
                actual.dy,
                closeTo(expected.dy, .001),
                reason: '$id ${active[0]} Y',
              );
            }
          }
          if (column < 4 && tick >= samples[column]) {
            final before = animation.active.map((r) => r.toList()).toList();
            canvas.save();
            canvas.translate(column * 240.0, row * 160.0);
            canvas.drawRect(
              const Rect.fromLTWH(0, 0, 240, 160),
              Paint()..color = const Color(0xff294139),
            );
            canvas.scale(.375);
            ModernBattleEffects.drawMovie(
              canvas,
              animation,
              anchor: const Offset(320, 180),
            );
            canvas.restore();
            expect(animation.active, before);
            column++;
          }
          if (!animation.update()) break;
          tick++;
        }
        row++;
      }
      final picture = recorder.endRecording();
      try {
        if (Platform.environment['FMJ_EXPORT_APPROVED_ART'] == '1') {
          final image = await picture.toImage(960, row * 160);
          try {
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final dir = Directory('build/validation/current-feedback-v32')
              ..createSync(recursive: true);
            File(
              '${dir.path}/shared-swords.png',
            ).writeAsBytesSync(bytes!.buffer.asUint8List());
          } finally {
            image.dispose();
          }
        }
      } finally {
        picture.dispose();
      }
    });
  });

  testWidgets('御魔剑诀保留首把剑原驻留与重叠位置，没有独立编排的扇形插值', (tester) async {
    await tester.runAsync(() async {
      final data = await loadData(),
          movie = GameMovie(data, 2, 15)..iterations = 2;
      // 原第7个header为47,34，寿命25；太极11x9换剑19x19后也必须使用同一基准。
      final header = movie.headers[7];
      expect(header, [47, 34, 25, 3, 3]);
      movie.active
        ..clear()
        ..add([7, 25, 3]);
      expect(ModernBattleSwords.angle('2:15', 3), 3 * math.pi / 4);
      final recorder = ui.PictureRecorder(), canvas = Canvas(recorder);
      final custom = ModernBattleSemantics.drawComposition(
        canvas,
        movie,
        const Offset(320, 180),
        const [Colors.white, Colors.amber, Colors.brown],
      );
      expect(custom, false, reason: '剑帧不能再次被整体自定义飞行覆盖');
      ModernBattleEffects.drawMovie(
        canvas,
        movie,
        anchor: const Offset(320, 180),
        fullScreen: true,
      );
      final picture = recorder.endRecording(),
          image = await picture.toImage(640, 384);
      try {
        final bytes = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!.buffer.asUint8List();
        var left = 640, top = 384, right = 0, bottom = 0;
        for (var y = 0; y < 384; y++) {
          for (var x = 0; x < 640; x++) {
            if (bytes[(y * 640 + x) * 4 + 3] > 100) {
              left = math.min(left, x);
              top = math.min(top, y);
              right = math.max(right, x);
              bottom = math.max(bottom, y);
            }
          }
        }
        final center = Offset((left + right) / 2, (top + bottom) / 2);
        final expected =
            ModernBattleSwords.frameOrigin(
              movie,
              7,
              const Offset(320, 180),
              fullScreen: true,
            ) +
            const Offset(38, 38);
        expect((center - expected).distance, lessThan(2));
        expect(right - left, greaterThan(60));
        expect(bottom - top, greaterThan(60));
        expect(movie.active, [
          [7, 25, 3],
        ]);
      } finally {
        image.dispose();
        picture.dispose();
      }
    });
  });

  test('剑体朝向覆盖八方向，非剑素材不按名字硬替换', () {
    for (var image = 0; image < 8; image++) {
      expect(ModernBattleSwords.angle('2:2', image), (image - 4) * math.pi / 4);
    }
    for (final id in [
      '2:3',
      '2:6',
      '2:10',
      '2:21',
      '2:22',
      '2:23',
      '2:24',
      '2:55',
    ]) {
      expect(ModernBattleSwords.movieIds.contains(id), false);
    }
    expect(
      ModernBattleSwords.angle('2:202', 4),
      isNull,
      reason: '巨剑后的落石仍用原资源类型',
    );
  });
}

import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bbk_flutter/games/fmj/data/game_data.dart';
import 'package:bbk_flutter/games/fmj/ui/battle_calligraphy.dart';
import 'package:bbk_flutter/games/fmj/ui/modern_battle_effects.dart';
import 'package:bbk_flutter/games/fmj/ui/modern_battle_semantics.dart';
import 'game_engine_test.dart' show loadData;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('共用动画经正式绘制入口修订，原SRS活动帧和时间只读', (tester) async {
    await tester.runAsync(() async {
      final data = await loadData();
      final recorder = ui.PictureRecorder(), canvas = Canvas(recorder);
      var row = 0;
      for (final id in ModernBattleSemantics.correctedMovies) {
        final parts = id.split(':').map(int.parse).toList();
        final timing = GameMovie(data, parts[0], parts[1])
          ..iterations = parts[0] == 1 ? 1 : 2;
        var length = 0;
        while (timing.update()) {
          length++;
          expect(length, lessThan(1000));
        }
        for (var column = 0; column < 4; column++) {
          final movie = GameMovie(data, parts[0], parts[1])
            ..iterations = parts[0] == 1 ? 1 : 2;
          for (var tick = 0; tick < length * (column + 1) ~/ 5; tick++) {
            movie.update();
          }
          final before = movie.active.map((a) => a.toList()).toList();
          final progress = ModernBattleSemantics.progress(movie);
          expect(progress, inInclusiveRange(0.0, 1.0));
          canvas.save();
          canvas.translate(column * 240.0, row * 160.0);
          canvas.drawRect(
            const Rect.fromLTWH(0, 0, 240, 160),
            Paint()..color = const Color(0xff25413e),
          );
          canvas.save();
          canvas.scale(.375);
          ModernBattleEffects.drawMovie(
            canvas,
            movie,
            anchor: const Offset(320, 180),
          );
          canvas.restore();
          final label = TextPainter(
            text: TextSpan(
              text: '$id  ${(progress * 100).round()}%',
              style: const TextStyle(fontSize: 11, color: Colors.white),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          label.paint(canvas, const Offset(5, 143));
          label.dispose();
          canvas.restore();
          expect(movie.active, before, reason: '$id 画图不能推进原动画');
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
              '${dir.path}/reviewed-semantics.png',
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

  testWidgets('全部书法字形可见且不同，攻速毒乱眠八门不再画成通用光圈', (tester) async {
    await tester.runAsync(() async {
      final signatures = <int>{};
      for (final letter in '攻防速毒乱封眠休生伤杜景死惊开降魔'.split('')) {
        final path = BattleCalligraphy.glyphs[letter];
        expect(path, isNotNull);
        expect(path!.getBounds().isEmpty, false);
        final recorder = ui.PictureRecorder(), canvas = Canvas(recorder);
        ModernBattleSemantics.glyph(
          canvas,
          letter,
          const Rect.fromLTWH(8, 8, 112, 112),
          const [Color(0xfffff0c5), Color(0xffe6ba68), Color(0xff70493d)],
        );
        final picture = recorder.endRecording();
        final image = await picture.toImage(128, 128);
        try {
          final pixels = (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!.buffer.asUint8List();
          var ink = 0, signature = 17;
          for (var i = 0; i < pixels.length; i += 4) {
            if (pixels[i + 3] > 128) ink++;
            signature = (signature * 31 + pixels[i + 3]) & 0x7fffffff;
          }
          expect(ink, greaterThan(1200), reason: '$letter 必须具有可辨识的完整笔画');
          signatures.add(signature);
        } finally {
          image.dispose();
          picture.dispose();
        }
      }
      expect(signatures, hasLength(17), reason: '不同汉字不能复用同一个几何光圈');
    });
  });

  test('单体和全体共用原状态字资源，八门、太极与物件分派在共享SRS层', () {
    expect(ModernBattleSemantics.statusLetters, {
      '1:240': '攻',
      '1:241': '防',
      '1:242': '速',
      '1:243': '毒',
      '1:244': '乱',
      '1:245': '封',
      '1:246': '眠',
    });
    for (final id in [
      '2:14',
      '2:16',
      '2:20',
      '2:21',
      '2:22',
      '2:23',
      '2:24',
      '2:32',
      '2:40',
      '2:44',
      '2:50',
      '2:203',
      '2:204',
      '2:205',
    ]) {
      expect(ModernBattleSemantics.correctedMovies.contains(id), true);
    }
  });
}

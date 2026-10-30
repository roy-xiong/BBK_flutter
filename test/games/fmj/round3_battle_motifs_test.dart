import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bbk_flutter/games/fmj/data/game_data.dart';
import 'package:bbk_flutter/games/fmj/ui/modern_battle_effects.dart';
import 'game_engine_test.dart' show loadData;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('本轮八套SRS描绘不同实物，原帧坐标、寿命和迭代时序只读', (tester) async {
    await tester.runAsync(() async {
      final data = await loadData();
      final recorder = ui.PictureRecorder(), canvas = Canvas(recorder);
      final signatures = <int>{};
      const ids = [6, 8, 15, 37, 41, 42, 46, 47];
      for (var row = 0; row < ids.length; row++) {
        final timing = GameMovie(data, 2, ids[row])..iterations = 2;
        var duration = 0;
        while (timing.update()) {
          duration++;
          expect(duration, lessThan(1000));
        }
        for (var column = 0; column < 4; column++) {
          final movie = GameMovie(data, 2, ids[row])..iterations = 2;
          for (var tick = 0; tick < duration * (column + 1) ~/ 5; tick++) {
            movie.update();
          }
          final active = movie.active.map((x) => x.toList()).toList();
          final headers = movie.headers.map((x) => x.toList()).toList();
          canvas.save();
          canvas.translate(column * 240.0, row * 160.0);
          canvas.drawRect(
            const Rect.fromLTWH(0, 0, 240, 160),
            Paint()..color = const Color(0xff29413b),
          );
          canvas.scale(.375);
          ModernBattleEffects.drawMovie(
            canvas,
            movie,
            anchor: const Offset(320, 180),
          );
          canvas.restore();
          expect(movie.active, active);
          expect(movie.headers, headers);
          expect(movie.iterations, 2);
          if (column == 2) {
            final one = ui.PictureRecorder();
            ModernBattleEffects.drawMovie(
              Canvas(one),
              movie,
              anchor: const Offset(320, 180),
            );
            final picture = one.endRecording(),
                image = await picture.toImage(640, 384);
            try {
              final bytes = (await image.toByteData(
                format: ui.ImageByteFormat.rawRgba,
              ))!.buffer.asUint8List();
              var ink = 0, signature = 13;
              for (var i = 3; i < bytes.length; i += 4) {
                if (bytes[i] > 30) ink++;
                signature = (signature * 31 + bytes[i]) & 0x7fffffff;
              }
              expect(ink, greaterThan(400), reason: 'SRS2:${ids[row]}必须有实物笔画');
              signatures.add(signature);
            } finally {
              image.dispose();
              picture.dispose();
            }
          }
        }
      }
      expect(signatures, hasLength(8), reason: '蜜蜂/蛇/虫/钟/大小爪/地爪/飞剑不能复用同一个通用轮廓');
      final picture = recorder.endRecording();
      try {
        if (Platform.environment['FMJ_EXPORT_APPROVED_ART'] == '1') {
          final image = await picture.toImage(960, 1280);
          try {
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final dir = Directory('build/validation/current-feedback-v32')
              ..createSync(recursive: true);
            File(
              '${dir.path}/round3-motifs.png',
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
}

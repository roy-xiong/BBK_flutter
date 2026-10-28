import 'dart:io';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bbk_flutter/games/fmj/data/game_data.dart';
import 'package:bbk_flutter/games/fmj/engine/game_actor.dart';
import 'package:bbk_flutter/games/fmj/engine/game_engine.dart';
import 'package:bbk_flutter/games/fmj/ui/modern_art.dart';
import 'package:bbk_flutter/games/fmj/ui/modern_scene.dart';
import 'package:bbk_flutter/games/fmj/ui/system_font_layout.dart';
import 'game_engine_test.dart' show loadData;

/// 冻结战斗时钟，只推进原SRS动画；防止彩色渲染再次只画与招式无关的统一光圈。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('霸王横刀在彩色界面显示真实SRS帧变化，原68套战斗动画均保留', (tester) async {
    await tester.runAsync(() async {
      final data = await loadData(), art = await ModernArt.load();
      final g = GameEngine(data, textLayout: FlutterSystemFontLayout())
        ..screen = 'play'
        ..intro = null;
      g.players.add(GameActor.load(data, 1, 3)!);
      final b = GameBattle(
        g,
        monsters: [44],
        background: [2, 2, 2],
        randomFight: true,
      );
      g.battle = b;
      final resource = g.magic('1:18')!;
      expect(resource.text(6), '霸王横刀');
      expect(resource.byte(5), 24);
      final movie = GameMovie(data, 2, resource.byte(5))..iterations = 2;
      final action =
          BattleAction(g.players.first, b.monsters, 'magic', resource: '1:18')
            ..stage = 1
            ..started = true
            ..movie = movie;
      b.current = action;
      b.phase = 'perform';
      final out = Directory('build/validation/macos-v22')
        ..createSync(recursive: true);
      Future<Uint8List> capture(int frame) async {
        final recorder = ui.PictureRecorder();
        ModernScenePainter(
          g,
          art,
        ).paint(Canvas(recorder), const Size(640, 384));
        final picture = recorder.endRecording();
        final image = await picture.toImage(640, 384);
        try {
          if (Platform.environment['FMJ_EXPORT_APPROVED_ART'] == '1') {
            final png = await image.toByteData(format: ui.ImageByteFormat.png);
            File(
              '${out.path}/bawang-$frame.png',
            ).writeAsBytesSync(png!.buffer.asUint8List());
          }
          final raw = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          return Uint8List.fromList(raw!.buffer.asUint8List());
        } finally {
          image.dispose();
          picture.dispose();
        }
      }

      try {
        final frames = <Uint8List>[];
        for (var frame = 0; frame < 36; frame++) {
          if (frame % 6 == 0) frames.add(await capture(frame));
          movie.update();
        }
        expect(
          frames.skip(1).any((pixels) {
            var changed = 0;
            for (var i = 0; i < pixels.length; i += 4) {
              if (pixels[i] != frames.first[i] ||
                  pixels[i + 1] != frames.first[i + 1] ||
                  pixels[i + 2] != frames.first[i + 2]) {
                changed++;
              }
            }
            return changed > 100;
          }),
          true,
          reason: '原动画帧推进必须改变实际画面，而不是依赖game.ticks画同一套光圈',
        );
        final movies = data.offsets.keys
            .where((k) => k.startsWith('5:2:'))
            .toList();
        expect(movies.length, 68);
        for (final key in movies) {
          final index = int.parse(key.split(':').last);
          final effect = GameMovie(data, 2, index);
          expect(effect.headers, isNotEmpty, reason: key);
          expect(effect.bitmaps, isNotEmpty, reason: key);
          expect(
            effect.headers.every((h) => h[4] < effect.bitmaps.length),
            true,
            reason: key,
          );
        }
      } finally {
        art.dispose();
      }
    });
  });
}

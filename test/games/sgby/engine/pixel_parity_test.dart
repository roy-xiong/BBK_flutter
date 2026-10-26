import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:bbk_flutter/games/sgby/data/services/game_save_codec.dart';
import 'package:bbk_flutter/games/sgby/engine/core/native_game_session.dart';
import 'package:bbk_flutter/games/sgby/engine/rendering/game_display_enhancements.dart';
import 'package:bbk_flutter/games/sgby/engine/resources/baye_archive.dart';
import 'package:bbk_flutter/games/sgby/engine/resources/baye_database.dart';
import 'package:bbk_flutter/games/sgby/engine/resources/bitmap_font.dart';
import 'package:bbk_flutter/games/sgby/engine/resources/gbk_codec.dart';

import '../support/pixel_artifact.dart';

/// 参考帧由当前旧内核绘制，并注入手机已采集的同一字模，比较完整960×576像素。
/// 原背景透明像素按旧网页#b4b4b4合成，测试不会把Dart渲染结果生成参考金图。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late BayeDatabase database;
  late List<dynamic> samples;
  setUpAll(() {
    database = BayeDatabase(
      archive: BayeArchive(
        File('assets/sgby/game/SGBY-Reset-4X.lib').readAsBytesSync(),
      ),
      codec: GbkCodec(
        File('assets/sgby/game/gbk_unicode.bin').readAsBytesSync(),
      ),
      font: BitmapFont(
        File('assets/sgby/game/fallback_font12.bin').readAsBytesSync(),
        androidAtlas: File(
          'assets/sgby/game/android_font48.bin',
        ).readAsBytesSync(),
      ),
      refinedRules:
          jsonDecode(
                File('assets/sgby/game/refined_rules.json').readAsStringSync(),
              )
              as Map<String, dynamic>,
    );
    samples =
        jsonDecode(
              File(
                'test/games/sgby/fixtures/reference_pixels.json',
              ).readAsStringSync(),
            )
            as List;
  });

  for (final name in [
    'main_menu',
    'period_menu',
    'rulers',
    'strategy',
    'city_menu',
    'city_details',
  ]) {
    test('手机字模与旧内核整帧像素对照：$name', () async {
      final sample = samples.firstWhere((item) => item['name'] == name) as Map;
      final session = NativeGameSession(database, seedProvider: () => 1);
      if (name == 'main_menu') {
        session.advance(const Duration(milliseconds: 200));
        session.advance(const Duration(milliseconds: 160));
      }
      session.input(NativeInput.confirm);
      if (name == 'period_menu') {
        session.input(NativeInput.confirm);
        for (var step = 0; step < 22; step++) {
          session.advance(const Duration(milliseconds: 10));
        }
      }
      if (name == 'rulers') {
        session.input(NativeInput.confirm);
        session.input(NativeInput.confirm);
        session.renderer.rulerSelection(
          session.world!,
          session.rulers,
          0,
          0,
          blink: true,
        );
      }
      if (['strategy', 'city_menu', 'city_details'].contains(name)) {
        final base = database.loadPeriod(1, seed: 1);
        database.beginGame(base, 5);
        final codec = GameSaveCodec(), envelope = GameSaveCodec().encode(base);
        final saved = Map<String, dynamic>.from(envelope['world']! as Map)
          ..addAll(Map<String, dynamic>.from(sample['world'] as Map));
        session.replaceWorld(
          codec.decode(<String, dynamic>{...envelope, 'world': saved}),
        );
        if (name != 'strategy') session.input(NativeInput.confirm);
        if (name == 'city_details') {
          for (var i = 0; i < 3; i++) {
            session.input(NativeInput.down);
          }
          session.input(NativeInput.confirm);
        }
      }
      final actual = GameDisplayEnhancements(database).frame(
        session.canvas.surface,
        session.world,
        strategy: session.scene == NativeScene.strategy,
        roads: session.mapRoadsVisible,
        factionColors: true,
      );
      final expected = gzip.decode(
        File('test/games/sgby/fixtures/pixels_$name.rgba.gz').readAsBytesSync(),
      );
      var difference = 0, minX = 960, minY = 576, maxX = 0, maxY = 0;
      for (var i = 0; i < actual.length; i += 4) {
        if (actual[i] != expected[i] ||
            actual[i + 1] != expected[i + 1] ||
            actual[i + 2] != expected[i + 2] ||
            actual[i + 3] != expected[i + 3]) {
          difference++;
          final x = i ~/ 4 % 960, y = i ~/ 4 ~/ 960;
          minX = math.min(minX, x);
          minY = math.min(minY, y);
          maxX = math.max(maxX, x);
          maxY = math.max(maxY, y);
        }
      }
      if (difference > 0) {
        final directory = Directory('.dart_tool/pixel_failures')
          ..createSync(recursive: true);
        final image = Completer<ui.Image>();
        ui.decodeImageFromPixels(
          actual,
          960,
          576,
          ui.PixelFormat.rgba8888,
          image.complete,
        );
        final decoded = await image.future;
        final png = await decoded.toByteData(format: ui.ImageByteFormat.png);
        decoded.dispose();
        if (png != null) {
          File(
            '${directory.path}/$name.png',
          ).writeAsBytesSync(png.buffer.asUint8List());
        }
        File('${directory.path}/$name.rgba').writeAsBytesSync(actual);
      }
      session.dispose();
      expect(
        difference,
        0,
        reason: '$name: $difference个像素不同，范围($minX,$minY)~($maxX,$maxY)',
      );
      await exportPixelFrame(actual, name);
    });
  }
}

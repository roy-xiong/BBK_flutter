import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:bbk_flutter/games/sgby/data/services/game_save_codec.dart';
import 'package:bbk_flutter/games/sgby/engine/core/native_game_session.dart';
import 'package:bbk_flutter/games/sgby/engine/core/refined_help_flow.dart';
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
                'test/games/sgby/fixtures/reference_pixels_extended.json',
              ).readAsStringSync(),
            )
            as List;
  });

  for (final name in [
    'help_menu',
    'help_heroes',
    'help_heroes_1',
    'help_tools',
    'help_cities',
    'help_city_hidden',
    'people_selection',
    'general_report',
    'no_goods_report',
    'goods_selection',
    'save_menu',
  ]) {
    test('手机字模与旧内核整帧像素对照：$name', () async {
      final sample = samples.firstWhere((item) => item['name'] == name) as Map;
      final session = NativeGameSession(database);
      final base = database.loadPeriod(1, seed: 1);
      database.beginGame(base, 5);
      final codec = GameSaveCodec(), envelope = GameSaveCodec().encode(base);
      final saved = Map<String, dynamic>.from(envelope['world']! as Map)
        ..addAll(Map<String, dynamic>.from(sample['world'] as Map));
      final world = codec.decode(<String, dynamic>{
        ...envelope,
        'world': saved,
      });
      session.replaceWorld(world);
      if (name.startsWith('help_')) {
        RefinedHelpFlow(session).start();
        if (name == 'help_heroes' || name == 'help_heroes_1') {
          session.input(NativeInput.confirm);
          if (name == 'help_heroes_1') session.input(NativeInput.down);
        }
        if (name == 'help_tools') {
          session.input(NativeInput.down);
          session.input(NativeInput.confirm);
        }
        if (name == 'help_cities' || name == 'help_city_hidden') {
          session.input(NativeInput.down);
          session.input(NativeInput.down);
          session.input(NativeInput.confirm);
          if (name == 'help_city_hidden') session.input(NativeInput.confirm);
        }
        // 原菜单滚动块本身闪烁，比较参考帧对应的相位。
      } else if (name == 'people_selection') {
        session.choosePeople(world.personsInCity(0, belong: 6), (_) {});
      } else if (name == 'general_report') {
        final old = database.loadPeriod(1, seed: 1).city(0)!.farming,
            now = world.city(0)!.farming;
        final text =
            '${database.text(64, 113)}$now${database.text(64, 114)}${(now - old) & 255}${database.text(64, 115)}';
        session.showReport(text, person: 56);
      } else if (name == 'no_goods_report') {
        session.showReport(database.text(64, 86));
      } else if (name == 'goods_selection') {
        // 旧内核搜索增强只修改数据，ShowMapClear恢复搜索前缓存的战略底图。
        // 按相同先后顺序重放，避免拿搜索后的统计数重绘旧底栏。
        final previous =
            samples.firstWhere((item) => item['name'] == 'no_goods_report')
                as Map;
        final oldSaved = Map<String, dynamic>.from(envelope['world']! as Map)
          ..addAll(Map<String, dynamic>.from(previous['world'] as Map));
        session.replaceWorld(
          codec.decode(<String, dynamic>{...envelope, 'world': oldSaved}),
        );
        session.world = world;
        session.chooseTools(
          world
              .goodsInCity(3, discoveredOnly: true)
              .map((id) => id & 32767)
              .toList(),
          (_) {},
        );
      } else if (name == 'save_menu') {
        session.openSaveMenu();
      }
      var actual = GameDisplayEnhancements(database).frame(
        session.canvas.surface,
        session.world,
        strategy: session.scene == NativeScene.strategy,
        roads: session.mapRoadsVisible,
        factionColors: true,
      );
      final expected = gzip.decode(
        File(
          'test/games/sgby/fixtures/pixels_ext_$name.rgba.gz',
        ).readAsBytesSync(),
      );
      // 原版滚动块按定时消息闪烁；允许对齐两个完整帧相位，不屏蔽任何区域。
      if ([
            'help_heroes',
            'help_heroes_1',
            'help_tools',
            'help_cities',
          ].contains(name) &&
          !listEquals(actual, expected)) {
        session.advance(const Duration(milliseconds: 50));
        actual = GameDisplayEnhancements(database).frame(
          session.canvas.surface,
          session.world,
          strategy: false,
          roads: session.mapRoadsVisible,
          factionColors: true,
        );
      }
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
            '${directory.path}/ext_$name.png',
          ).writeAsBytesSync(png.buffer.asUint8List());
        }
        File('${directory.path}/ext_$name.rgba').writeAsBytesSync(actual);
      }
      session.dispose();
      expect(
        difference,
        0,
        reason: '$name: $difference个像素不同，范围($minX,$minY)~($maxX,$maxY)',
      );
      await exportPixelFrame(actual, 'extended_$name');
    });
  }
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:bbk_flutter/games/sgby/engine/rendering/cartoon_assets.dart';
import 'package:bbk_flutter/games/sgby/engine/resources/bitmap_font.dart';
import 'package:bbk_flutter/games/sgby/engine/resources/person_names.dart';

import '../support/game_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('全部800个头像按人物身份匹配剧照或原始黑白像素，无生成头像补位', () async {
    final database = loadGameDatabase();
    final registry =
        jsonDecode(
              File(
                'tool/games/sgby/art/portraits_1994.json',
              ).readAsStringSync(),
            )
            as Map;
    final approved = {
      for (final entry in registry['portraits'] as List)
        (entry as Map)['name'] as String,
    };
    final assets = await CartoonAssets.load();
    try {
      final bindings = assets.manifest['portraitIds'] as Map;
      final pixels = (await assets.atlas.toByteData())!.buffer.asUint8List();
      var photos = 0, originals = 0;
      for (var period = 1; period <= 4; period++) {
        for (var id = 0; id < 200; id++) {
          final name = database.personName(period, id);
          final key = bindings['portrait/$period/$id'] as String;
          if (approved.contains(name)) {
            expect(key, 'photo1994/$name');
            photos++;
            continue;
          }
          expect(key, startsWith('original/'));
          final source = database.pictures(47 + period)!.picture(id)!;
          final rect = assets.spriteRect(key)!;
          expect(rect.width, source.width);
          expect(rect.height, source.height);
          for (var y = 0; y < source.height; y++) {
            for (var x = 0; x < source.width; x++) {
              final position =
                  ((rect.top.toInt() + y) * assets.atlas.width +
                      rect.left.toInt() +
                      x) *
                  4;
              final expected = source.inkAt(x, y) ? 0 : 180;
              if (pixels[position] != expected ||
                  pixels[position + 1] != expected ||
                  pixels[position + 2] != expected) {
                fail('时期$period 人物$id ($name) 黑白头像像素($x,$y)发生变化');
              }
            }
          }
          originals++;
        }
      }
      expect(photos + originals, 800);
      expect(photos, greaterThan(200));
      expect(approved, hasLength(92));
    } finally {
      assets.dispose();
    }
  });

  test('正式黑白字体覆盖全部勘误汉字，避免GBK扩展字变成空白', () {
    final database = loadGameDatabase();
    final font = BitmapFont(
      File('assets/sgby/game/fallback_font12.bin').readAsBytesSync(),
      androidAtlas: File(
        'assets/sgby/game/android_font48.bin',
      ).readAsBytesSync(),
    );
    for (final name in PersonNames.corrections.values) {
      for (final rune in name.runes) {
        final bytes = database.codec.encode(String.fromCharCode(rune));
        final bitmap = font.glyph((bytes[0] << 8) | bytes[1]);
        expect(
          bitmap.data.any((byte) => byte != 0),
          isTrue,
          reason: '${String.fromCharCode(rune)}在黑白模式不可见',
        );
      }
    }
  });
}

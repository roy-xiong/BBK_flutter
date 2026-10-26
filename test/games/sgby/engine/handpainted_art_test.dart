import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:bbk_flutter/games/sgby/engine/rendering/cartoon_assets.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('手绘资源完整覆盖六兵种、动作、退场、场景与材质，没有旧模型素材补位', () async {
    final assets = await CartoonAssets.load();
    try {
      expect(assets.manifest['style'], 'hand-painted Chinese 2.5D');
      final sources = assets.manifest['spriteSources'] as Map;
      final sprites = assets.manifest['sprites'] as Map;
      const poses = ['idle', 'stride', 'windup', 'attack', 'hit', 'down'];
      for (final side in ['friendly', 'enemy']) {
        for (var kind = 0; kind < 6; kind++) {
          for (final pose in poses) {
            final key = 'unit/$side/$kind/$pose';
            expect(assets.spriteRect(key), isNotNull, reason: key);
            expect(sources[key], isA<Map>(), reason: '$key缺少原稿绑定');
          }
          if (kind == 1 || kind == 2) {
            for (final pose in ['idle', 'stride']) {
              final key = 'unit/$side/$kind/field_$pose';
              expect(assets.spriteRect(key), isNotNull, reason: key);
              expect(sources[key], isA<Map>(), reason: '$key缺少战场轮廓原稿');
            }
          }
          for (var frame = 0; frame < 6; frame++) {
            final key = 'defeat/$side/$kind/$frame';
            expect(assets.spriteRect(key), isNotNull, reason: key);
            expect(sources[key], isA<Map>(), reason: '$key缺少原稿绑定');
          }
        }
      }
      for (final prefix in [
        'city/capital',
        'city/fort',
        'city/harbor',
        'city/battle',
        'terrain/mountain',
        'terrain/tree',
        'terrain/village',
        'terrain/camp',
        'icon/supplies',
        'icon/sun',
        'icon/cloud',
        'icon/wind',
        'icon/rain',
        'icon/hail',
        'scene/field',
        'scene/river',
        'scene/forest',
        'scene/siege',
        'scene/victory',
        'scene/defeat',
        'ground/dirt',
        'ground/water',
        'ui/paper',
        'effect/slash',
        'effect/impact',
        'effect/fire',
        'effect/water',
        'effect/mist',
        'effect/level',
        'effect/log',
        'effect/rock',
        'effect/trap',
      ]) {
        expect(assets.spriteRect(prefix), isNotNull, reason: prefix);
        expect(sources[prefix], isA<Map>(), reason: '$prefix缺少手绘原稿绑定');
      }
      for (final key in sprites.keys.cast<String>()) {
        if (key.startsWith('original/') || key.startsWith('photo1994/')) {
          continue;
        }
        expect(sources.containsKey(key), isTrue, reason: '$key出现没有原稿记录的旧素材');
      }
      final bytes =
          (assets.atlas.width * assets.atlas.height +
              assets.map.width * assets.map.height +
              assets.texture.width * assets.texture.height) *
          4;
      expect(bytes, lessThanOrEqualTo(64 * 1024 * 1024));
      expect(assets.atlas.width, lessThanOrEqualTo(4096));
      expect(assets.atlas.height, lessThanOrEqualTo(4096));
    } finally {
      assets.dispose();
    }
  });

  test('角色抠图没有残留荧光绿幕，六兵种的实体像素各不相同', () async {
    final assets = await CartoonAssets.load();
    try {
      final bytes = (await assets.atlas.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!.buffer.asUint8List();
      for (final side in ['friendly', 'enemy']) {
        final identities = <int>{};
        for (var kind = 0; kind < 6; kind++) {
          final rect = assets.spriteRect('unit/$side/$kind/idle')!;
          var brightGreen = 0, opaque = 0, fingerprint = 2166136261;
          for (var y = rect.top.toInt(); y < rect.bottom.toInt(); y++) {
            for (var x = rect.left.toInt(); x < rect.right.toInt(); x++) {
              final p = (y * assets.atlas.width + x) * 4;
              for (var channel = 0; channel < 4; channel++) {
                fingerprint =
                    ((fingerprint ^ bytes[p + channel]) * 16777619) &
                    0xffffffff;
              }
              if (bytes[p + 3] < 128) continue;
              opaque++;
              if (bytes[p + 1] > 170 &&
                  bytes[p + 1] > bytes[p] * 2 &&
                  bytes[p + 1] > bytes[p + 2] * 2) {
                brightGreen++;
              }
            }
          }
          expect(opaque, greaterThan(500));
          expect(
            brightGreen / opaque,
            lessThan(.001),
            reason: '$side/$kind残留绿幕',
          );
          identities.add(fingerprint);
        }
        expect(identities, hasLength(6), reason: '$side不同兵种使用了同一张实体图');
      }
    } finally {
      assets.dispose();
    }
  });
}

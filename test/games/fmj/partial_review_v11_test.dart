import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bbk_flutter/games/fmj/data/game_data.dart';
import 'package:bbk_flutter/games/fmj/ui/modern_art.dart';

/// 审核补丁不能借共享图块改变已通过/未审核场景；所有新图必须真正接入生产加载。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('64张未修改地图含4张已通过地图保持原布局且无场景图块覆写', () {
    final hd = GameData.decodeObject(
      File('assets/fmj/modern/enhanced-art.json').readAsStringSync(),
    );
    final original = GameData.decodeObject(
      File(
        'test/games/fmj/fixtures/unreviewed_v11_layout.json',
      ).readAsStringSync(),
    );
    expect(original.length, 64);
    for (final entry in original.entries) {
      expect(
        hd['buildings'][entry.key] ?? [],
        entry.value['buildings'],
        reason: entry.key,
      );
      expect(
        hd['decorations'][entry.key] ?? [],
        entry.value['decorations'],
        reason: entry.key,
      );
      expect(hd['tileOverrides'][entry.key], isNull, reason: entry.key);
    }
    for (final id in ['1:21', '1:22', '1:24', '1:26']) {
      expect(original, contains(id));
    }
    expect((hd['partialReviewV11']['maps'] as List), hasLength(19));
  });

  testWidgets('新图和限定地图规则从正式ModernArt加载，三清宫陈设及四象各有完整资源', (tester) async {
    await tester.runAsync(() async {
      final art = await ModernArt.load();
      try {
        expect(art.tileOverrides['1:3']?[32]?.$1, 'earth');
        expect(art.tileOverrides['1:3']?[86]?.$3, 'review-v11:edge-86/0');
        expect(art.tileOverrides['1:13']?[19]?.$1, 'bamboo-forest');
        expect(art.tileOverrides['1:10'], isNull);
        for (final key in [
          'water-jar',
          'temple-censer',
          'potted-shrub',
          'lotus',
          'signpost',
          'granary',
          'guardian-dragon',
          'guardian-tiger',
          'guardian-bird',
          'guardian-tortoise',
        ]) {
          expect(art.sprites, contains('review-v11:$key/0'));
        }
        final guardians = ['dragon', 'tiger', 'bird', 'tortoise']
            .map((kind) => art.sprites['review-v11:guardian-$kind/0']!.rect)
            .toSet();
        expect(guardians, hasLength(4), reason: '四象不能继续共用同一根盘龙柱');
        expect(
          art.decorations['1:1']!.where(
            (b) => b.key == 'review-v11:temple-censer',
          ),
          hasLength(2),
        );
        expect(
          art.decorations['1:1']!.any((b) => b.key == 'review-v11:water-jar'),
          true,
        );
      } finally {
        art.dispose();
      }
    });
  });
}

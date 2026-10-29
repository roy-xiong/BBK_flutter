import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bbk_flutter/games/fmj/ui/modern_art.dart';

/// 第三轮审核同时约束已通过场景、底材语义和新物件真实加载，防止只补效果稿。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Map read(String path) => jsonDecode(File(path).readAsStringSync()) as Map;
  final hd = read('assets/fmj/modern/enhanced-art.json');
  final baseline = read('tool/art_sources/review-v14/baseline-layout.json');
  final scope = read('tool/art_sources/review-v14/scope.json');
  final guide = read('assets/fmj/game/FmjGuideData.json');
  final maps = {for (final m in guide['maps'] as List) m['id']: m as Map};

  test('44项已通过内容保持原场景布局及底材规则，32张本轮地图逐项有修改说明', () {
    expect(scope['approved'], hasLength(44));
    expect(hd['reviewRound3']['maps'], hasLength(32));
    for (final id in scope['approved'] as List) {
      if (!maps.containsKey(id)) continue;
      for (final kind in ['buildings', 'decorations', 'tileOverrides']) {
        expect(hd[kind][id], baseline[kind][id], reason: '$id/$kind');
      }
      expect(hd['groundOverrides'][id], isNull, reason: '$id 已通过底图');
    }
    final fixes = read('tool/review_v14_fixes.json');
    for (final id in hd['reviewRound3']['maps'] as List) {
      expect(fixes[id], isNotEmpty, reason: '$id 必须保留复审说明');
      for (final b in hd['decorations'][id] as List) {
        expect(hd['frames'], contains('${b['key']}/0'));
      }
    }
  });

  test('静态箱子、路牌、六座谷仓及十二座石灯接管原格位', () {
    final pharmacy = hd['decorations']['2:1'] as List;
    expect(
      pharmacy.any(
        (b) => b['key'] == 'review-v14:chest' && b['x'] == 15 && b['y'] == 3,
      ),
      true,
    );
    for (final id in ['1:40', '1:41', '1:42']) {
      expect(
        (hd['decorations'][id] as List).any(
          (b) => b['key'] == 'review-v11:signpost',
        ),
        true,
      );
    }
    expect(
      (hd['decorations']['1:41'] as List).where(
        (b) => b['key'] == 'review-v11:granary',
      ),
      hasLength(6),
    );
    expect(
      (hd['decorations']['1:39'] as List).where(
        (b) => b['key'] == 'review-v14:stone-lantern',
      ),
      hasLength(12),
    );
    for (final id in ['2:21', '2:22', '2:26']) {
      final objects = hd['decorations'][id] as List;
      expect(
        objects.where((b) => b['key'] == 'review-v14:seated-guest-bench'),
        hasLength(2),
        reason: '$id 坐客不能因修改凳子消失',
      );
      expect(
        objects
            .where(
              (b) => (b['key'] as String).startsWith('furniture:long-bench-'),
            )
            .length,
        greaterThanOrEqualTo(4),
      );
    }
  });

  testWidgets('格子底材正式加载，四象是四根独立精绘柱子', (tester) async {
    await tester.runAsync(() async {
      final art = await ModernArt.load();
      try {
        expect(art.groundOverrides['2:14']?[2 * 21 + 11], 'wall-plaster');
        for (final id in ['2:10', '2:11', '2:12', '2:13', '2:23', '2:24']) {
          final map = maps[id]!;
          final cells = map['cells'] as List;
          for (var i = 0; i < cells.length; i++) {
            if ((cells[i] as int) & 127 == 93) {
              expect(
                art.groundOverrides[id]?[i],
                'wood-cross',
                reason: '$id/$i',
              );
            }
          }
        }
        for (final name in ['dragon', 'tiger', 'bird', 'tortoise']) {
          final sprite = art.sprites['review-v11:guardian-$name/0']!;
          expect(sprite.rect.height, 256);
          expect(sprite.rect.width, 128);
        }
        expect(art.sprites, contains('review-v14:cave-stairs/0'));
      } finally {
        art.dispose();
      }
    });
  });
}

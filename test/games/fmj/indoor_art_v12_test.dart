import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bbk_flutter/games/fmj/ui/modern_art.dart';

/// 整类陈设覆盖检查：未来新增同类房间时不能再次依赖玩家逐个发现旧点阵。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final hd =
      jsonDecode(File('assets/fmj/modern/enhanced-art.json').readAsStringSync())
          as Map;

  test('26个室内地图均已查验，已知旧陈设全部有高清替代或原有高清柜体', () {
    final audit = hd['interiorReviewV12'] as Map;
    expect(audit['auditedMaps'], hasLength(26));
    expect(audit['maps'], hasLength(22));
    for (final entry in (audit['audit'] as Map).entries) {
      expect(
        entry.value['remainingPropTiles'],
        isEmpty,
        reason: '${entry.key}',
      );
    }
    final objects = hd['decorations']['2:9'] as List;
    for (final name in [
      'sealed-jar',
      'storage-sack',
      'herb-rack',
      'pottery-bowl',
    ]) {
      expect(objects.any((b) => b['key'] == 'interior-v12:$name'), isTrue);
    }
    final pharmacyJar = objects.singleWhere(
      (b) =>
          b['key'] == 'interior-v12:sealed-jar' && b['x'] == 16 && b['y'] == 6,
    );
    expect(
      pharmacyJar['cells'],
      containsAll([136, 137, 156, 157]),
      reason: '坛口和坛身四片必须一起接管，不能裁掉上半部',
    );
    expect(
      (hd['decorations']['2:18'] as List).any(
        (b) => b['key'] == 'interior-v12:weapon-rack',
      ),
      isFalse,
      reason: '药铺墙上是器物药材架，不是兵器架',
    );
    final guide =
        jsonDecode(File('assets/fmj/game/FmjGuideData.json').readAsStringSync())
            as Map;
    final maps = {for (final m in guide['maps'] as List) m['id']: m as Map};
    for (final b in (hd['decorations']['2:22'] as List).where(
      (b) => (b['key'] as String).startsWith('interior-v12:'),
    )) {
      final tiles = (b['cells'] as List).map(
        (i) => (maps['2:22']!['cells'][i] as int) & 127,
      );
      expect(
        tiles.any((tile) => {81, 82, 83}.contains(tile)),
        isFalse,
        reason: '客栈楼梯不能被新家具遮盖',
      );
    }
    for (final id in audit['maps'] as List) {
      final map = maps[id]!;
      for (final b in (hd['decorations'][id] as List).where(
        (b) => (b['key'] as String).startsWith('interior-v12:'),
      )) {
        expect(hd['frames'], contains('${b['key']}/0'));
        for (final cell in b['cells'] as List) {
          expect(cell, inInclusiveRange(0, (map['cells'] as List).length - 1));
        }
      }
    }
    expect(
      hd['frames']['furniture:hidden-passage/0'],
      hd['frames']['building:cave-mouth/0'],
    );
  });

  testWidgets('新增物件由正式图集加载，无运行时临时图或空引用', (tester) async {
    await tester.runAsync(() async {
      final art = await ModernArt.load();
      try {
        for (final name in [
          'sealed-jar',
          'storage-sack',
          'herb-pot',
          'pottery-bowl',
          'herb-rack',
          'kitchen-counter',
          'vase-stand',
          'weapon-rack',
          'round-stool',
          'bronze-scale',
          'counter-top',
          'counter-front',
          'counter-side',
        ]) {
          expect(art.sprites, contains('interior-v12:$name/0'));
        }
        expect(
          art.tileOverrides['2:9']?[4]?.$3,
          'interior-v12:counter-front/0',
        );
      } finally {
        art.dispose();
      }
    });
  });
}

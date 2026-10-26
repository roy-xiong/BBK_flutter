import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bbk_flutter/games/fmj/ui/modern_terrain.dart';

/// 使用原地图物件编号锁定此次用户反馈，避免只检查资源文件存在。
void main() {
  final hd =
      jsonDecode(File('assets/fmj/modern/enhanced-art.json').readAsStringSync())
          as Map;
  final guide =
      jsonDecode(File('assets/fmj/game/FmjGuideData.json').readAsStringSync())
          as Map;
  final maps = {for (final m in guide['maps'] as List) m['id']: m as Map};

  test('末章暗道四片完整归属独立入口，普通无机阁没有额外暗道', () {
    final doors = (hd['decorations']['2:8'] as List)
        .where((b) => b['key'] == 'furniture:hidden-passage')
        .toList();
    expect(doors, hasLength(1));
    final door = doors.single as Map;
    expect(
      [door['x'], door['y'], door['width'], door['height']],
      [13, 1, 2, 2],
    );
    final map = maps['2:8']!;
    expect((door['cells'] as List).map((i) => (map['cells'][i] as int) & 127), [
      76,
      77,
      78,
      79,
    ]);
    expect(
      (hd['decorations']['2:7'] as List).where(
        (b) => b['key'] == 'furniture:hidden-passage',
      ),
      isEmpty,
    );
    expect(hd['frames'], contains('furniture:hidden-passage/0'));
  });

  test('小客栈原内嵌掌柜、三座酒缸和三张餐桌均使用完整形象', () {
    final objects = hd['decorations']['2:26'] as List;
    expect(
      objects.where(
        (b) => (b['key'] as String).startsWith('world:archetype:merchant:'),
      ),
      hasLength(1),
    );
    expect(objects.where((b) => b['key'] == 'furniture:jars'), hasLength(3));
    expect(
      objects.where(
        (b) => (b['key'] as String).startsWith('furniture:inn-table-'),
      ),
      hasLength(3),
    );
    final clerk = objects.singleWhere(
      (b) => (b['key'] as String).startsWith('world:archetype:merchant:'),
    );
    final original = maps['2:26']!['cells'][clerk['cells'].single] as int;
    expect(original & 127, 62);
  });

  test('鹤鸣山洞口所有枯树片有物件归属，脚下不再铺云气或石栏', () {
    final map = maps['1:46']!, width = maps['1:46']!['width'] as int;
    final buildings = [
      ...hd['buildings']['1:46'] as List,
      ...hd['decorations']['1:46'] as List,
    ];
    final trees = buildings.where((b) => b['key'] == 'plant:dead-tree');
    final owned = {for (final b in trees) ...b['cells'] as List};
    for (var i = 0; i < (map['cells'] as List).length; i++) {
      final tile = (map['cells'][i] as int) & 127;
      if (tile >= 103 && tile <= 109) {
        expect(
          owned,
          contains(i),
          reason: '枯树片$tile ${i % width},${i ~/ width}',
        );
        expect(ModernTerrain.sceneMaterial(2, tile, false), 'earth');
      }
    }
    final cave = buildings.where((b) => b['key'] == 'building:cave-mouth');
    expect(cave, hasLength(1));
    expect(ModernTerrain.sceneMaterial(2, 90, false), 'mountain-wall');
  });

  test('酆都每栋三格房屋覆盖完整立面，四柱、金斗和山门都有新版切片', () {
    final houses = (hd['buildings']['1:43'] as List).where(
      (b) => b['key'] == 'building:house',
    );
    expect(houses, isNotEmpty);
    for (final house in houses) {
      expect(house['cells'], hasLength(9));
    }
    for (final key in [
      'mechanism:40/0',
      'mechanism:41/0',
      'mechanism:gate:2/0',
    ]) {
      final frame = hd['frames'][key] as List;
      expect(frame[3], greaterThan(250), reason: key);
      expect(frame[4], greaterThan(300), reason: key);
    }
  });
}

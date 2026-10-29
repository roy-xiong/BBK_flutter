import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bbk_flutter/games/fmj/ui/modern_art.dart';

/// 锁定用户选回的24个旧帧；四向走路必须各有迈步帧，不能再复用同一站姿。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final expected =
      jsonDecode(
            File(
              'test/games/fmj/fixtures/hero_rollback_v13.json',
            ).readAsStringSync(),
          )
          as Map;

  test('柳清风恢复调整前的地图迈步和战斗帧', () {
    final hd =
        jsonDecode(
              File('assets/fmj/modern/enhanced-art.json').readAsStringSync(),
            )
            as Map;
    final frames = hd['frames'] as Map;
    expect((expected['frames'] as Map).length, 24);
    for (final e in (expected['frames'] as Map).entries) {
      expect(frames[e.key], e.value['frame'], reason: '${e.key} 恢复旧帧');
    }
    for (var direction = 1; direction <= 4; direction++) {
      final poses = {
        for (var phase = 0; phase < 3; phase++)
          jsonEncode(frames['world:hero:1:$direction/$phase']),
      };
      expect(poses, hasLength(3), reason: '方向 $direction 的站姿和左右迈步不能相同');
    }
  });

  testWidgets('旧帧可从正式图集加载，无悬空图片引用', (tester) async {
    await tester.runAsync(() async {
      final art = await ModernArt.load();
      try {
        for (final e in (expected['frames'] as Map).entries) {
          final frame = e.value['frame'] as List;
          final sprite = art.sprites[e.key];
          expect(sprite, isNotNull, reason: '${e.key}');
          expect(sprite!.rect.width, frame[3]);
          expect(sprite.rect.height, frame[4]);
        }
      } finally {
        art.dispose();
      }
    });
  });
}

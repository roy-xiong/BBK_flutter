import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bbk_flutter/games/fmj/ui/modern_art.dart';

/// 地图迈步和战斗站姿沿用旧版，蓄力及横斩攻击保留新版，不能整组误覆盖。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final expected =
      jsonDecode(
            File(
              'test/games/fmj/fixtures/hero_rollback_v13.json',
            ).readAsStringSync(),
          )
          as Map;

  test('柳清风保留旧版地图迈步和战斗站姿，仅攻击使用新版', () {
    final hd =
        jsonDecode(
              File('assets/fmj/modern/enhanced-art.json').readAsStringSync(),
            )
            as Map;
    final frames = hd['frames'] as Map;
    expect((expected['frames'] as Map).length, 24);
    for (final e in (expected['frames'] as Map).entries) {
      expect(frames[e.key], e.value['frame'], reason: '${e.key} 保留指定版本');
    }
    final textures = hd['textures'] as List;
    for (var phase = 0; phase < 12; phase++) {
      final frame = frames['battle:hero:1/$phase'] as List;
      expect(
        textures[frame[0]],
        phase >= 1 && phase <= 4 ? 'hero-v10.png' : isNot('hero-v10.png'),
      );
    }
    for (var direction = 1; direction <= 4; direction++) {
      final poses = {
        for (var phase = 0; phase < 3; phase++)
          jsonEncode(frames['world:hero:1:$direction/$phase']),
      };
      expect(poses, hasLength(3), reason: '方向 $direction 的站姿和左右迈步不能相同');
    }
  });

  testWidgets('指定的新旧动作均可从正式图集加载，无悬空图片引用', (tester) async {
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

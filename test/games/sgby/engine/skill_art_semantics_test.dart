import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:bbk_flutter/games/sgby/engine/rendering/cartoon_assets.dart';
import 'package:bbk_flutter/games/sgby/engine/rendering/cartoon_scene_art.dart';
import 'package:bbk_flutter/games/sgby/engine/rendering/game_art.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late CartoonAssets assets;
  setUpAll(() async {
    assets = await CartoonAssets.load();
    final font = File('/System/Library/Fonts/Hiragino Sans GB.ttc');
    if (font.existsSync()) {
      await (FontLoader('SkillArtReview')..addFont(
            Future.value(ByteData.sublistView(font.readAsBytesSync())),
          ))
          .load();
      GameArt.previewFontFamily = 'SkillArtReview';
    }
  });
  tearDownAll(() {
    assets.dispose();
    GameArt.previewFontFamily = null;
  });

  /// 直接绘制正式计策画面，取特效中心像素；排除施法者和顶部技能名，
  /// 避免仅靠文字不同就误判“不同技能已经使用不同素材”。
  Future<Uint8List> render(int resource, String label) async {
    const scale = 3, width = 130 * scale;
    final recorder = ui.PictureRecorder(), canvas = ui.Canvas(recorder);
    canvas.scale(scale.toDouble());
    CartoonSceneArt(GameArt(canvas, assets: assets)).movie((
      resource: resource,
      first: 0,
      last: 10,
      frame: 5,
      x: 0,
      y: 0,
      label: label,
      // 与BattleFlow._skillAnimation一致：通用计策不携带普攻的兵种标记。
      sourceType: null,
      targetType: null,
      sourceFriendly: true,
      targetFriendly: false,
      effect: 'skill',
    ), const ui.Rect.fromLTWH(0, 0, 130, 64));
    final picture = recorder.endRecording();
    final image = await picture.toImage(width, 64 * scale);
    try {
      final rgba = (await image.toByteData())!.buffer.asUint8List();
      final pixels = BytesBuilder(copy: false);
      for (var y = 18 * scale; y < 54 * scale; y++) {
        pixels.add(
          rgba.sublist(
            (y * width + 56 * scale) * 4,
            (y * width + 97 * scale) * 4,
          ),
        );
      }
      final output = Platform.environment['SGBY_ART_OUTPUT'];
      if (output != null) {
        final file = File('$output/skill_semantics_${resource}_$label.png');
        file.parent.createSync(recursive: true);
        file.writeAsBytesSync(
          (await image.toByteData(
            format: ui.ImageByteFormat.png,
          ))!.buffer.asUint8List(),
        );
      }
      return pixels.takeBytes();
    } finally {
      image.dispose();
      picture.dispose();
    }
  }

  int coolPixels(Uint8List pixels) {
    var count = 0;
    for (var p = 0; p < pixels.length; p += 4) {
      if (pixels[p + 3] > 100 &&
          pixels[p + 1] > pixels[p] * 1.1 &&
          pixels[p + 2] > pixels[p] * 1.12) {
        count++;
      }
    }
    return count;
  }

  test('原版35火攻、36水攻、38撞击的真实中心像素保持正确语义', () async {
    final fire = coolPixels(await render(35, '火攻'));
    final water = coolPixels(await render(36, '水淹'));
    final impact = coolPixels(await render(38, '撞击'));
    expect(water, greaterThan(fire + 96), reason: '水攻不能被误画成橙色火焰');
    expect(impact, lessThan(water ~/ 4), reason: '撞击不能被误画成蓝色水花');
  });

  test('滚木、礌石、援兵、石阵、陷阱的实体像素各不相同', () async {
    final fingerprints = <int>{};
    for (final entry in [
      (37, '滚木'),
      (37, '礌石'),
      (41, '援兵'),
      (42, '石阵'),
      (43, '陷阱'),
    ]) {
      var hash = 2166136261;
      for (final value in await render(entry.$1, entry.$2)) {
        hash = ((hash ^ value) * 16777619) & 0xffffffff;
      }
      fingerprints.add(hash);
    }
    expect(fingerprints, hasLength(5), reason: '不能只更换名称却继续复用同一团光雾');
  });
}

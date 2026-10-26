import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:bbk_flutter/games/sgby/engine/core/original_random.dart';
import 'package:bbk_flutter/games/sgby/engine/rendering/pixel_surface.dart';
import 'package:bbk_flutter/games/sgby/engine/resources/baye_archive.dart';
import 'package:bbk_flutter/games/sgby/engine/resources/baye_picture.dart';
import 'package:bbk_flutter/games/sgby/engine/resources/gbk_codec.dart';

void main() {
  test('真实精修4X资源保留倍率槽、GBK文本和主菜单尺寸', () {
    final archive = BayeArchive(
      File('assets/sgby/game/SGBY-Reset-4X.lib').readAsBytesSync(),
    );
    expect(archive.slotCount, 116);
    expect(archive.scale, 4);
    expect(archive.resource(17), isNull);
    final menu = archive.item(44);
    expect(menu, isNotNull);
    final group = BayePictureGroup.decode(menu!);
    expect(group.width, 636);
    expect(group.height, 384);
    expect(group.count, 1);
    expect(archive.item(58, 39), isNull);
    expect(archive.item(58, 0), isNull);
  });

  test('截断的归档与图片数据应明确报错', () {
    expect(() => BayeArchive(Uint8List(3)), throwsFormatException);
    expect(() => BayePictureGroup.decode(Uint8List(6)), throwsFormatException);
    expect(
      () => BayePictureGroup.decode(
        Uint8List.fromList([9, 0, 1, 0, 1, 0, 0, 128]),
      ),
      throwsFormatException,
    );
  });

  test('非8倍数宽度按行对齐，遮罩保持与清除不混用', () {
    final group = BayePictureGroup.decode(
      Uint8List.fromList([
        3, 0, 1, 0, 1, 0, 0x11, // 3×1，最低位为 mask，高位不改变平面数量。
        0xa0, // mask: 保留、清除、保留。
        0x20, // data: 背景、背景、前景。
      ]),
    );
    final surface = PixelSurface(width: 3, height: 1)..clear(100);
    surface.blit(group.picture(0)!, 0, 0);
    expect(surface.snapshot(), [100, 0, 255]);
    surface.clear(200);
    surface.blit(group.picture(0)!, 0, 0, color: 128);
    expect(surface.snapshot(), [200, 0, 128]);
    surface.clear(100);
    surface.blit(group.picture(0)!, 0, 0);
    surface.reverse(-3, -3, 5, 5);
    surface.reverse(-3, -3, 5, 5);
    expect(surface.snapshot(), [100, 0, 255]);
    final snapshot = surface.snapshot();
    surface.clear();
    expect(snapshot, [100, 0, 255]);
  });

  test('精修4X全部56组图形与动画均可完整解码', () {
    final archive = BayeArchive(
      File('assets/sgby/game/SGBY-Reset-4X.lib').readAsBytesSync(),
    );
    const staticIds = [
      4,
      5,
      7,
      8,
      9,
      15,
      16,
      26,
      28,
      29,
      30,
      31,
      32,
      33,
      34,
      44,
      45,
      46,
      47,
      48,
      49,
      50,
      51,
      54,
      55,
      56,
      69,
      75,
      76,
    ];
    const animationIds = [
      3,
      6,
      19,
      20,
      21,
      22,
      23,
      24,
      25,
      27,
      35,
      36,
      37,
      38,
      39,
      40,
      41,
      42,
      43,
      100,
      101,
      102,
      103,
      104,
      105,
      106,
      107,
    ];
    var pictures = 0;
    for (final id in staticIds) {
      final bytes = archive.item(id)!;
      final group = BayePictureGroup.decode(bytes);
      expect(group.byteLength, bytes.length, reason: '静态资源 $id');
      pictures += group.count;
    }
    for (final id in animationIds) {
      pictures += BayeAnimation.decode(archive.item(id)!).pictures.length;
    }
    expect(staticIds.length + animationIds.length, 56);
    expect(pictures, 1202);
  });

  test('扩展GBK表头经解码和再编码仍保留原内码，半个字符安全截断', () {
    final codec = GbkCodec(
      File('assets/sgby/game/gbk_unicode.bin').readAsBytesSync(),
    );
    final bytes = <int>[0xa2, 0xfd, 0xa2, 0xfe, 65];
    expect(codec.encode(codec.decode(bytes)), bytes);
    expect(codec.decode([0xa2]), '\ufffd');
  });

  test('随机源保留已记录的旧WASM返回序列和独立种子状态', () {
    final random = OriginalRandom(1);
    expect(
      [random.next(), random.next(), random.next(), random.next()],
      [1993684161, 1388323688, 65314989, 717128328],
    );
    final restored = OriginalRandom(random.state);
    expect(restored.next(), random.next());
    expect(restored.state, random.state);
  });
}

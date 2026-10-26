import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:bbk_flutter/games/sgby/data/repositories/game_save_repository.dart';
import 'package:bbk_flutter/games/sgby/engine/resources/baye_archive.dart';
import 'package:bbk_flutter/games/sgby/engine/resources/baye_database.dart';
import 'package:bbk_flutter/games/sgby/engine/resources/bitmap_font.dart';
import 'package:bbk_flutter/games/sgby/engine/resources/gbk_codec.dart';

void main() {
  late Directory directory;
  late GameSaveRepository repository;
  late BayeDatabase database;
  setUpAll(() {
    database = BayeDatabase(
      archive: BayeArchive(
        File('assets/sgby/game/SGBY-Reset-4X.lib').readAsBytesSync(),
      ),
      codec: GbkCodec(
        File('assets/sgby/game/gbk_unicode.bin').readAsBytesSync(),
      ),
      font: BitmapFont(
        File('assets/sgby/game/fallback_font12.bin').readAsBytesSync(),
      ),
      refinedRules:
          jsonDecode(
                File('assets/sgby/game/refined_rules.json').readAsStringSync(),
              )
              as Map<String, dynamic>,
    );
  });
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('sgby-native-save-');
    repository = GameSaveRepository(directoryProvider: () async => directory);
  });
  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test('重叠存储保存调用时快照，主文件损坏后能恢复前一个有效进度', () async {
    final world = database.loadPeriod(1, seed: 1);
    database.beginGame(world, 5);
    final original = world.person(0)!.force;
    final first = repository.save(0, world);
    world.setPerson(0, world.person(0)!.copyWith(force: original + 1));
    final second = repository.save(0, world);
    await Future.wait([first, second]);
    expect((await repository.load(0))?.person(0)?.force, original + 1);
    await File(
      '${directory.path}/games/sgby/slot_0.json',
    ).writeAsString('{broken');
    expect((await repository.load(0))?.person(0)?.force, original);
    // 救援后保存新进度，损坏的旧主文件不能覆盖有效备份。
    await repository.save(0, world);
    await File(
      '${directory.path}/games/sgby/slot_0.json',
    ).writeAsString('null');
    expect((await repository.load(0))?.person(0)?.force, original);
  });

  test('偏好文件先恢复备份，两份都损坏时回到默认值且不阻止启动', () async {
    await repository.saveSettings({'controlsVisible': false});
    await repository.saveSettings({'controlsVisible': true});
    final file = File('${directory.path}/games/sgby/settings.json');
    await file.writeAsString('{broken');
    expect((await repository.loadSettings())['controlsVisible'], false);
    await File('${file.path}.backup').writeAsString('invalid');
    expect(await repository.loadSettings(), isEmpty);
  });

  test('第四读取档位可独立恢复，首次目录读取失败不会阻塞后续写入', () async {
    var attempts = 0;
    final retry = GameSaveRepository(
      directoryProvider: () {
        attempts++;
        if (attempts == 1) throw const FileSystemException('模拟暂时不可用');
        return Future.value(directory);
      },
    );
    await expectLater(
      retry.saveSettings({'ready': false}),
      throwsA(isA<FileSystemException>()),
    );
    await retry.saveSettings({'ready': true});
    expect((await retry.loadSettings())['ready'], true);
    final world = database.loadPeriod(4, seed: 42);
    database.beginGame(world, database.rulers(world).first);
    await retry.save(3, world);
    expect((await retry.load(3))?.period, 4);
    await expectLater(retry.load(4), throwsRangeError);
  });
}

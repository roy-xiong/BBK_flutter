import 'package:flutter_test/flutter_test.dart';
import 'package:bbk_flutter/games/sgby/data/repositories/game_asset_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('真实Flutter资产入口和isolate解析能取得4X资源及Android参考字模', () async {
    final database = await GameAssetRepository().load();
    expect(database.scale, 4);
    expect(database.font.usesAndroidReference, isTrue);
    final world = database.loadPeriod(4, seed: 1);
    expect(world.persons.length, 200);
    expect(world.cities.length, 38);
  });
}

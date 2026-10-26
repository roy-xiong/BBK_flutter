import 'package:flutter_test/flutter_test.dart';
import 'package:bbk_flutter/games/sgby/domain/use_cases/build_general_roster.dart';
import 'package:bbk_flutter/games/sgby/engine/resources/person_names.dart';

import '../support/game_database.dart';

void main() {
  test('四时期人物编号不变，黑白绘字和彩色查询共用勘误姓名且GBK不丢字', () {
    final database = loadGameDatabase();
    final seen = <String>{};
    for (var period = 1; period <= 4; period++) {
      final world = database.loadPeriod(period);
      database.beginGame(world, database.rulers(world).first);
      final roster = BuildGeneralRoster(database)(world).generals;
      for (var id = 0; id < world.persons.length; id++) {
        final original = database
            .text(const [62, 70, 71, 72][period - 1], id + 1)
            .trimRight();
        final expected = PersonNames.corrections[original] ?? original;
        expect(database.personName(period, id), expected);
        expect(
          database.codec.decode(database.codec.encode(expected)),
          expected,
        );
        final entry = roster.where((value) => value.index == id).firstOrNull;
        if (entry != null) expect(entry.name, expected);
        if (PersonNames.corrections.containsKey(original)) seen.add(original);
      }
    }
    expect(seen, PersonNames.corrections.keys.toSet());
    for (final name in ['孙尚香', '曹叡', '泠苞']) {
      expect(PersonNames.correct(name), name);
    }
  });
}

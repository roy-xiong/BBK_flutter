import 'package:bbk_flutter/games/sgby/ui/features/game/view_models/game_view_model.dart';
import 'package:bbk_flutter/games/sgby/ui/features/game/views/game_general_roster_sheet.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('精确搜索敌方君主姓名时置顶君主并保留同势力将领', () {
    final generals = <SgbyGeneralCheatInfo>[
      _general(index: 1, name: '夏侯惇', factionName: '曹操'),
      _general(index: 0, name: '曹操', factionName: '曹操', isRuler: true),
      _general(index: 2, name: '荀彧', factionName: '曹操'),
    ];

    final result = filterSgbyGeneralRoster(
      generals,
      SgbyGeneralGroup.enemy,
      '曹操',
    );

    expect(result.map((general) => general.name), <String>['曹操', '夏侯惇', '荀彧']);
  });

  test('没有精确姓名命中时仍可按势力搜索', () {
    final generals = <SgbyGeneralCheatInfo>[
      _general(index: 0, name: '曹操', factionName: '魏'),
      _general(index: 1, name: '夏侯惇', factionName: '魏'),
      _general(index: 2, name: '刘备', factionName: '蜀'),
    ];

    final result = filterSgbyGeneralRoster(
      generals,
      SgbyGeneralGroup.enemy,
      '魏',
    );

    expect(result.map((general) => general.name), <String>['曹操', '夏侯惇']);
  });

  test('独立君主结果显示所在地城池', () {
    final ruler = _general(
      index: 0,
      name: '曹操',
      factionName: '曹操',
      isRuler: true,
    );

    expect(formatSgbyGeneralLocation(ruler), '所在地：许昌');
  });
}

SgbyGeneralCheatInfo _general({
  required int index,
  required String name,
  required String factionName,
  bool isRuler = false,
}) {
  return SgbyGeneralCheatInfo.fromJson(<String, dynamic>{
    'index': index,
    'name': name,
    'group': 'enemy',
    'factionName': factionName,
    'cityName': '许昌',
    'isRuler': isRuler,
  });
}

import 'dart:collection';

import '../../engine/core/original_random.dart';
import 'game_city.dart';
import 'game_order.dart';
import 'game_person.dart';
import 'game_tool.dart';
import 'battle_record.dart';
import 'hidden_general_backup.dart';

/// 一局游戏的数据所有者，统一保存人物、城池、订单与原版顺序队列。
///
/// 本对象仅由游戏会话所在 isolate 修改，界面通过只读集合读取不可变记录。
/// 在野武将、俘虏和未来出场武将均保留原数据，不通过归属重新生成城市队列。
final class GameWorld {
  GameWorld({
    required this.period,
    required this.year,
    required this.month,
    required List<GamePerson> persons,
    required List<GameCity> cities,
    required List<GameTool> tools,
    required List<int> personQueue,
    required List<int> goodsQueue,
    required int randomSeed,
  }) : _persons = List.of(persons),
       _cities = List.of(cities),
       _tools = List.of(tools),
       _personQueue = List.of(personQueue),
       _goodsQueue = List.of(goodsQueue),
       random = OriginalRandom(randomSeed) {
    if (period < 1 ||
        period > 4 ||
        month < 1 ||
        month > 12 ||
        _persons.isEmpty ||
        _cities.isEmpty ||
        _personQueue.length != _persons.length) {
      throw const FormatException('时期、日期或人物队列无效');
    }
    for (final city in _cities) {
      if (city.personQueue < 0 ||
          city.persons < 0 ||
          city.toolQueue < 0 ||
          city.tools < 0 ||
          city.personQueue + city.persons > _personQueue.length ||
          city.toolQueue + city.tools > _goodsQueue.length) {
        throw const FormatException('城池中的人物或道具队列越界');
      }
    }
    for (final person in _personQueue) {
      if (person < 0 || person >= _persons.length) {
        throw const FormatException('人物队列编号越界');
      }
    }
  }

  final int period;
  int year;
  int month;
  int? playerRulerIndex;
  int cursorX = 0;
  int cursorY = 0;
  int viewX = 0;
  int viewY = 0;

  /// 原版存档的三个战场显示参数；每局独立，读档后恢复原先设置。
  bool lookBattleMovie = true;
  bool slowBattleMovement = true;
  bool lookEnemyMovement = true;
  final OriginalRandom random;
  BattleRecord battleRecord = BattleRecord();

  /// 隐藏备份属于本局；读档整体替换世界时一并替换，避免其他档位人物被复活。
  final Map<int, HiddenGeneralBackup> hiddenGenerals = {};
  bool get hasLargeArmies => _persons.any((person) => person.arms > 65535);
  final List<GamePerson> _persons;
  final List<GameCity> _cities;
  final List<GameTool> _tools;
  final List<int> _personQueue;
  final List<int> _goodsQueue;
  final List<GameOrder> _orders = <GameOrder>[];

  List<GamePerson> get persons => UnmodifiableListView(_persons);
  List<GameCity> get cities => UnmodifiableListView(_cities);
  List<GameTool> get tools => UnmodifiableListView(_tools);
  List<int> get personQueue => UnmodifiableListView(_personQueue);
  List<int> get goodsQueue => UnmodifiableListView(_goodsQueue);
  List<GameOrder> get orders => UnmodifiableListView(_orders);

  /// 依据原版AddGoods在城市道具队尾插入，返回队列位置；资源编号保留0基值。
  int? addTool(int cityIndex, int toolIndex, {bool discovered = false}) {
    final selected = city(cityIndex);
    if (selected == null ||
        tool(toolIndex) == null ||
        _cities.fold<int>(0, (sum, value) => sum + value.tools) >=
            _goodsQueue.length) {
      return null;
    }
    final offset = selected.toolQueue + selected.tools;
    for (var i = _goodsQueue.length - 1; i > offset; i--) {
      _goodsQueue[i] = _goodsQueue[i - 1];
    }
    _goodsQueue[offset] = toolIndex | (discovered ? 0x8000 : 0);
    _cities[cityIndex] = selected.copyWith(tools: selected.tools + 1);
    for (var i = cityIndex + 1; i < _cities.length; i++) {
      _cities[i] = _cities[i].copyWith(toolQueue: _cities[i].toolQueue + 1);
    }
    return offset;
  }

  bool removeTool(int cityIndex, int toolIndex) {
    final selected = city(cityIndex);
    if (selected == null) return false;
    var offset = -1;
    for (
      var i = selected.toolQueue;
      i < selected.toolQueue + selected.tools;
      i++
    ) {
      if ((_goodsQueue[i] & 0x7fff) == toolIndex) {
        offset = i;
        break;
      }
    }
    if (offset < 0) return false;
    for (var i = offset; i < _goodsQueue.length - 1; i++) {
      _goodsQueue[i] = _goodsQueue[i + 1];
    }
    _cities[cityIndex] = selected.copyWith(tools: selected.tools - 1);
    for (var i = cityIndex + 1; i < _cities.length; i++) {
      _cities[i] = _cities[i].copyWith(toolQueue: _cities[i].toolQueue - 1);
    }
    return true;
  }

  GamePerson? person(int index) =>
      index >= 0 && index < _persons.length ? _persons[index] : null;
  GameCity? city(int index) =>
      index >= 0 && index < _cities.length ? _cities[index] : null;
  GameTool? tool(int index) =>
      index >= 0 && index < _tools.length ? _tools[index] : null;

  /// 替换记录，不暴露可以被外部后台任务写入的数组。
  bool setPerson(int index, GamePerson value) {
    if (person(index) == null) return false;
    _persons[index] = value;
    return true;
  }

  bool setCity(int index, GameCity value) {
    if (city(index) == null) return false;
    _cities[index] = value;
    return true;
  }

  bool setTool(int index, GameTool value) {
    if (tool(index) == null) return false;
    _tools[index] = value;
    return true;
  }

  /// 队列保持原顺序；kind为空返回全部，否则按归属筛选在任、在野或俘虏。
  List<int> personsInCity(int cityIndex, {int? belong}) {
    final selected = city(cityIndex);
    if (selected == null) return const <int>[];
    final output = <int>[];
    for (
      var i = selected.personQueue;
      i < selected.personQueue + selected.persons;
      i++
    ) {
      final index = _personQueue[i];
      if (belong == null || _persons[index].belong == belong) output.add(index);
    }
    return output;
  }

  List<int> citiesOf(int rulerIndex) => <int>[
    for (var i = 0; i < _cities.length; i++)
      if (_cities[i].belong == rulerIndex + 1) i,
  ];

  /// 未在城池队列出现的人物返回空值，不能凭归属猜测落脚城池。
  int? cityOfPerson(int personIndex) {
    if (person(personIndex) == null) return null;
    for (var i = 0; i < _cities.length; i++) {
      if (personsInCity(i).contains(personIndex)) return i;
    }
    return null;
  }

  /// 对应DelPerson：删除首个匹配并左移，后续城市起点统一减一。
  bool removePerson(int cityIndex, int personIndex) {
    final selected = city(cityIndex);
    if (selected == null || person(personIndex) == null) return false;
    var offset = -1;
    for (
      var i = selected.personQueue;
      i < selected.personQueue + selected.persons;
      i++
    ) {
      if (_personQueue[i] == personIndex) {
        offset = i;
        break;
      }
    }
    if (offset < 0) return false;
    for (var i = offset; i < _personQueue.length - 1; i++) {
      _personQueue[i] = _personQueue[i + 1];
    }
    _cities[cityIndex] = selected.copyWith(persons: selected.persons - 1);
    for (var i = cityIndex + 1; i < _cities.length; i++) {
      _cities[i] = _cities[i].copyWith(personQueue: _cities[i].personQueue - 1);
    }
    return true;
  }

  /// 对应开启去重保护的AddPerson，在目标城市队首插入，不重复登记同一武将。
  bool addPerson(int cityIndex, int personIndex) {
    if (city(cityIndex) == null || person(personIndex) == null) return false;
    for (var i = 0; i < _cities.length; i++) {
      while (removePerson(i, personIndex)) {
        /* 清除历史重复登记。 */
      }
    }
    if (_cities.fold<int>(0, (sum, value) => sum + value.persons) >=
        _personQueue.length) {
      return false;
    }
    final selected = _cities[cityIndex];
    for (var i = _personQueue.length - 1; i > selected.personQueue; i--) {
      _personQueue[i] = _personQueue[i - 1];
    }
    _personQueue[selected.personQueue] = personIndex;
    _cities[cityIndex] = selected.copyWith(persons: selected.persons + 1);
    for (var i = cityIndex + 1; i < _cities.length; i++) {
      _cities[i] = _cities[i].copyWith(personQueue: _cities[i].personQueue + 1);
    }
    return true;
  }

  /// 道具原值的0x8000表示已发现，编号为低15位，不能把二者混在一起索引。
  List<int> goodsInCity(int cityIndex, {bool discoveredOnly = false}) {
    final selected = city(cityIndex);
    if (selected == null) return const <int>[];
    return <int>[
      for (
        var i = selected.toolQueue;
        i < selected.toolQueue + selected.tools;
        i++
      )
        if (!discoveredOnly || (_goodsQueue[i] & 0x8000) != 0) _goodsQueue[i],
    ];
  }

  /// 修改已存在的道具发现标志，保持城市队列及其他档位不变。
  bool discoverTool(int cityIndex, int toolIndex) {
    final selected = city(cityIndex);
    if (selected == null || tool(toolIndex) == null) return false;
    for (
      var i = selected.toolQueue;
      i < selected.toolQueue + selected.tools;
      i++
    ) {
      if ((_goodsQueue[i] & 0x7fff) == toolIndex) {
        _goodsQueue[i] |= 0x8000;
        return true;
      }
    }
    return false;
  }

  /// 订单容量与旧内核一致。插入失败不应继续扣减人物和城市资源。
  bool addOrder(GameOrder order, {bool atEnd = false}) {
    final used = _orders.map((value) => value.queueSlot).toSet();
    for (var slot = atEnd ? 170 : 0; slot < 200; slot++) {
      if (used.contains(slot)) continue;
      _orders.add(order.copyWith(queueSlot: slot));
      _orders.sort((a, b) => a.queueSlot!.compareTo(b.queueSlot!));
      return true;
    }
    return false;
  }

  /// 先保留出征槽和命令槽，再提交武将队列；失败时调用方不能扣除人物。
  bool addFightOrder(GameOrder order, List<int> fighters) {
    if (fighters.isEmpty ||
        fighters.length > 10 ||
        fighters.any((id) => person(id) == null) ||
        fighters.toSet().length != fighters.length) {
      return false;
    }
    final used = _orders
        .where((value) => value.orderId == 27)
        .map((value) => value.person)
        .toSet();
    for (var index = 0; index < 30; index++) {
      if (used.contains(index)) continue;
      return addOrder(
        order.copyWith(orderId: 27, person: index, fighters: fighters),
        atEnd: true,
      );
    }
    return false;
  }

  void removeOrder(GameOrder order) =>
      _orders.removeWhere((value) => value.queueSlot == order.queueSlot);

  void replaceOrders(Iterable<GameOrder> values) {
    final replacement = values.toList(growable: false);
    if (replacement.length > 200) throw const FormatException('订单数量超过上限');
    final slots = <int>{};
    for (var index = 0; index < replacement.length; index++) {
      final slot = replacement[index].queueSlot ?? index;
      if (slot < 0 || slot >= 200 || !slots.add(slot)) {
        throw const FormatException('订单槽位重复或越界');
      }
      replacement[index] = replacement[index].copyWith(queueSlot: slot);
    }
    replacement.sort((a, b) => a.queueSlot!.compareTo(b.queueSlot!));
    _orders
      ..clear()
      ..addAll(replacement);
  }

  /// 返回深层可序列化快照；记录和值列表均不与后续游戏推进共享可变元素。
  Map<String, Object?> toJson() => <String, Object?>{
    'period': period,
    'year': year,
    'month': month,
    'playerRulerIndex': playerRulerIndex,
    'randomSeed': random.state,
    'cursorX': cursorX,
    'cursorY': cursorY,
    'viewX': viewX,
    'viewY': viewY,
    'lookBattleMovie': lookBattleMovie,
    'slowBattleMovement': slowBattleMovement,
    'lookEnemyMovement': lookEnemyMovement,
    'persons': [for (final value in _persons) value.toJson()],
    'cities': [for (final value in _cities) value.toJson()],
    'tools': [for (final value in _tools) value.toJson()],
    'personQueue': List<int>.of(_personQueue),
    'goodsQueue': List<int>.of(_goodsQueue),
    'orders': [for (final value in _orders) value.toJson()],
    'battleRecord': battleRecord.toJson(),
    'hiddenGenerals': [
      for (final value in hiddenGenerals.values) value.toJson(),
    ],
  };
}

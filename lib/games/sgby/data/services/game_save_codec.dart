import '../../domain/models/game_city.dart';
import '../../domain/models/game_order.dart';
import '../../domain/models/game_person.dart';
import '../../domain/models/game_tool.dart';
import '../../domain/models/game_world.dart';
import '../../domain/models/battle_record.dart';
import '../../domain/models/game_options.dart';
import '../../domain/models/hidden_general_backup.dart';

/// 原生版本化存档编码。资源哈希绑定精修4X，损坏数据不会部分写入当前会话。
final class GameSaveCodec {
  static const int version = 2;
  static const String resourceHash =
      'a60cdf33e697bf39e26dce82e2390dbc8c0683dce06b8fee6de791ba569a7c8d';

  Map<String, Object?> encode(GameWorld world) => <String, Object?>{
    'version': version,
    'resourceHash': resourceHash,
    'world': world.toJson(),
  };

  /// 所有记录验证完成后才构造新世界；调用方可保留旧会话直到读取成功。
  GameWorld decode(Object? value) {
    final root = _map(value);
    if (!const [1, version].contains(root['version']) ||
        root['resourceHash'] != resourceHash) {
      throw const FormatException('存档版本或资源版本不匹配');
    }
    final data = _map(root['world']);
    final people = _list(data['persons']);
    final cities = _list(data['cities']);
    final tools = _list(data['tools']);
    if (people.isEmpty ||
        people.length > 2000 ||
        cities.length != 38 ||
        tools.length > 2000) {
      throw const FormatException('存档记录数量无效');
    }
    final world = GameWorld(
      period: _int(data['period'], 4),
      year: _int(data['year'], 65535),
      month: _int(data['month'], 12),
      persons: people.map((value) => _person(_map(value))).toList(),
      cities: cities.map((value) => _city(_map(value))).toList(),
      tools: tools.map((value) => _tool(_map(value))).toList(),
      personQueue: _list(
        data['personQueue'],
      ).map((value) => _int(value, 65535)).toList(),
      goodsQueue: _list(
        data['goodsQueue'],
      ).map((value) => _int(value, 65535)).toList(),
      randomSeed: _int(data['randomSeed'], 0xffffffff),
    );
    final ruler = data['playerRulerIndex'];
    world.playerRulerIndex = ruler == null
        ? null
        : _int(ruler, people.length - 1);
    world.cursorX = _int(data['cursorX'], 11);
    world.cursorY = _int(data['cursorY'], 8);
    world.viewX = _int(data['viewX'], 11);
    world.viewY = _int(data['viewY'], 8);
    world.lookBattleMovie = _boolean(data['lookBattleMovie']);
    world.slowBattleMovement = _boolean(data['slowBattleMovement']);
    world.lookEnemyMovement = _boolean(data['lookEnemyMovement']);
    world.battleRecord = BattleRecord.decode(data['battleRecord']);
    world.replaceOrders(
      _list(data['orders']).map((value) => _order(_map(value))),
    );
    // 数值宽度正确并不代表引用有效；在替换活动会话前一次性检查跨表编号。
    for (final person in world.persons) {
      if ((person.belong != 65535 && person.belong > people.length) ||
          (person.oldBelong != 65535 && person.oldBelong > people.length) ||
          person.armsType > 5 ||
          person.equip0 > tools.length ||
          person.equip1 > tools.length) {
        throw const FormatException('武将归属、装备或兵种无效');
      }
    }
    for (final city in world.cities) {
      if (city.belong > people.length || city.satrapId > people.length) {
        throw const FormatException('城池归属或城主无效');
      }
    }
    for (final value in world.goodsQueue) {
      if ((value & 32767) >= tools.length) {
        throw const FormatException('道具队列编号越界');
      }
    }
    for (final order in world.orders) {
      if (order.orderId < 1 ||
          order.orderId > 27 ||
          order.city >= cities.length ||
          order.person >= (order.orderId == 27 ? 30 : people.length) ||
          order.fighters.length > 10 ||
          order.fighters.any((id) => id >= people.length)) {
        throw const FormatException('订单或出征武将编号无效');
      }
    }
    final hidden = data['hiddenGenerals'];
    if (hidden != null) {
      final records = _list(hidden);
      if (records.length > 2) throw const FormatException('特殊武将备份过多');
      // 编号与固定精修资源哈希绑定；拒绝利用损坏备份恢复普通或在任武将。
      final allowed = const [
        [185, 186],
        [183, 184],
        [187, 188],
        [174, 175],
      ][world.period - 1];
      for (final value in records) {
        final item = _map(value), id = _int(item['index'], people.length - 1);
        final city = item['city'] == null
            ? null
            : _int(item['city'], cities.length - 1);
        final backup = HiddenGeneralBackup(
          index: id,
          belong: _int(item['belong'], 65535),
          oldBelong: _int(item['oldBelong'], 65535),
          arms: _int(item['arms'], GameOptions.maximumPersonArms),
          city: city,
        );
        if (!allowed.contains(id) ||
            backup.belong != 65535 && backup.belong > people.length ||
            world.hiddenGenerals.containsKey(id) ||
            world.person(id)?.belong != 65535 ||
            world.cityOfPerson(id) != null ||
            world.orders.any(
              (o) => o.orderId == 27 ? o.fighters.contains(id) : o.person == id,
            )) {
          throw const FormatException('特殊武将备份与当前局面不一致');
        }
        world.hiddenGenerals[id] = backup;
      }
    }
    return world;
  }

  bool _boolean(Object? value) {
    if (value == null) return true; // 兼容未保存显示参数的早期原生存档。
    if (value is! bool) throw const FormatException('战场显示参数无效');
    return value;
  }

  Map<String, dynamic> _map(Object? value) {
    if (value is! Map<String, dynamic>) throw const FormatException('存档对象格式无效');
    return value;
  }

  List<dynamic> _list(Object? value) {
    if (value is! List) throw const FormatException('存档数组格式无效');
    return value;
  }

  int _int(Object? value, int maximum) {
    if (value is! num ||
        !value.isFinite ||
        value != value.toInt() ||
        value < 0 ||
        value > maximum) {
      throw const FormatException('存档数字越界');
    }
    return value.toInt();
  }

  GamePerson _person(Map<String, dynamic> value) {
    final equipment = _list(value['Equip']);
    if (equipment.length != 2) throw const FormatException('装备记录长度无效');
    return GamePerson(
      oldBelong: _int(value['OldBelong'], 65535),
      belong: _int(value['Belong'], 65535),
      level: _int(value['Level'], 255),
      force: _int(value['Force'], 255),
      iq: _int(value['IQ'], 255),
      devotion: _int(value['Devotion'], 255),
      character: _int(value['Character'], 255),
      experience: _int(value['Experience'], 255),
      thew: _int(value['Thew'], 255),
      armsType: _int(value['ArmsType'], 255),
      arms: _int(value['Arms'], GameOptions.maximumPersonArms),
      age: _int(value['Age'], 255),
      equip0: _int(equipment[0], 65535),
      equip1: _int(equipment[1], 65535),
    );
  }

  GameCity _city(Map<String, dynamic> value) {
    return GameCity(
      state: _int(value['State'], 255),
      belong: _int(value['Belong'], 65535),
      satrapId: _int(value['SatrapId'], 65535),
      farmingLimit: _int(value['FarmingLimit'], 65535),
      farming: _int(value['Farming'], 65535),
      commerceLimit: _int(value['CommerceLimit'], 65535),
      commerce: _int(value['Commerce'], 65535),
      peopleDevotion: _int(value['PeopleDevotion'], 255),
      avoidCalamity: _int(value['AvoidCalamity'], 255),
      populationLimit: _int(value['PopulationLimit'], 4294967295),
      population: _int(value['Population'], 4294967295),
      money: _int(value['Money'], 65535),
      food: _int(value['Food'], 65535),
      mothballArms: _int(value['MothballArms'], 65535),
      personQueue: _int(value['PersonQueue'], 65535),
      persons: _int(value['Persons'], 65535),
      toolQueue: _int(value['ToolQueue'], 65535),
      tools: _int(value['Tools'], 65535),
    );
  }

  GameTool _tool(Map<String, dynamic> value) {
    return GameTool(
      useFlag: _int(value['useflag'], 255),
      attack: _int(value['at'], 255),
      iq: _int(value['iq'], 255),
      move: _int(value['move'], 255),
      arm: _int(value['arm'], 255),
    );
  }

  GameOrder _order(Map<String, dynamic> value) {
    return GameOrder(
      orderId: _int(value['OrderId'], 255),
      person: _int(value['Person'], 65535),
      city: _int(value['City'], 255),
      object: _int(value['Object'], 65535),
      arms: _int(value['Arms'], 65535),
      food: _int(value['Food'], 65535),
      money: _int(value['Money'], 65535),
      consume: _int(value['Consume'], 255),
      timeCount: _int(value['TimeCount'], 255),
      queueSlot: value['queueSlot'] == null
          ? null
          : _int(value['queueSlot'], 199),
      fighters: value['fighters'] == null
          ? const <int>[]
          : _list(
              value['fighters'],
            ).map((id) => _int(id, 1999)).toList(growable: false),
    );
  }
}

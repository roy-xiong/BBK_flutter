import 'dart:typed_data';

import '../../domain/models/game_city.dart';
import '../../domain/models/game_person.dart';
import '../../domain/models/game_tool.dart';
import '../../domain/models/game_world.dart';
import 'baye_archive.dart';
import 'baye_picture.dart';
import 'bitmap_font.dart';
import 'gbk_codec.dart';
import 'person_names.dart';

/// 固定资源库、精修参数和领域模型之间的唯一映射。
///
/// 二进制结构遵循旧内核loadCity/loadPerson的逐字段读法，不使用平台结构体
/// 对齐。精修脚本的开局属性调整已转换为固定数据，运行时不执行JavaScript。
final class BayeDatabase {
  BayeDatabase({
    required this.archive,
    required this.codec,
    required this.font,
    required Map<String, dynamic> refinedRules,
  }) : _rules = refinedRules {
    if (archive.scale != 4) throw const FormatException('此工程需要精修4X资源');
    if (_rules['config'] is! Map ||
        _rules['personOverrides'] is! List ||
        (_rules['personOverrides'] as List).length != 4) {
      throw const FormatException('精修配置缺少必要字段');
    }
    for (final id in [
      1,
      2,
      3,
      6,
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
      57,
      58,
      61,
      62,
      63,
      64,
      65,
      66,
      68,
      69,
      70,
      71,
      72,
      73,
      75,
      100,
      101,
      102,
      103,
      104,
      105,
      106,
      107,
    ]) {
      requiredItem(id);
    }
    for (final id in [37, 38, 39, 40, 121]) {
      if (text(64, id).isEmpty) throw FormatException('菜单文本缺失：$id');
    }
    if (constant(6).length < 76 || constant(14).length < mapWidth * mapHeight) {
      throw const FormatException('地图坐标或城池数据不完整');
    }
  }

  final BayeArchive archive;
  final GbkCodec codec;
  final BitmapFont font;
  final Map<String, dynamic> _rules;
  final Map<int, BayePictureGroup> _pictures = <int, BayePictureGroup>{};
  final Map<int, BayeAnimation> _animations = <int, BayeAnimation>{};
  final Map<(int, int), String> _strings = <(int, int), String>{};
  final Map<int, Uint8List> _constants = <int, Uint8List>{};
  late final List<int> displayPalette = _displayPalette();

  /// 对照旧内核调色板与CSS的#b4b4b4背景，预先合成256个显示颜色。
  ///
  /// 将Alpha处理放在颜色表构建阶段，不在每帧55万像素上重复做透明度除法。
  /// 帧上传为不透明RGBA，也避免Flutter原始图片接口的预乘Alpha差异。
  List<int> _displayPalette() {
    final source = _rules['palette'];
    if (source is! List || source.length != 256) {
      throw const FormatException('精修调色板不完整');
    }
    return List<int>.unmodifiable(
      source.map((value) {
        if (value is! num) throw const FormatException('精修调色板颜色无效');
        final word = value.toInt() & 0xffffffff;
        final alpha = (word >> 24) & 255;
        int blend(int channel) =>
            (channel * alpha + 180 * (255 - alpha) + 127) ~/ 255;
        final red = blend(word & 255);
        final green = blend((word >> 8) & 255);
        final blue = blend((word >> 16) & 255);
        return 0xff000000 | red | (green << 8) | (blue << 16);
      }),
    );
  }

  int get logicalWidth => 240;
  int get logicalHeight => 144;
  int get scale => archive.scale;
  int get mapWidth => rule('cityMapWidth', 12);
  int get mapHeight => rule('cityMapHeight', 9);

  /// 策略阶段开始前重选太守：君主优先，其余按城内同势力武将最高智力。
  void assignSatraps(GameWorld world) {
    for (var i = 0; i < world.cities.length; i++) {
      final city = world.cities[i];
      var selected = 0;
      if (city.belong != 0) {
        for (final id in world.personsInCity(i, belong: city.belong)) {
          if (city.belong == id + 1) {
            selected = id + 1;
            break;
          }
          if (selected == 0 ||
              (world.person(selected - 1)?.iq ?? 0) <
                  (world.person(id)?.iq ?? 0)) {
            selected = id + 1;
          }
        }
      }
      world.setCity(i, city.copyWith(satrapId: selected));
    }
  }

  int rule(String key, [int fallback = 0]) {
    final value = (_rules['config'] as Map)[key];
    return value is num ? value.toInt() : fallback;
  }

  List<int> ruleArray(String key) {
    final value = (_rules['config'] as Map)[key];
    return value is List
        ? value.whereType<num>().map((e) => e.toInt()).toList(growable: false)
        : const <int>[];
  }

  Uint8List requiredItem(int resource, [int index = 1]) {
    final data = archive.item(resource, index);
    if (data == null) throw FormatException('缺少资源 $resource/$index');
    return data;
  }

  /// 原版接口常量资源2。返回只读字节，避免调用方改写地图或兵种规则。
  Uint8List constant(int index) => _constants.putIfAbsent(
    index,
    () => (archive.item(2, index) ?? _defaultConstant(index))
        .asUnmodifiableView(),
  );

  /// 老LIB仅含前16项。ResItemGetN读取不到新增项时保留C静态默认表。
  Uint8List _defaultConstant(int index) {
    if (index == 17) return Uint8List.fromList([5, 4, 4, 5, 6, 3]);
    final values = switch (index) {
      18 => <double>[
        1,
        1.2,
        .8,
        1,
        .7,
        1.3,
        .8,
        1,
        1.2,
        1,
        .6,
        1.2,
        1.2,
        .8,
        1,
        1,
        1.1,
        1.2,
        1,
        1,
        1,
        1,
        1,
        1,
        1.1,
        1.3,
        .9,
        1,
        1,
        1.5,
        .6,
        .6,
        .6,
        .6,
        .6,
        .6,
      ],
      19 => <double>[1, .8, .9, .8, 1.3, .4],
      20 => <double>[.7, 1.2, 1, 1.1, 1.2, .6],
      21 => <double>[1, 1, 1.3, 1.15, 1.1, 1.5, 1.2, .8],
      _ => throw FormatException('缺少接口常量 $index'),
    };
    final bytes = ByteData(values.length * 4);
    for (var i = 0; i < values.length; i++) {
      bytes.setFloat32(i * 4, values[i], Endian.little);
    }
    return bytes.buffer.asUint8List();
  }

  Map<String, dynamic> get strategyDialogs =>
      Map<String, dynamic>.from(_rules['strategyDialogs'] as Map? ?? const {});

  BayePictureGroup? pictures(int resource) {
    final cached = _pictures[resource];
    if (cached != null) return cached;
    final bytes = archive.item(resource);
    if (bytes == null) return null;
    return _pictures[resource] = BayePictureGroup.decode(bytes);
  }

  BayeAnimation? animation(int resource) {
    final cached = _animations[resource];
    if (cached != null) return cached;
    final bytes = archive.item(resource);
    if (bytes == null) return null;
    return _animations[resource] = BayeAnimation.decode(bytes);
  }

  String text(int resource, int index) => _strings.putIfAbsent((
    resource,
    index,
  ), () => codec.decode(archive.item(resource, index) ?? const <int>[]));

  /// 所有视觉模式、查询和战斗提示共用的姓名出口，人物ID不受文字勘误影响。
  String personName(int period, int index) => index < 0 || index >= 2000
      ? ''
      : PersonNames.correct(
          text(const [62, 70, 71, 72][period - 1], index + 1).trimRight(),
        );
  String cityName(int index) =>
      index < 0 ? '' : text(58, index + 1).trimRight();
  String toolName(int index) =>
      index < 0 ? '' : text(73, index + 1).trimRight();
  String skillName(int index) =>
      index < 0 ? '' : text(11, index + 1).trimRight();

  /// 对应LoadPeriod：先读城市和年份，再读人物及队列，最后重置开局字段。
  GameWorld loadPeriod(int period, {int seed = 1}) {
    if (period < 1 || period > 4) {
      throw RangeError.range(period, 1, 4, 'period');
    }
    final cityData = _Reader(requiredItem(57, period));
    final cities = <GameCity>[];
    for (var i = 0; i < rule('citiesCount', 38); i++) {
      cities.add(
        GameCity(
          state: cityData.u8(),
          belong: cityData.u16(),
          satrapId: cityData.u16(),
          farmingLimit: cityData.u16(),
          farming: cityData.u16(),
          commerceLimit: cityData.u16(),
          commerce: cityData.u16(),
          peopleDevotion: cityData.u8(),
          avoidCalamity: cityData.u8(),
          populationLimit: cityData.u32(),
          population: cityData.u32(),
          money: cityData.u16(),
          food: cityData.u16(),
          mothballArms: cityData.u16(),
          personQueue: cityData.u16(),
          persons: cityData.u16(),
          toolQueue: cityData.u16(),
          tools: cityData.u16(),
        ).copyWith(state: 0),
      );
    }
    final year = cityData.u16();
    final rawPeople = requiredItem(61, period);
    if (rawPeople.length % 19 != 0) throw const FormatException('武将记录长度无效');
    final peopleData = _Reader(rawPeople);
    final people = <GamePerson>[];
    for (var i = 0; i < rawPeople.length ~/ 19; i++) {
      people.add(
        GamePerson(
          oldBelong: peopleData.u16(),
          belong: peopleData.u16(),
          level: peopleData.u8(),
          force: peopleData.u8(),
          iq: peopleData.u8(),
          devotion: peopleData.u8(),
          character: peopleData.u8(),
          experience: peopleData.u8(),
          thew: peopleData.u8(),
          armsType: peopleData.u8(),
          arms: peopleData.u16(),
          equip0: peopleData.u16(),
          equip1: peopleData.u16(),
          age: peopleData.u8(),
        ).copyWith(oldBelong: 0, thew: 100, arms: 100),
      );
    }
    final tools = <GameTool>[];
    final rawTools = requiredItem(66);
    if (rawTools.length % 66 != 0) throw const FormatException('道具记录长度无效');
    for (var i = 0; i < rawTools.length ~/ 66; i++) {
      final offset = i * 66;
      tools.add(
        GameTool(
          useFlag: rawTools[offset + 1],
          attack: rawTools[offset + 62],
          iq: rawTools[offset + 63],
          move: rawTools[offset + 64],
          arm: rawTools[offset + 65],
        ),
      );
    }
    return GameWorld(
      period: period,
      year: year,
      month: 1,
      persons: people,
      cities: cities,
      tools: tools,
      personQueue: _wordQueue(requiredItem(65, period), people.length),
      goodsQueue: _wordQueue(requiredItem(68, period), 2000),
      randomSeed: seed,
    );
  }

  /// 君主按城池首次出现的顺序去重，与GetAllKings一致，不按武将编号重排。
  List<int> rulers(GameWorld world) {
    final seen = <int>{};
    return <int>[
      for (final city in world.cities)
        if (city.belong > 0 && seen.add(city.belong - 1)) city.belong - 1,
    ];
  }

  /// 选择君主后执行旧版开局顺序：定位、敌军初始兵粮、精修属性Hook。
  void beginGame(GameWorld world, int rulerIndex) {
    if (!rulers(world).contains(rulerIndex)) {
      throw const FormatException('君主编号无效');
    }
    world.playerRulerIndex = rulerIndex;
    final owned = world.citiesOf(rulerIndex);
    if (owned.isNotEmpty) {
      final positions = constant(6);
      final first = owned.first;
      world.cursorX = positions[first * 2];
      world.cursorY = positions[first * 2 + 1];
    }
    for (var i = 0; i < world.cities.length; i++) {
      final city = world.cities[i];
      if (city.belong == rulerIndex + 1) continue;
      for (final id in world.personsInCity(i, belong: city.belong)) {
        final person = world.person(id);
        if (person != null) world.setPerson(id, person.copyWith(arms: 800));
      }
      world.setCity(i, city.copyWith(food: (city.food + 1000).clamp(0, 65535)));
    }
    final overrides = (_rules['personOverrides'] as List)[world.period - 1];
    if (overrides is Map) {
      for (final entry in overrides.entries) {
        final index = int.tryParse(entry.key.toString());
        if (index == null || entry.value is! Map) continue;
        final current = world.person(index);
        if (current == null) continue;
        final patch = entry.value as Map;
        world.setPerson(
          index,
          current.copyWith(
            force: _patchInt(patch, 'Force'),
            iq: _patchInt(patch, 'IQ'),
            armsType: _patchInt(patch, 'ArmsType'),
            level: _patchInt(patch, 'Level'),
          ),
        );
      }
    }
    final toolOverrides = _rules['tools'];
    if (toolOverrides is List) {
      for (var i = 0; i < toolOverrides.length && i < world.tools.length; i++) {
        final patch = toolOverrides[i];
        if (patch is! Map) continue;
        world.setTool(
          i,
          world.tools[i].copyWith(
            attack: _patchInt(patch, 'at'),
            iq: _patchInt(patch, 'iq'),
            move: _patchInt(patch, 'move'),
            arm: _patchInt(patch, 'arm'),
            useFlag: _patchInt(patch, 'useflag'),
          ),
        );
      }
    }
  }

  int? _patchInt(Map<dynamic, dynamic> value, String key) {
    final number = value[key];
    return number is num ? number.toInt() : null;
  }

  /// 按原存档界面的GBK字节偏移插入君主和年份，不按Unicode字符数估算空格。
  String saveTitle(GameWorld world) {
    final ruler = world.playerRulerIndex;
    if (ruler == null) return '';
    final template = requiredItem(1, 65);
    final name = codec.encode(personName(world.period, ruler));
    final year = world.year.toString().codeUnits;
    if (template.length < 10 + year.length + 1) {
      throw const FormatException('存档标题模板不完整');
    }
    for (var i = 0; i < name.length && i < 10; i++) {
      template[i] = name[i];
    }
    template.setRange(10, 10 + year.length, year);
    template[10 + year.length] = 0;
    return codec.decode(template);
  }

  List<int> _wordQueue(Uint8List bytes, int capacity) {
    if (bytes.length.isOdd || bytes.length > capacity * 2) {
      throw const FormatException('资源队列长度无效');
    }
    final result = List<int>.filled(capacity, 0);
    final view = ByteData.sublistView(bytes);
    for (var i = 0; i < bytes.length ~/ 2; i++) {
      result[i] = view.getUint16(i * 2, Endian.little);
    }
    return result;
  }
}

/// 有边界检查的小端顺序读取器，替代不安全的结构体指针转换。
final class _Reader {
  _Reader(Uint8List bytes) : _data = ByteData.sublistView(bytes);
  final ByteData _data;
  int _offset = 0;
  int _read(int width) {
    if (_offset + width > _data.lengthInBytes) {
      throw const FormatException('记录数据截断');
    }
    final value = width == 1
        ? _data.getUint8(_offset)
        : width == 2
        ? _data.getUint16(_offset, Endian.little)
        : _data.getUint32(_offset, Endian.little);
    _offset += width;
    return value;
  }

  int u8() => _read(1);
  int u16() => _read(2);
  int u32() => _read(4);
}

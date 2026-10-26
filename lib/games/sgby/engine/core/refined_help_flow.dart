import '../../domain/models/game_world.dart';
import '../rendering/baye_canvas.dart';
import 'native_game_session.dart';

/// 精修4X资源脚本showMainHelp的原生菜单和详情联动。
///
/// 列表选择与左侧资料同帧绘制；关闭菜单即释放回调，不保留旧武将或城市的引用。
final class RefinedHelpFlow {
  RefinedHelpFlow(this.session);
  final NativeGameSession session;
  BayeCanvas get canvas => session.canvas;
  GameWorld? get world => session.world;
  String _person(int id) => session.resources.personName(world!.period, id);
  String _tool(int id) =>
      id < 0 || world?.tool(id) == null ? '' : session.resources.toolName(id);
  String _pad(String text, int width) =>
      ' ' *
          (width - session.resources.codec.encode(text).length).clamp(
            0,
            width,
          ) +
      text;
  void _text((int, int, int, int) r, int x, int y, String value) => canvas.text(
    x,
    y,
    value,
    left: r.$1,
    top: r.$2,
    right: r.$3,
    bottom: r.$4,
  );
  void _box((int, int, int, int) r) => canvas.rectangle(r.$1, r.$2, r.$3, r.$4);
  void _name(int x1, int x2, int y1, int y2, String name) {
    final length = name.length < 3 ? 3 : name.length;
    final left = x1 + ((x2 - x1 - length * 12) / 2).ceil() + 1,
        top = y1 + ((y2 - y1 - 12) / 2).ceil();
    canvas.fill(x1 + 1, y1 + 1, x2 - 1, y2 - 1);
    final label = name.length == 2 ? '${name[0]}  ${name[1]}' : name;
    canvas.text(left, top, label);
  }

  void _base() {
    session.showStrategy();
    canvas.fill(14, 14, 177, 131);
    canvas.rectangle(14, 14, 177, 131);
  }

  void start() {
    if (session.isDisposed || world == null) return;
    session.showStrategy();
    session.canvasMenu(
      [
        '查看将领',
        '查看道具',
        '查看城池',
        session.legacySaveLoadEnabled ? '关闭 S/L' : '打开 S/L',
      ],
      (choice) {
        if (choice == 0) {
          _heroes();
        } else if (choice == 1) {
          _tools();
        } else if (choice == 2) {
          _cities(0);
        } else {
          if (choice == 3) {
            session.legacySaveLoadEnabled = !session.legacySaveLoadEnabled;
          }
          session.showStrategy();
        }
      },
      x: 96,
      y: 48,
      columns: 8,
    );
  }

  void _heroes() {
    final data = world;
    if (data == null) return;
    final people = <int>[];
    for (var i = 0; i < data.persons.length; i++) {
      if (_person(i).isEmpty) break;
      people.add(i);
    }
    _base();
    session.canvasMenu(
      [for (final id in people) _person(id)],
      (_) => start(),
      x: 121,
      y: 19,
      columns: 8,
      onHighlight: (index) {
        final id = people[index], p = data.person(id)!;
        canvas.fill(16, 16, 116, 129);
        _box((16, 16, 78, 62));
        canvas.fill(35, 20, 59, 44);
        canvas.picture(47 + data.period, id, 35, 20);
        _name(18, 76, 46, 60, _person(id));
        _box((80, 16, 116, 62));
        _text((80, 16, 116, 62), 82, 18, '武');
        _text((80, 16, 116, 62), 96, 18, _pad('${p.force}', 3));
        _text((80, 16, 116, 62), 82, 33, '智');
        _text((80, 16, 116, 62), 96, 33, _pad('${p.iq}', 3));
        _text((80, 16, 116, 62), 82, 48, '忠');
        _text(
          (80, 16, 116, 62),
          96,
          48,
          _pad(p.devotion > 0 ? '${p.devotion}' : '--', 3),
        );
        _box((16, 64, 116, 80));
        _text((16, 64, 116, 80), 18, 67, 'Lv.${p.level}(${p.experience}%)');
        _text(
          (16, 64, 116, 80),
          90,
          67,
          _pad(
            const ['骑兵', '步兵', '弓兵', '水兵', '极兵', '玄兵'][p.armsType.clamp(0, 5)],
            4,
          ),
        );
        _box((16, 82, 116, 129));
        final city = data.cityOfPerson(id);
        _text(
          (16, 82, 116, 129),
          18,
          85,
          city == null ? '--' : session.resources.cityName(city),
        );
        _text(
          (16, 82, 116, 129),
          42,
          85,
          _pad(
            p.belong == 65535 || p.belong == 255
                ? '已阵亡'
                : p.belong > 0
                ? '${_person(p.belong - 1)}势力'
                : '无势力',
            12,
          ),
        );
        _text((16, 82, 116, 129), 18, 100, '装备:');
        _text((16, 82, 116, 129), 54, 100, _pad(_tool(p.equip0 - 1), 10));
        _text((16, 82, 116, 129), 18, 115, '装备:');
        _text((16, 82, 116, 129), 54, 115, _pad(_tool(p.equip1 - 1), 10));
      },
    );
  }

  void _tools() {
    final data = world;
    if (data == null) return;
    _base();
    session.canvasMenu(
      [for (var i = 0; i < data.tools.length; i++) _tool(i)],
      (_) => start(),
      x: 121,
      y: 19,
      columns: 8,
      onHighlight: (id) {
        final tool = data.tool(id)!;
        canvas.fill(16, 16, 116, 129);
        _box((16, 16, 70, 44));
        _name(18, 68, 18, 44, _tool(id));
        _box((16, 46, 70, 62));
        int? equipped, slot, city;
        for (var i = 0; i < data.persons.length; i++) {
          final p = data.person(i)!;
          if (p.equip0 == id + 1) {
            equipped = i;
            slot = 0;
            break;
          }
          if (p.equip1 == id + 1) {
            equipped = i;
            slot = 1;
            break;
          }
        }
        for (var i = 0; i < data.cities.length; i++) {
          if (data.goodsInCity(i).any((value) => (value & 32767) == id)) {
            city = i;
            break;
          }
        }
        if (tool.useFlag == 0 && equipped != null) {
          _text((16, 46, 70, 62), 19, 49, _person(equipped));
          _text((16, 46, 70, 62), 55, 49, slot == 0 ? '主' : '副');
        } else {
          _text(
            (16, 46, 70, 62),
            19,
            49,
            city == null
                ? (tool.useFlag == 0 ? '装备' : '已被使用')
                : '${session.resources.cityName(city)}${tool.useFlag == 0 ? '装备' : ''}',
          );
        }
        _box((72, 16, 116, 62));
        _text((72, 16, 116, 62), 74, 18, '武力');
        _text((72, 16, 116, 62), 102, 18, _pad('${tool.attack}', 2));
        _text((72, 16, 116, 62), 74, 33, '智力');
        _text((72, 16, 116, 62), 102, 33, _pad('${tool.iq}', 2));
        _text((72, 16, 116, 62), 74, 48, '速度');
        _text((72, 16, 116, 62), 102, 48, _pad('${tool.move}', 2));
        _box((16, 64, 116, 80));
        _text((16, 64, 116, 80), 18, 67, '兵种变更:');
        _text(
          (16, 64, 116, 80),
          72,
          67,
          _pad(
            tool.arm > 0 && tool.arm <= 6
                ? const ['水兵', '玄兵', '极兵', '骑兵', '步兵', '弓兵'][tool.arm - 1]
                : '--',
            7,
          ),
        );
        _box((16, 82, 116, 129));
        _text((16, 82, 116, 129), 18, 85, '特殊效果:');
        _text(
          (18, 82, 114, 128),
          18,
          103,
          _tool(id) == '赤兔'
              ? '    进入战场时变更兵种为极兵。'
              : _tool(id) == '鬼谷子'
              ? '    进入战场时变更兵种为玄兵。'
              : '',
        );
      },
    );
  }

  void _cities(int initial) {
    final data = world;
    if (data == null) return;
    _base();
    session.canvasMenu(
      [
        for (var i = 0; i < data.cities.length; i++)
          session.resources.cityName(i),
      ],
      (index) {
        if (index == null) {
          start();
          return;
        }
        final city = data.city(index)!;
        canvas.fill(16, 16, 175, 111);
        _box((16, 16, 175, 62));
        _text(
          (18, 18, 174, 60),
          18,
          18,
          '在野人才:${data.personsInCity(index).where((id) => data.person(id)!.belong != city.belong).map(_person).join(',')}',
        );
        _box((16, 64, 175, 110));
        _text(
          (18, 64, 174, 108),
          18,
          66,
          '宝物列表:${data.goodsInCity(index).map((id) => _tool(id & 32767)).join(',')}',
        );
        session.canvasMenu(
          ['确认'],
          (_) => _cities(index),
          x: 19,
          y: 115,
          columns: 25,
          pixelWidth: 154,
        );
      },
      x: 145,
      y: 19,
      columns: 4,
      initialSelection: initial,
      onHighlight: (id) {
        final city = data.city(id)!;
        canvas.fill(16, 16, 140, 129);
        _box((16, 16, 98, 46));
        _text((16, 16, 98, 46), 18, 18, '归属:');
        _text(
          (16, 16, 98, 46),
          48,
          18,
          _pad(city.belong > 0 ? _person(city.belong - 1) : '--', 8),
        );
        _text((16, 16, 98, 46), 18, 33, '城主:');
        _text(
          (16, 16, 98, 46),
          48,
          33,
          _pad(city.satrapId > 0 ? _person(city.satrapId - 1) : '--', 8),
        );
        _box((100, 16, 140, 46));
        _text((100, 16, 140, 46), 102, 18, '后备兵');
        _text((100, 16, 140, 46), 102, 33, _pad('${city.mothballArms}', 6));
        _box((16, 48, 50, 78));
        _text((16, 48, 50, 78), 18, 50, '忠');
        _text((16, 48, 50, 78), 30, 50, _pad('${city.peopleDevotion}', 3));
        if (city.state == 0) {
          _text((16, 48, 50, 78), 18, 65, '灾');
          _text((16, 48, 50, 78), 30, 65, _pad('${city.avoidCalamity}', 3));
        } else {
          _text(
            (16, 48, 50, 78),
            22,
            65,
            const ['饥荒', '旱灾', '水灾', '暴动'][(city.state - 1).clamp(0, 3)],
          );
        }
        _box((52, 48, 140, 78));
        _text((16, 48, 140, 78), 54, 50, '商业:');
        _text(
          (16, 48, 140, 78),
          84,
          50,
          _pad('${city.commerce}/${city.commerceLimit}', 9),
        );
        _text((16, 48, 140, 78), 54, 65, '农业:');
        _text(
          (16, 48, 140, 78),
          84,
          65,
          _pad('${city.farming}/${city.farmingLimit}', 9),
        );
        _box((16, 80, 92, 110));
        _text((16, 80, 92, 110), 18, 82, '人才数量:');
        _text((16, 80, 92, 110), 72, 82, _pad('${city.persons}', 3));
        _text((16, 80, 92, 110), 18, 97, '宝物数量:');
        _text((16, 80, 92, 110), 72, 97, _pad('${city.tools}', 3));
        _box((94, 80, 140, 110));
        _text((94, 80, 140, 110), 96, 82, '钱');
        _text((94, 80, 140, 110), 108, 82, _pad('${city.money}', 5));
        _text((94, 80, 140, 110), 96, 97, '粮');
        _text((94, 80, 140, 110), 108, 97, _pad('${city.food}', 5));
        _box((16, 112, 140, 129));
        _text((16, 112, 140, 129), 18, 115, '人口:');
        _text(
          (16, 112, 140, 129),
          48,
          115,
          _pad('${city.population}/${city.populationLimit}', 15),
        );
      },
    );
  }
}

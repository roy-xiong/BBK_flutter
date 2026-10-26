import '../../domain/models/game_world.dart';
import '../../domain/models/game_report.dart';
import '../../domain/use_cases/build_general_roster.dart';
import '../resources/baye_database.dart';
import 'baye_canvas.dart';

/// 原版启动、君主选择和战略场景的逐层绘制。
///
/// 坐标对应gamEng.c和ShowCityMap；画面不混入Flutter控件、系统字体或
/// 自动布局。此类只读领域数据，绘制不能推进随机源或修改人物状态。
final class GameSceneRenderer {
  GameSceneRenderer(this.resources, this.canvas);
  final BayeDatabase resources;
  final BayeCanvas canvas;

  void mainMenu() {
    // GamPicMenu覆盖图片区域；右侧不足整逻辑行的区域保留开场动画底图。
    canvas.picture(44, 0, 0, 0);
  }

  void periodMenu() {
    canvas.picture(45, 0, 0, 0);
  }

  void rulerSelection(
    GameWorld world,
    List<int> kings,
    int selected,
    int top, {
    bool blink = false,
  }) {
    canvas.clear();
    canvas.rectangle(0, 0, canvas.width - 1, canvas.height - 1);
    canvas.text(72, 4, resources.text(1, 45));
    canvas.picture(47, 0, 60, 20);
    final count = (canvas.height - 1 - 6 - 13) ~/ 12;
    canvas.rectangle(13, 10, 53, 13 + 12 * count + 2);
    final right = canvas.width - 2;
    canvas.rectangle(canvas.width - 28, 0, right, 14);
    canvas.text(canvas.width - 26, 1, '返回');
    for (var row = 0; row < count && top + row < kings.length; row++) {
      final name = resources.personName(world.period, kings[top + row]);
      canvas.text(
        16,
        13 + row * 12,
        name,
        left: 16,
        top: 13,
        right: 51,
        bottom: count * 12 + 13,
      );
    }
    if (selected >= top && selected < top + count) {
      final y = 13 + (selected - top) * 12;
      canvas.reverse(16, y, 51, y + 12);
    }
    if (blink && selected >= 0 && selected < kings.length) {
      final positions = resources.constant(6);
      for (final city in world.citiesOf(kings[selected])) {
        final x = positions[city * 2] * 7 + 63;
        final y = positions[city * 2 + 1] * 7 + 23;
        canvas.reverse(x, y, x + 1, y + 1);
      }
    }
  }

  /// 战略地图以全图格子编号索引图块，而C_MAP仅负责查找该格的城池编号。
  void strategy(GameWorld world) {
    canvas.clear();
    final columns = ((canvas.width + 1) ~/ 16) - 2;
    final rows = canvas.height ~/ 16;
    final map = resources.constant(14);
    for (var row = 0; row < rows; row++) {
      final mapY = world.viewY + row;
      if (mapY >= resources.mapHeight) break;
      for (var column = 0; column < columns; column++) {
        final mapX = world.viewX + column;
        if (mapX >= resources.mapWidth) break;
        final index = mapY * resources.mapWidth + mapX;
        canvas.picture(54, index, column * 16, row * 16, color: 200);
        final cityIndex = map[index] - 1;
        final city = world.city(cityIndex);
        if (city == null) continue;
        final owned = city.belong == (world.playerRulerIndex ?? -1) + 1;
        final pictureIndex = owned
            ? 8
            : city.belong > 0
            ? 7
            : 0;
        canvas.picture(
          55,
          pictureIndex,
          column * 16 + 4,
          row * 16 + 4,
          color: owned || city.belong == 0 ? 255 : 225,
        );
      }
    }
    final cursorX = world.cursorX - world.viewX;
    final cursorY = world.cursorY - world.viewY;
    if (cursorX >= 0 && cursorX < columns && cursorY >= 0 && cursorY < rows) {
      canvas.picture(56, 0, cursorX * 16 + 4, cursorY * 16 + 8, color: 230);
    }
    final panelX = columns * 16;
    canvas.fill(panelX, 0, canvas.width - 1, canvas.height - 1);
    final ruler = world.playerRulerIndex;
    if (ruler != null) {
      canvas.picture(
        47 + world.period,
        ruler,
        panelX + (canvas.width - 1 - panelX - 24) ~/ 2,
        4,
      );
      canvas.picture(69, 1, panelX + 2, 33);
      canvas.text(panelX + 12, 33, '${world.citiesOf(ruler).length}');
      canvas.picture(69, 0, panelX + 2, 47);
      final people = world.persons
          .where((person) => person.belong == ruler + 1)
          .length;
      canvas.text(panelX + 12, 45, '$people');
    }
    canvas.text(
      panelX + 1,
      canvas.height - 38,
      '${world.year}${resources.text(64, 63)}',
    );
    canvas.text(
      panelX + 1,
      canvas.height - 26,
      '${world.month}${resources.text(64, 64)}',
    );
    final selected = selectedCity(world);
    if (selected != null) {
      canvas.text(panelX + 2, canvas.height - 14, resources.cityName(selected));
    }
    if (resources.rule('hideRightBorder') == 0) {
      canvas.rectangle(panelX, 0, canvas.width - 1, canvas.height - 1);
    }
    canvas.markBase('strategy');
  }

  int? selectedCity(GameWorld world) {
    if (world.cursorX < 0 ||
        world.cursorY < 0 ||
        world.cursorX >= resources.mapWidth ||
        world.cursorY >= resources.mapHeight) {
      return null;
    }
    final id =
        resources.constant(14)[world.cursorY * resources.mapWidth +
            world.cursorX] -
        1;
    return world.city(id) == null ? null : id;
  }

  void miniMap() {
    canvas.clear();
    canvas.picture(
      75,
      0,
      (canvas.width - 1 - 84) ~/ 2,
      (canvas.height - 1 - 64) ~/ 2,
    );
  }

  /// ShowPersonControl的固定表格，左右切换属性组，姓名列始终保留。
  int peopleSelection(
    GameWorld world,
    List<int> ids,
    int selected,
    int top,
    int firstProperty,
  ) {
    final widths = [
      8,
      10,
      4,
      4,
      4,
      4,
      4,
      4,
      4,
      world.hasLargeArmies ? 6 : 5,
      4,
      10,
      10,
    ];
    const left = 4, topY = 2;
    final count = ((canvas.height - 5) ~/ 12 - 1).clamp(1, ids.length);
    final bottom = topY + count * 12 + 12;
    canvas.fill(left + 1, topY + 1, canvas.width - 6, bottom);
    canvas.rectangle(left, topY, canvas.width - 5, bottom + 1);
    final columns = <(int, int, int)>[(6, 48, -1)];
    var end = 54;
    var next = firstProperty;
    for (var property = firstProperty; property < widths.length; property++) {
      final width = widths[property] * 6;
      if (end + width > canvas.width - 6) break;
      columns.add((end + 1, width, property));
      end += width + 1;
      next = property + 1;
    }
    void centered(int center, int y, String text) {
      final bytes = resources.codec.encode(text);
      canvas.textBytes(center - bytes.length * 3, y, bytes);
    }

    for (final column in columns) {
      centered(
        column.$1 + column.$2 ~/ 2,
        3,
        resources.text(64, column.$3 < 0 ? 23 : 24 + column.$3),
      );
    }
    final types = BuildGeneralRoster(resources);
    for (var row = 0; row < count && top + row < ids.length; row++) {
      final id = ids[top + row];
      final person = world.person(id);
      if (person == null) continue;
      final city = world.cityOfPerson(id);
      final values = <String>[
        person.belong == 65535
            ? resources.text(64, 49)
            : person.belong == id + 1
            ? resources.text(64, 48)
            : person.belong == 0
            ? resources.text(64, 47)
            : resources.personName(world.period, person.belong - 1),
        city == null ? '' : resources.cityName(city),
        '${person.level}',
        '${person.force}',
        '${person.iq}',
        person.belong == 0 || person.belong == id + 1
            ? resources.text(64, 51)
            : '${person.devotion}',
        '${person.experience}',
        '${person.thew}',
        resources.text(64, 17 + types.effectiveArmsType(world, person)),
        '${person.arms}',
        '${person.age}',
        resources.toolName(person.equip0 - 1),
        resources.toolName(person.equip1 - 1),
      ];
      for (final column in columns) {
        centered(
          column.$1 + column.$2 ~/ 2,
          15 + row * 12,
          column.$3 < 0
              ? resources.personName(world.period, id)
              : values[column.$3],
        );
      }
    }
    if (selected >= top && selected < top + count) {
      canvas.reverse(
        5,
        15 + (selected - top) * 12,
        52,
        26 + (selected - top) * 12,
      );
    }
    return next;
  }

  /// NumOperate的三行数字框及确定/最大/取消热区。
  int goodsSelection(
    GameWorld world,
    List<int> ids,
    int selected,
    int top,
    int firstProperty,
  ) {
    final widths = resources.constant(7);
    final count = ((canvas.height - 5) ~/ 12 - 1).clamp(1, ids.length),
        bottom = 2 + count * 12 + 12;
    canvas.fill(5, 3, canvas.width - 6, bottom);
    canvas.rectangle(4, 2, canvas.width - 5, bottom + 1);
    final columns = <(int, int, int)>[(6, 60, -1)];
    var end = 66, next = firstProperty;
    for (var property = firstProperty; property < 5; property++) {
      final width = widths[property] * 6;
      if (end + width > canvas.width - 6) break;
      columns.add((end + 1, width, property));
      end += width + 1;
      next = property + 1;
    }
    void center(int x, int y, String value) =>
        canvas.text(x - resources.codec.encode(value).length * 3, y, value);
    for (final column in columns) {
      center(
        column.$1 + column.$2 ~/ 2,
        3,
        resources.text(64, column.$3 < 0 ? 65 : 66 + column.$3),
      );
    }
    for (var row = 0; row < count && top + row < ids.length; row++) {
      final id = ids[top + row], tool = world.tool(ids[top + row]);
      if (tool == null) continue;
      final arm = tool.arm == 0
          ? resources.text(64, 50)
          : tool.arm <= 3
          ? resources.text(64, 72 + tool.arm)
          : resources.text(64, 17 + tool.arm - 4);
      final values = [
        resources.text(64, tool.useFlag == 0 ? 71 : 72),
        '${tool.attack}',
        '${tool.iq}',
        '${tool.move}',
        arm,
      ];
      for (final column in columns) {
        center(
          column.$1 + column.$2 ~/ 2,
          15 + row * 12,
          column.$3 < 0 ? resources.toolName(id) : values[column.$3],
        );
      }
    }
    if (selected >= top && selected < top + count) {
      canvas.reverse(
        5,
        15 + (selected - top) * 12,
        64,
        26 + (selected - top) * 12,
      );
    }
    return next;
  }

  /// NumOperate的三行数字框及确定/最大/取消热区。
  void number(String title, int minimum, int maximum, int value, int digit) {
    final left = (canvas.width - 1 - 72) ~/ 2;
    final top = (canvas.height - 1 - 36) ~/ 2;
    canvas.fill(left, top, left + 72, top + 36);
    canvas.rectangle(left - 1, top - 1, left + 73, top + 37);
    canvas.text(left, top, title);
    canvas.text(left, top + 12, resources.text(64, 44));
    final text = value.toString().padLeft(maximum.toString().length, '0');
    canvas.text(left + 42, top + 12, text);
    canvas.reverse(
      left + 42 + digit * 6,
      top + 12,
      left + 47 + digit * 6,
      top + 23,
    );
    canvas.text(left, top + 24, '${resources.text(64, 45)}$maximum');
    for (var i = 0; i < 3; i++) {
      final x = left - 10 + i * 31;
      canvas.fill(x, top + 39, x + 29, top + 52);
      canvas.rectangle(x, top + 39, x + 29, top + 52);
      canvas.text(x + 2, top + 40, const ['确定', '最大', '取消'][i]);
    }
  }

  /// 城市详情每页显示9项，保留旧版13逻辑点行距。
  void cityDetails(GameWorld world, int cityIndex, int top) {
    final city = world.city(cityIndex);
    if (city == null) return;
    final x = (canvas.width - 1 - 90) ~/ 2;
    final lines = (canvas.height - 6) ~/ 13;
    canvas.fill(x - 5, 2, x + 95, 2 + 13 * lines);
    canvas.rectangle(x - 6, 1, x + 96, 3 + 13 * lines);
    canvas.text(x, 2, resources.cityName(cityIndex));
    final noPerson = resources.text(64, 50);
    final values = <String>[
      resources.text(64, 2) +
          (city.belong > 0
              ? resources.personName(world.period, city.belong - 1)
              : noPerson),
      resources.text(64, 3) +
          (city.satrapId > 0
              ? resources.personName(world.period, city.satrapId - 1)
              : noPerson),
      '${resources.text(64, 4)}${city.farming}/${city.farmingLimit}',
      '${resources.text(64, 5)}${city.commerce}/${city.commerceLimit}',
      '${resources.text(64, 6)}${city.peopleDevotion}',
      '${resources.text(64, 7)}${city.avoidCalamity}',
      '${resources.text(64, 8)}${city.population}',
      '${resources.text(64, 9)}${city.money}',
      '${resources.text(64, 10)}${city.food}',
      '${resources.text(64, 11)}${city.mothballArms}',
      resources.text(64, 1) + resources.text(64, 12 + city.state.clamp(0, 4)),
    ];
    for (var row = 0; row < lines - 1 && top + row < values.length; row++) {
      canvas.text(x, 14 + row * 13, values[top + row]);
    }
  }

  void saveSlots(List<String?> titles, int selected) {
    canvas.picture(46, 0, 0, 0);
    final anchor = resources.ruleArray('saveFaceListAnchor');
    final x = anchor.length >= 2 ? anchor[0] : 31;
    final y = anchor.length >= 2 ? anchor[1] : 33;
    for (var i = 0; i < titles.length; i++) {
      canvas.text(x, y + i * 14, titles[i] ?? resources.text(1, 66));
    }
    canvas.reverse(x, y + selected * 14, x + 95, y + selected * 14 + 12);
  }

  /// 原版 ShowTacticNote 的底部窄框，黑白和彩色重放同一文字和坐标。
  void tacticNote(GameWorld world, int ruler) {
    final left = (canvas.width - 1) ~/ 2 - (6 * 19 + 4) ~/ 2;
    final right = left + 6 * 19 + 4;
    final bottom = canvas.height - 1 - 2;
    final top = bottom - 12 - 2;
    canvas.fill(left, top, right, bottom);
    canvas.rectangle(left, top, right, bottom);
    canvas.text(
      (canvas.width - 1 - 6 * 19) ~/ 2,
      bottom - 12,
      '${resources.personName(world.period, ruler)}${resources.text(64, 163)}',
    );
  }

  void report(String value, {int page = 0}) {
    final bytes = resources.codec.encode(value);
    final columns = (canvas.width - 1) ~/ 6 - 2;
    final lines = bytes.length ~/ columns + 1;
    final top = lines > (canvas.height - 1) ~/ 12 - 1
        ? 5
        : (canvas.height - 1 - lines * 12) >> 1;
    final bottom = lines > (canvas.height - 1) ~/ 12 - 1
        ? canvas.height - 6
        : top + lines * 12;
    final right = canvas.width - 5;
    canvas.fill(2, top - 3, right + 3, bottom + 2);
    canvas.rectangle(2, top - 3, right + 3, bottom + 2);
    canvas.textBytes(
      5,
      top,
      bytes,
      left: 5,
      top: top,
      right: right,
      bottom: bottom,
    );
  }

  /// ShowGReport的底部48点区域，文字按PlcStrShowS避让原版人物头像。
  void generalReport(GameWorld world, int person, String value) {
    final end = canvas.height - 1;
    final top = end - 52;
    canvas.fill(4, top, canvas.width - 6, end - 4);
    canvas.rectangle(4, top, canvas.width - 6, end - 5);
    canvas.picture(
      47 + world.period,
      person,
      21,
      top + 6,
      color: resources.rule('personHeadColor', 255),
    );
    final name = resources.personName(world.period, person);
    canvas.text(34 - resources.codec.encode(name).length * 3, top + 32, name);
    final bytes = resources.codec.encode(value);
    var offset = 0;
    final regions = <(int, int, int, int)>[
      (8, top, canvas.width - 8, end - 46),
      (8, end - 46, 10, end - 4),
      (62, end - 46, canvas.width - 8, end - 4),
      (8, end - 4, canvas.width - 8, end - 7),
    ];
    for (final region in regions) {
      if (offset >= bytes.length) break;
      offset += canvas.textBytes(
        region.$1,
        region.$2,
        bytes.sublist(offset),
        left: region.$1,
        top: region.$2,
        right: region.$3,
        bottom: region.$4,
      );
    }
  }

  /// ShowFightNoteFace与四类战争通知，保留120×84框、84×64插图和居中文字。
  void battleNote(
    GameWorld world,
    GameReportKind kind,
    int? actor,
    int? target,
  ) {
    final left = (canvas.width - 1 - 120) ~/ 2,
        top = (canvas.height - 1 - 84) ~/ 2;
    canvas.fill(left, top, left + 120, top + 84);
    canvas.rectangle(left, top, left + 120, top + 84);
    final icon = switch (kind) {
      GameReportKind.attack => 0,
      GameReportKind.fight => 1,
      GameReportKind.victory => 2,
      _ => 3,
    };
    canvas.picture(76, icon, (canvas.width - 1 - 84) ~/ 2, top + 2);
    String s(int id) => resources.text(64, id);
    String name(int? id) =>
        id == null ? '' : resources.personName(world.period, id);
    final who = actor == world.playerRulerIndex ? s(98) : name(actor);
    final text = switch (kind) {
      GameReportKind.attack =>
        '$who${s(97)}${target == null ? '' : resources.cityName(target)}',
      GameReportKind.fight => '${name(actor)}${s(104)}${name(target)}${s(105)}',
      GameReportKind.victory => '$who${s(91)}',
      _ => '${s(98)}${s(92)}',
    };
    canvas.text(
      (canvas.width - 1) ~/ 2 - resources.codec.encode(text).length * 3,
      top + 68,
      text,
    );
  }
}

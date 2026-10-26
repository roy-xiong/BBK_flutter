import 'dart:typed_data';

/// 原版FGTJK与战场变量，人物编号为0基，空槽位显式使用null。
///
/// 世界数据仍由GameWorld拥有；战场只保存坐标、生命、策略点和战斗阶段。
/// 所有修改在会话isolate串行完成，帧绘制不持有可写的后台引用。
final class GameBattle {
  GameBattle({
    required this.mode,
    required this.city,
    required this.sourceCity,
    required this.way,
    required this.mapId,
    required this.playerFood,
    required this.enemyFood,
    required List<int?> people,
  }) : people = List<int?>.unmodifiable(people),
       units = List<BattleUnit>.generate(20, (_) => BattleUnit()) {
    if (people.length != 20 || mode < 0 || mode > 2 || way < 0 || way > 7) {
      throw const FormatException('战斗参数无效');
    }
  }
  final int mode;
  final int city;
  final int sourceCity;
  final int way;
  final int mapId;
  final List<int?> people;
  final List<BattleUnit> units;
  final Map<int, int> originalArmTypes = <int, int>{};
  int playerFood;
  int enemyFood;
  int result = 0;
  int day = 0;
  int maxDays = 30;
  int weather = 3;
  int width = 0;
  int height = 0;
  int cityX = 0;
  int cityY = 0;
  int focusX = 0;
  int focusY = 0;
  int viewX = 0;
  int viewY = 0;
  int enemyFoodKnown = 0;
  bool entered = false;
  int originalCityBelong = 0;
  final List<int> initialCaptives = <int>[];
  Uint8List map = Uint8List(0);
  int get mainGeneral => mode == 1 ? 0 : 10;

  int terrain(int x, int y) {
    if (x < 0 || y < 0 || x >= width || y >= height) return 255;
    final tile = map[y * width + x];
    if (tile > 15) return tile == 41 ? 6 : 7;
    if (tile > 5) return 2;
    if (tile > 4) return 3;
    if (tile > 3) return 4;
    if (tile > 2) return 5;
    if (tile > 1) return 0;
    return tile > 0 ? 1 : 255;
  }

  int? unitAt(int x, int y) {
    for (var i = 0; i < units.length; i++) {
      final unit = units[i];
      if (unit.state != 8 && unit.x == x && unit.y == y) return i;
    }
    return null;
  }
}

/// 对应JLPOS，离场/空人物槽状态固定为8，避免空槽被当作可行动武将。
final class BattleUnit {
  int x = 0, y = 0, hp = 0, mp = 0, move = 0, active = 0, state = 8;
  Map<String, int> toJson() => {
    'x': x,
    'y': y,
    'hp': hp,
    'mp': mp,
    'move': move,
    'active': active,
    'state': state,
  };
}

/// 战场指令：0普通攻击、1计谋、3休息。源、目标均为战场槽位。
final class BattleCommand {
  const BattleCommand(this.source, this.type, {this.target, this.skill});
  final int source;
  final int type;
  final int? target;
  final int? skill;
}

/// 原版15×15行军缓冲及地图映射起点，保留每个格子的剩余移动力。
final class BattlePath {
  BattlePath(this.left, this.top, this.useX, this.useY, this.values);
  final int left, top, useX, useY;
  final Uint8List values;
  int valueAt(int x, int y) {
    final column = x - left + useX, row = y - top + useY;
    return column < 0 || row < 0 || column >= 15 || row >= 15
        ? 255
        : values[row * 15 + column];
  }

  bool contains(int x, int y) => valueAt(x, y) < 128;
}

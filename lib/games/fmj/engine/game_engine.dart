import 'dart:collection';
import 'dart:convert';
import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import '../data/game_data.dart';
import 'game_actor.dart';
import 'pixel_surface.dart';

part 'game_render.dart';
part 'game_battle.dart';
part 'game_menus.dart';
part 'game_navigation.dart';

/// 输入编号与 BBK 原引擎一致，触屏、键盘和寻路均经过同一入口。
enum GameKey { up, down, left, right, pageUp, pageDown, confirm, cancel }

final class ScriptCursor {
  ScriptCursor(this.script);
  final GameScript script;
  int pointer = 0, timer = 0, timerCounter = 0, timerEvent = 0;
  bool running = true;
  ScriptCursor? previous;

  /// 仅供新版对白署名：触发本段对话的 NPC，不参与剧情条件或事件跳转。
  String? dialogueSpeaker;
}

final class GameOperation {
  GameOperation(
    this.kind, {
    this.text = '',
    this.args = const [],
    this.options = const [],
  });
  final String kind;
  final String text;
  final List<int> args;
  final List<String> options;
  int elapsed = 0, start = 0, next = 0, selected = 0;
  bool armed = false;
  GameMovie? movie;
  String scriptId = '';
  int address = 0;
  String? speakerName;
}

/// 纯 Dart 会话状态机；只由前台固定步长驱动，不持有 Widget 或平台 Context。
final class GameEngine {
  /// 仅供后台只读路由解释器使用，不创建电影或位图，也不调用 Flutter 排版器。
  GameEngine._navigation(this.data)
    : textLayout = const _NavigationTextLayout(),
      random = math.Random(0);

  GameEngine(this.data, {required this.textLayout, math.Random? random})
    : random = random ?? math.Random() {
    surface = PixelSurface(320, 192, textLayout: textLayout);
    intro = GameMovie(data, 1, 247)..iterations = 4;
    render();
  }
  final GameData data;
  late final GameNavigation navigation = GameNavigation(this);
  final SystemTextLayout textLayout;
  final math.Random random;
  static final _speakerPrefix = RegExp(r'^([^：:\r\n，。！？!?]{1,16})[：:]');
  late PixelSurface surface;
  final List<GameActor> players = [];
  final Map<int, GameActor> npcs = {};
  final Set<int> flags = {};
  final List<int> variables = List.filled(240, 0);
  final Map<String, int> inventory = {};
  final List<GameMenu> menus = [];
  final List<Map<String, dynamic>?> saves = List.filled(3, null);
  final Map<String, dynamic> preferences = {
    'modernUi': false,
    'darkControls': true,
    'controlsVisible': true,
    'hapticsEnabled': true,
    'portraitControls': false,
    'manualLayout': false,
    'wideView': true,
    'hd': true,
    'runSpeed': 1,
    'autoBattle': false,
    'invincible': false,
    'oneHitKill': false,
    'normalAttackAll': false,
    'randomBattleDisabled': false,
    'storyScope': 'complete',
  };
  GameMap? map;
  ScriptCursor? cursor;
  GameOperation? operation;
  GameBattle? battle;
  GameMovie? intro;
  String screen = 'intro', sceneName = '', error = '', notice = '';
  int screenX = 0, screenY = 0, money = 0, titleSelection = 0, ticks = 0;
  double _walkElapsed = 0;
  bool _scriptYield = false;
  bool _dialogueConfirmHeld = false;
  bool allowMiss = false, allowTossArm = true;
  bool disableSave = false, fightEnabled = false, ended = false;
  List<int> randomMonsters = [], randomBackground = [2, 2, 2];
  List<(int, int)> route = [];
  String routeMap = '';
  String? _stageBackup;
  int? stageStoneProgress;
  String? get stageBackup => _stageBackup;
  void retainStageBackup(String? value) {
    if (value != null && value.length <= 8 * 1024 * 1024) _stageBackup = value;
  }

  GameActor? get player => players.isEmpty ? null : players.first;
  bool get wide => preferences['wideView'] != false;
  bool get canSave =>
      screen == 'play' &&
      !disableSave &&
      battle == null &&
      operation == null &&
      cursor?.running != true &&
      players.isNotEmpty;
  bool get forceClassic => operation?.movie?.id == '1:3';

  /// 同一倍速作用于整个游戏时钟。输入、寻路、剧情与战斗不得分别重复乘速。
  int get runSpeed => (preferences['runSpeed'] as int? ?? 1).clamp(1, 4);
  void Function()? onSaveChanged;

  /// 一次前台回调对应 40ms 实际时间，以倍速执行原有固定步长，再统一输出画面。
  ///
  /// 保留逐步状态转换，奖励、脚本事件和碰撞仍按原顺序各执行一次；不直接跳过
  /// 升级卡片或动画。菜单、后台由原有入口暂停，恢复时不追赶离开期间的时间。
  void update() {
    if (error.isNotEmpty) return;
    try {
      final steps = screen == 'play' && menus.isEmpty ? runSpeed : 1;
      for (var step = 0; step < steps; step++) {
        _updateStep();
      }
      render();
    } catch (e) {
      error = '游戏状态异常：$e';
      route.clear();
    }
  }

  /// 原引擎的一次 40ms 模拟；此层只处理游戏时间，不另读倍速或驱动平台定时器。
  void _updateStep() {
    ticks++;
    if (screen == 'intro') {
      final movie = intro;
      if (movie == null || !movie.update()) {
        if (movie?.id == '1:247') {
          intro = GameMovie(data, 1, 248)..iterations = 4;
        } else {
          screen = 'title';
          intro = null;
        }
      }
    } else if (screen == 'play' && menus.isEmpty) {
      final current = cursor;
      if (current != null &&
          (current.running || battle == null) &&
          current.timer > 0 &&
          current.timerEvent > 0) {
        current.timerCounter -= 40;
        if (current.timerCounter <= 0) {
          current.timerCounter += current.timer;
          triggerEvent(current.timerEvent);
        }
      }
      final op = operation;
      if (op != null) {
        _updateOperation(op);
      } else if (cursor?.running == true) {
        _process();
      } else if (battle != null) {
        battle?.update();
      } else {
        _updateNpcs();
        navigation.tick();
        if (route.isNotEmpty) {
          _walkElapsed += 40;
          // 倍速已由外层游戏时钟处理；此处仍是每 105ms 游戏时间走一格。
          while (route.isNotEmpty && _walkElapsed >= 105) {
            _walkElapsed -= 105;
            _routeStep();
            if (cursor?.running == true ||
                operation != null ||
                battle != null) {
              _walkElapsed = 0;
              break;
            }
          }
        } else {
          _walkElapsed = 0;
        }
      }
    }
  }

  void startNewGame() {
    navigation.cancel();
    stageStoneProgress = null;
    players.clear();
    npcs.clear();
    flags.clear();
    inventory.clear();
    menus.clear();
    variables.fillRange(0, variables.length, 0);
    money = 0;
    map = null;
    operation = null;
    battle = null;
    screenX = 0;
    screenY = 0;
    fightEnabled = false;
    disableSave = false;
    ended = false;
    error = '';
    route.clear();
    screen = 'play';
    _chapter('1:1');
    render();
  }

  void _chapter(String id, {bool call = false}) {
    final script = data.scripts[id];
    if (script == null) throw FormatException('剧情不存在：$id');
    final previous = cursor;
    cursor = ScriptCursor(script);
    if (call) {
      cursor?.previous = previous;
      cursor?.dialogueSpeaker = previous?.dialogueSpeaker;
    } else {
      npcs.clear();
      variables.fillRange(200, 240, 0);
    }
  }

  void jump(int address) {
    final c = cursor;
    if (c == null) return;
    final pointer = c.script.addresses[address];
    if (pointer == null) {
      throw FormatException('剧情跳转无效：${c.script.id}/$address');
    }
    c.pointer = pointer;
    c.running = true;
    _scriptYield = true;
  }

  bool triggerEvent(int id) {
    final c = cursor;
    if (c == null || id < 1 || id > c.script.events.length) return false;
    final address = c.script.events[id - 1];
    if (address == 0) return false;
    operation = null;
    c.dialogueSpeaker = id <= 40 ? npcs[id]?.name : null;
    jump(address);
    return true;
  }

  void _process() {
    _scriptYield = false;
    for (var budget = 0; budget < 512; budget++) {
      final c = cursor;
      if (c == null ||
          !c.running ||
          operation != null ||
          battle != null && battle?.scriptPaused != true) {
        return;
      }
      if (c.pointer >= c.script.commands.length) {
        c.running = false;
        return;
      }
      final command = c.script.commands[c.pointer++];
      _execute(command, c);
      if (_scriptYield ||
          !identical(cursor, c) ||
          operation != null ||
          menus.isNotEmpty) {
        return;
      }
    }
    throw const FormatException('剧情指令循环超过安全预算');
  }

  void _execute(GameCommand cmd, ScriptCursor c) {
    final a = cmd.args;
    if (c.script.id == '2:52' && cmd.opcode == 3) {
      const markers = {465: 2301, 536: 2301, 765: 2302, 865: 2302, 1131: 2303};
      final marker = markers[cmd.address];
      if (marker != null) flags.add(marker);
      if (cmd.address == 765) flags.add(2313);
    }
    if (c.script.id == '2:18' && cmd.address == 1527 && cmd.opcode == 20) {
      flags.add(2316);
    }
    int n(int i) => cmd.arg(i);
    String id(int start) =>
        c.script.id == '2:52' &&
            cmd.address == 1072 &&
            cmd.opcode == 57 &&
            start == 0
        ? '14:6'
        : '${n(start)}:${n(start + 1)}';
    GameActor? actor(int index) => index == 0 ? player : _player(index);
    switch (cmd.opcode) {
      case 0:
        break; // 上游引擎的音乐指令为空操作，资源没有独立音频轨。
      case 1:
        _loadMap(id(0), n(2), n(3));
        operation = GameOperation('delay', args: [40]);
      case 2:
        final p = GameActor.load(data, 1, n(0));
        if (p != null) {
          p.x = screenX + n(1);
          p.y = screenY + n(2);
          players.add(p);
        }
        operation = GameOperation('delay', args: [40]);
      case 3:
      case 33:
        npcs.remove(n(0));
      case 6:
        operation = GameOperation('move', args: a);
      case 9:
        final passage = _postTombCaveExit(c.script, cmd, flags);
        if (passage != null) {
          npcs.clear();
          _loadMap(passage.$1, passage.$2, passage.$3);
          _chapter(passage.$4);
          operation = GameOperation('delay', args: [40]);
          break;
        }
        for (final id in _defeatedHemingActors(c.script, cmd, flags)) {
          npcs.remove(id);
        }
        if (c.script.id == '9:13' && stageStoneProgress != null) {
          final completed = stageStoneProgress ?? 0;
          variables[1] = completed;
          for (var i = 1; i <= completed; i++) {
            npcs.remove(i);
          }
          stageStoneProgress = null;
        }
        c.running = false;
      case 10:
        jump(n(0));
      case 11:
        if (flags.contains(n(0)) &&
            !_allowReturnPassage(c.script, cmd, flags)) {
          jump(n(1));
        }
      case 12:
        _setVar(n(0), n(1));
      case 13:
        if (n(0) == 0) {
          final named = _speakerPrefix.firstMatch(cmd.string)?.group(1);
          if (named != null) c.dialogueSpeaker = named;
        }
        operation = GameOperation('dialogue', text: cmd.string, args: a)
          ..scriptId = c.script.id
          ..address = cmd.address
          ..speakerName = c.dialogueSpeaker;
      case 14:
        _chapter(id(0));
      case 16:
        screenX = n(0);
        screenY = n(1);
      case 20:
        screen = 'title';
        battle = null;
        operation = null;
        ended = true;
        c.running = false;
      case 21:
        if (_var(n(0)) == n(1)) jump(n(2));
      case 22:
        _setVar(n(0), _var(n(0)) + n(1));
      case 23:
        _setVar(n(0), _var(n(0)) - n(1));
      case 24:
        final p = _player(n(0));
        if (p != null) {
          players.remove(p);
          players.insert(0, p);
        }
      case 26:
        flags.add(n(0));
      case 27:
        flags.remove(n(0));
      case 28:
        _openShop(cmd.string);
      case 29:
        final p = n(0) == 0 ? player : npcs[n(0)],
            other = n(1) == 0 ? player : npcs[n(1)];
        // 剧情自动安排 NPC 与主角相向时，同样保留原角色身份；不依赖点击事件。
        final speaker = n(0) == 0
            ? other
            : n(1) == 0
            ? p
            : null;
        if (speaker?.type == 2) c.dialogueSpeaker = speaker?.name;
        if (p != null && other != null) {
          other.direction = p.x > other.x
              ? 2
              : p.x < other.x
              ? 4
              : p.y > other.y
              ? 3
              : 1;
        }
        operation = GameOperation('delay', args: [40]);
      case 30:
        final movie = GameMovie(data, n(0), n(1));
        operation = GameOperation('movie', args: a)..movie = movie;
      case 31:
        final values = cmd.text;
        operation =
            GameOperation(
                'choice',
                args: a,
                options: values is List
                    ? values.whereType<String>().toList()
                    : ['是', '否'],
              )
              ..scriptId = c.script.id
              ..address = cmd.address;
      case 32:
      case 38:
        final npc = GameActor.load(data, cmd.opcode == 32 ? 4 : 2, n(1));
        if (npc != null) {
          npc.x = n(2);
          npc.y = n(3);
          npcs[n(0)] = npc;
        }
      case 34:
        addGoods(id(0));
        operation = GameOperation(
          'timed',
          text: '获得:${goodsName(id(0))}',
          args: [1000],
        );
      case 35:
        randomMonsters = a.take(8).where((v) => v != 0).toList();
        randomBackground = a.skip(8).take(3).toList();
        fightEnabled = true;
      case 36:
        fightEnabled = true;
      case 37:
        fightEnabled = false;
      case 39:
        battle = GameBattle(
          this,
          monsters: a.skip(1).take(3).toList(),
          background: a.skip(4).take(3).toList(),
          randomFight: false,
          maxRound: n(0),
          eventRounds: a.skip(7).take(3).toList(),
          events: a.skip(10).take(3).toList(),
          loss: n(13),
          win: n(14),
        );
        c.running = false;
      case 40:
        players.removeWhere((p) => p.index == n(0));
      case 41:
        money = (money + n(0) + (n(1) << 16)).clamp(0, 2147483647);
      case 42:
        money = (money - n(0) - (n(1) << 16)).clamp(0, 2147483647);
      case 43:
        money = (n(0) + (n(1) << 16)).clamp(0, 2147483647);
      case 44:
        final p = _player(n(0));
        final magic = id(1);
        if (p != null && !p.extraMagic.contains(magic)) p.extraMagic.add(magic);
        operation = GameOperation(
          'timed',
          text: '${p?.name ?? ''}学会了魔法:${magicName(magic)}',
          args: [1000],
        );
      case 45:
        openInventory(mode: 'sell');
      case 46:
        final npc = npcs[n(0)];
        if (npc != null) npc.state = n(1);
      case 47:
        operation = GameOperation('message', text: cmd.string);
      case 48:
      case 57:
        if (!useGoods(id(0))) jump(n(2));
      case 49:
        final p = _player(n(0));
        if (p != null) p.hp = (p.maxHp * n(1) ~/ 100).clamp(0, p.maxHp);
      case 50:
        final p = _player(n(0));
        if (p != null) {
          p.levelUp(data, n(1));
          operation = GameOperation('message', text: '${p.name}修行提升');
        }
      case 51:
        final npc = npcs[n(0)];
        if (npc != null) npc.step = 1;
      case 52:
        npcs.clear();
        c.dialogueSpeaker = null;
      case 53:
        final p = n(0) == 0 ? player : npcs[n(0)];
        if (p != null) {
          p.direction = [1, 2, 3, 4][n(1).clamp(0, 3)];
          p.step = n(2) % 4;
        }
        operation = GameOperation('delay', args: [300]);
      case 54:
        sceneName = cmd.string;
      case 55:
        // 地点名短暂提示即可；700ms 为一倍速时长，其他倍速共用游戏时钟。
        operation = GameOperation('timed', text: sceneName, args: [700]);
      case 56:
        operation = GameOperation('delay', args: [40]);
      case 58:
        final p = actor(n(0));
        if (p != null) {
          final value = _attribute(p, n(1));
          if (value < n(2)) {
            jump(n(3));
          } else if (value > n(2)) {
            jump(n(4));
          }
        }
      case 59:
      case 60:
        final p = actor(n(0));
        if (p != null) _setAttribute(p, n(1), n(2), add: cmd.opcode == 60);
      case 61:
        operation = GameOperation('credits', text: cmd.string, args: a);
      case 62:
        if (!useGoods(id(0), n(2))) jump(n(3));
      case 63:
        if (random.nextInt(1000) <= n(0)) jump(n(1));
      case 64:
        operation = GameOperation(
          'menu',
          args: a,
          options: cmd.string.split(' '),
        );
      case 65:
        if (money < n(0) + (n(1) << 16)) jump(n(2));
      case 66:
        _chapter(id(0), call: true);
      case 67:
        final value = _var(n(0));
        if (value > _var(n(1))) {
          jump(n(2));
        } else if (value < _var(n(1))) {
          jump(n(3));
        }
      case 68:
        if (c.previous != null) {
          cursor = c.previous;
        } else {
          c.running = false;
        }
      case 69:
        operation = GameOperation('timed', text: cmd.string, args: [n(0) * 10]);
      case 70:
        disableSave = true;
      case 71:
        disableSave = false;
      case 72:
        openSaveMenu(force: true);
      case 73:
        c.timer = n(1) * 500;
        c.timerCounter = c.timer;
        c.timerEvent = n(0);
      case 74:
      case 75:
        break; // 上游用于调试坐标显示的空指令。
      case 76:
        _setVar(n(1), _var(n(0)));
      case 77:
        final count = inventory[id(0)] ?? 0;
        if (count == n(2)) {
          jump(n(3));
        } else if (count > n(2)) {
          jump(n(4));
        }
      case 78:
        allowMiss = n(0) == 1;
      case 79:
        allowTossArm = n(0) == 1;
      default:
        throw FormatException('不支持的剧情指令：${cmd.opcode}');
    }
  }

  void _updateOperation(GameOperation op) {
    op.elapsed += 40;
    if (op.kind == 'delay' && (op.args.isEmpty || op.elapsed >= op.args[0])) {
      operation = null;
    }
    if (op.kind == 'timed' &&
        op.args.isNotEmpty &&
        op.args[0] > 0 &&
        op.elapsed >= op.args[0]) {
      operation = null;
    }
    if (op.kind == 'movie' && op.movie?.update() != true) operation = null;
    if (op.kind == 'credits' &&
        op.elapsed > data.encoding.encode(op.text).length * 100 + 10000) {
      operation = null;
    }
    if (op.kind == 'move' && op.args.length >= 3 && op.elapsed >= 120) {
      final npc = op.args[0] == 0 ? player : npcs[op.args[0]];
      if (npc == null || npc.x == op.args[1] && npc.y == op.args[2]) {
        operation = null;
        return;
      }
      op.elapsed = 0;
      _moveActor(
        npc,
        npc.x > op.args[1]
            ? 4
            : npc.x < op.args[1]
            ? 2
            : npc.y > op.args[2]
            ? 1
            : 3,
      );
    }
  }

  /// 按下和抬起分离，选择框必须显式选定，避免快读对白误选互斥剧情。
  void key(GameKey key, {bool down = true, bool automatic = false}) {
    if (error.isNotEmpty) return;
    // 对白在按下确认时翻页。该次抬起仍属于对白，不能穿透到刚出现的战斗
    // 去选择攻击目标，否则会把自动战斗卡在手动选敌状态。
    if (key == GameKey.confirm && !down && _dialogueConfirmHeld) {
      _dialogueConfirmHeld = false;
      return;
    }
    if (!automatic && down && key.index < 4) navigation.cancel();
    if (screen == 'intro') {
      if (down && key == GameKey.cancel) {
        screen = 'title';
        intro = null;
      }
      return;
    }
    if (screen == 'title') {
      if (down && (key == GameKey.up || key == GameKey.down)) {
        titleSelection = 1 - titleSelection;
      }
      if (!down && key == GameKey.confirm) {
        if (titleSelection == 0) {
          startNewGame();
        } else {
          openSaveMenu(load: true);
        }
      }
      render();
      return;
    }
    if (menus.isNotEmpty) {
      _menuKey(key, down);
      render();
      return;
    }
    final op = operation;
    if (op != null) {
      if (op.kind == 'choice' || op.kind == 'menu') {
        if (down && key.index < 4) {
          op.selected =
              (op.selected +
                  (key == GameKey.up || key == GameKey.left ? -1 : 1)) %
              op.options.length;
          op.armed = true;
        }
        if (!down && key == GameKey.confirm && op.armed) choose(op.selected);
        if (!down && key == GameKey.cancel && op.kind == 'menu') {
          _setVar(op.args.first, 255);
          operation = null;
        }
      } else if (down && op.kind == 'dialogue') {
        if (key == GameKey.confirm) _dialogueConfirmHeld = true;
        if (op.next >= op.text.length) {
          operation = null;
        } else {
          op.start = op.next;
        }
      } else if (!down && (op.kind == 'message' || op.kind == 'timed')) {
        operation = null;
      } else if (!down &&
          op.kind == 'movie' &&
          op.args.length > 4 &&
          (op.args[4] == 1 || op.args[4] == 3)) {
        operation = null;
      } else if (!down && op.kind == 'credits' && key == GameKey.cancel) {
        operation = null;
      }
      render();
      return;
    }
    if (battle != null) {
      battle?.key(key, down);
      render();
      return;
    }
    if (cursor?.running == true) return;
    if (down && key.index < 4) {
      move([1, 3, 4, 2][key.index]);
    } else if (down && key == GameKey.confirm) {
      interact();
    } else if (!down && key == GameKey.cancel) {
      openMainMenu();
    }
    render();
  }

  void press(GameKey key) {
    this.key(key);
    this.key(key, down: false);
  }

  void choose(int index, {GameOperation? expected}) {
    final op = operation;
    if (expected != null && !identical(op, expected)) return;
    if (op == null || index < 0 || index >= op.options.length) return;
    operation = null;
    if (op.kind == 'choice') {
      const deferred = {
        '9:1': 2330,
        '10:1': 2331,
        '11:4': 2332,
        '14:9': 2333,
        '2:33': 2334,
      };
      final flag = deferred[op.scriptId];
      if (index == 0 && flag != null) flags.add(flag);
      if (op.scriptId == '5:1' && op.address == 512 && index == 0) {
        flags.add(2335);
        navigation.cancel();
      }
      if (op.scriptId == '2:18' && op.address == 866) {
        flags.add(2314);
        if (index == 1) {
          flags.add(2315);
        } else {
          flags.remove(2315);
        }
      }
    }
    if (op.kind == 'choice' && index == 1 && op.args.isNotEmpty) {
      jump(op.args.first);
    }
    if (op.kind == 'menu' && op.args.isNotEmpty) _setVar(op.args.first, index);
    render();
  }

  void _loadMap(String id, int x, int y) {
    final next = data.maps[id];
    if (next == null) throw FormatException('地图不存在：$id');
    final p = player;
    if (p != null && map != null) {
      p.x = p.x - screenX + x;
      p.y = p.y - screenY + y;
    }
    map = next;
    screenX = x;
    screenY = y;
    route.clear();
  }

  GameActor? _player(int id) {
    for (final p in players) {
      if (p.index == id) return p;
    }
    return null;
  }

  int _var(int index) =>
      index >= 0 && index < variables.length ? variables[index] : 0;
  void _setVar(int index, int value) {
    if (index < 0 || index >= variables.length) {
      throw const FormatException('剧情变量下标无效');
    }
    variables[index] = value;
  }

  static (int, int) _delta(int direction) => switch (direction) {
    1 => (0, -1),
    2 => (1, 0),
    3 => (0, 1),
    _ => (-1, 0),
  };
  void _moveActor(GameActor p, int d) {
    final (dx, dy) = _delta(d);
    p.x += dx;
    p.y += dy;
    p.direction = d;
    p.step = (p.step + 1) % 4;
  }

  int? _npcAt(int x, int y) {
    for (final e in npcs.entries) {
      if (e.value.x == x && e.value.y == y) return e.key;
    }
    return null;
  }

  bool _walkable(int x, int y, {bool player = false}) =>
      map?.canWalk(x, y, player: player) == true && _npcAt(x, y) == null;
  void move(int direction) {
    final p = player, m = map;
    if (p == null || m == null) return;
    final (dx, dy) = _delta(direction);
    final x = p.x + dx, y = p.y + dy;
    final event = m.event(x, y);
    if (event != 0) triggerEvent(event + 40);
    if (_walkable(x, y, player: true)) {
      _moveActor(p, direction);
      screenX += dx;
      screenY += dy;
    } else {
      p.direction = direction;
      p.step = (p.step + 1) % 4;
    }
    if (event == 0 &&
        cursor?.running != true &&
        fightEnabled &&
        preferences['randomBattleDisabled'] != true &&
        randomMonsters.isNotEmpty &&
        random.nextInt(20) == 0) {
      battle = GameBattle(
        this,
        monsters: List.generate(
          random.nextInt(3) + 1,
          (_) => randomMonsters[random.nextInt(randomMonsters.length)],
        ),
        background: randomBackground,
        randomFight: true,
      );
    }
  }

  void interact() {
    final p = player;
    if (p == null) return;
    final (dx, dy) = _delta(p.direction);
    final x = p.x + dx, y = p.y + dy;
    final npc = _npcAt(x, y);
    if (npc != null) {
      triggerEvent(npc);
      return;
    }
    final event = map?.event(x, y) ?? 0;
    if (event != 0) triggerEvent(event + 40);
  }

  void _updateNpcs() {
    final p = player;
    for (final npc in npcs.values) {
      npc.tick += 40;
      if (npc.state == 4 && npc.tick > 100) {
        npc.step = (npc.step + 1) % 4;
        npc.tick = 0;
      }
      if (npc.type == 4) continue;
      if (npc.state == 3) {
        npc.pause -= 40;
        if (npc.pause < 0) npc.state = 2;
      }
      if ((npc.state == 1 || npc.state == 2) && npc.tick >= 500) {
        npc.tick = 0;
        if (random.nextInt(5) == 0) {
          npc.pause = npc.delay * 100;
          npc.state = 3;
          continue;
        }
        if (random.nextInt(5) == 0) npc.direction = random.nextInt(4) + 1;
        final currentMap = map;
        if (currentMap == null) continue;
        // 自由游走不能进入玩家不可达的四周取景边缘。旧档中已走到边缘的
        // 人物逐格返回可达区域；强制剧情移动仍由原 move 指令独立控制。
        final outside =
            npc.x < 4 ||
            npc.x >= currentMap.width - 4 ||
            npc.y < 3 ||
            npc.y >= currentMap.height - 2;
        if (outside) {
          npc.direction = npc.x < 4
              ? 2
              : npc.x >= currentMap.width - 4
              ? 4
              : npc.y < 3
              ? 3
              : 1;
        }
        final (dx, dy) = _delta(npc.direction);
        final x = npc.x + dx, y = npc.y + dy;
        if (_walkable(x, y) &&
            (outside || currentMap.canWalk(x, y, player: true)) &&
            !(p?.x == x && p?.y == y)) {
          _moveActor(npc, npc.direction);
        }
      }
    }
  }

  /// 寻路只提交正常方向输入；不能跳过碰撞、地图事件、遭遇或剧情限制。
  bool walkTo(int x, int y) {
    final p = player, m = map;
    if (p == null ||
        m == null ||
        cursor?.running == true ||
        operation != null ||
        battle != null) {
      return false;
    }
    final start = (p.x, p.y),
        target = (x, y),
        queue = Queue<(int, int)>()..add(start);
    final parents = <(int, int), (int, int)?>{start: null};
    final passiveEvents = <int, bool>{};
    while (queue.isNotEmpty && parents.length <= m.cells.length) {
      final here = queue.removeFirst();
      if (here == target) break;
      for (final d in [1, 2, 3, 4]) {
        final (dx, dy) = _delta(d);
        final next = (here.$1 + dx, here.$2 + dy);
        if (!parents.containsKey(next) &&
            _walkable(next.$1, next.$2, player: true) &&
            (m.event(next.$1, next.$2) == 0 ||
                passiveEvents.putIfAbsent(
                  m.event(next.$1, next.$2) + 40,
                  () =>
                      navigation.isPassiveEvent(m.event(next.$1, next.$2) + 40),
                ))) {
          parents[next] = here;
          queue.add(next);
        }
      }
    }
    if (!parents.containsKey(target)) return false;
    final path = <(int, int)>[];
    var current = target;
    while (current != start) {
      path.add(current);
      final prev = parents[current];
      if (prev == null) return false;
      current = prev;
    }
    route = path.reversed.toList();
    routeMap = m.id;
    return true;
  }

  void _routeStep() {
    final p = player;
    if (p == null || map?.id != routeMap) {
      route.clear();
      return;
    }
    if (route.isEmpty) return;
    final next = route.first;
    if (!_walkable(next.$1, next.$2, player: true)) {
      final target = route.last;
      if (!walkTo(target.$1, target.$2)) route.clear();
      return;
    }
    final direction = next.$1 > p.x
        ? 2
        : next.$1 < p.x
        ? 4
        : next.$2 > p.y
        ? 3
        : 1;
    route.removeAt(0);
    move(direction);
  }

  GameRecord? goods(String id) {
    final a = id.split(':');
    return a.length == 2
        ? data.record(6, int.tryParse(a[0]) ?? 0, int.tryParse(a[1]) ?? 0)
        : null;
  }

  GameRecord? magic(String id) {
    final a = id.split(':');
    return a.length == 2
        ? data.record(4, int.tryParse(a[0]) ?? 0, int.tryParse(a[1]) ?? 0)
        : null;
  }

  String goodsName(String id) => goods(id)?.text(6) ?? id;
  String magicName(String id) => magic(id)?.text(6) ?? id;
  void addGoods(String id, [int count = 1]) {
    if (goods(id) != null) {
      inventory[id] = ((inventory[id] ?? 0) + count).clamp(0, 999);
    }
  }

  bool useGoods(String id, [int count = 1]) {
    final current = inventory[id] ?? 0;
    if (count < 0 || current < count) return false;
    if (current == count) {
      inventory.remove(id);
    } else {
      inventory[id] = current - count;
    }
    return true;
  }

  int _attribute(GameActor p, int field) {
    if (field >= 15 && field <= 22) {
      const slots = [7, 5, 6, 2, 4, 3, 0, 1];
      return int.tryParse(
            p.equipment[slots[field - 15]]?.split(':').last ?? '0',
          ) ??
          0;
    }
    return switch (field) {
      0 => p.level,
      1 => p.attack,
      2 => p.defense,
      3 => p.speed,
      4 => p.hp,
      5 => p.mp,
      6 => p.exp,
      7 => p.spirit,
      8 => p.luck,
      23 => p.maxHp,
      24 => p.maxMp,
      _ => 0,
    };
  }

  void _setAttribute(GameActor p, int field, int value, {bool add = false}) {
    if (add) {
      value += switch (field) {
        10 => p.maxHp,
        11 => p.maxMp,
        _ => _attribute(p, field),
      };
    }
    switch (field) {
      case 0:
        p.level = value.clamp(1, 255);
      case 1:
        p.attack = value.clamp(0, 999);
      case 2:
        p.defense = value.clamp(0, 999);
      case 3:
        p.speed = value.clamp(0, 99);
      case 4:
        p.hp = value.clamp(0, p.maxHp);
      case 5:
        p.mp = value.clamp(0, p.maxMp);
      case 6:
        p.exp = value.clamp(0, 2147483647);
      case 7:
        p.spirit = value.clamp(0, 99);
      case 8:
        p.luck = value.clamp(0, 99);
      case 10:
      case 15:
        p.maxHp = value.clamp(1, 999);
      case 11:
      case 16:
        p.maxMp = value.clamp(0, 999);
    }
  }

  /// 保存快照不包含画布、闭包和平台资源；写入层负责串行与原子替换。
  Map<String, dynamic> snapshot() => {
    'format': 1,
    'navigationRevision': 1,
    'rom': 'a71a98c72af5d1122cc4adbad861c5fa4c2454850cbc6d2b70903b818c0dfd93',
    'scene': sceneName,
    'map': map?.id,
    'screenX': screenX,
    'screenY': screenY,
    'money': money,
    'flags': flags.toList()..sort(),
    'variables': List<int>.from(variables),
    'disableSave': disableSave,
    'allowMiss': allowMiss,
    'allowTossArm': allowTossArm,
    'players': players.map((p) => p.toJson()).toList(),
    'npcs': npcs.map((id, p) => MapEntry('$id', p.toJson())),
    'inventory': Map<String, int>.from(inventory),
    'script': cursor?.script.id,
    'timer': cursor?.timer ?? 0,
    'timerCounter': cursor?.timerCounter ?? 0,
    'timerEvent': cursor?.timerEvent ?? 0,
    'fightEnabled': fightEnabled,
    'randomMonsters': randomMonsters,
    'randomBackground': randomBackground,
  };

  /// 先验证完整快照，再一次性替换会话，损坏档案不会污染当前进度。
  void restore(Map<String, dynamic> j) {
    if (j['format'] != 1 ||
        j['rom'] !=
            'a71a98c72af5d1122cc4adbad861c5fa4c2454850cbc6d2b70903b818c0dfd93') {
      throw const FormatException('存档版本或游戏资源不匹配');
    }
    for (final key in [
      'screenX',
      'screenY',
      'money',
      'timer',
      'timerCounter',
      'timerEvent',
      'navigationRevision',
    ]) {
      if (j[key] != null && j[key] is! int) {
        throw const FormatException('存档数值类型无效');
      }
    }
    if (j['scene'] != null && j['scene'] is! String) {
      throw const FormatException('存档场景名称无效');
    }
    final nextMap = data.maps[j['map']], nextScript = data.scripts[j['script']];
    final rawPlayers = j['players'],
        rawVars = j['variables'],
        rawFlags = j['flags'];
    if (nextMap == null ||
        nextScript == null ||
        rawPlayers is! List ||
        rawPlayers.isEmpty ||
        rawPlayers.length > 3) {
      throw const FormatException('存档地图或队伍无效');
    }
    if (rawVars is! List ||
        rawVars.length != 240 ||
        rawVars.any((v) => v is! int) ||
        rawFlags is! List) {
      throw const FormatException('存档变量数量或类型无效');
    }
    final nextPlayers = rawPlayers
        .map((v) => GameActor.fromJson(Map<String, dynamic>.from(v as Map)))
        .toList();
    if (nextPlayers.any(
      (p) =>
          p.type != 1 ||
          data.record(3, 1, p.index) == null ||
          p.x < 0 ||
          p.y < 0 ||
          p.x >= nextMap.width ||
          p.y >= nextMap.height,
    )) {
      throw const FormatException('存档人物或坐标无效');
    }
    final nextInventory = Map<String, int>.from(j['inventory'] as Map);
    if (nextInventory.entries.any(
      (e) => goods(e.key) == null || e.value < 0 || e.value > 999,
    )) {
      throw const FormatException('存档物品数据无效');
    }
    final nextNpcs = <int, GameActor>{};
    for (final entry in (j['npcs'] as Map).entries) {
      final id = int.tryParse('${entry.key}');
      if (id == null || id < 1 || id > 40) {
        throw const FormatException('存档场景对象编号无效');
      }
      final actor = GameActor.fromJson(
        Map<String, dynamic>.from(entry.value as Map),
      );
      if (data.record(3, actor.type, actor.index) == null) {
        throw const FormatException('存档场景对象资源无效');
      }
      nextNpcs[id] = actor;
    }
    final nextMonsters = (j['randomMonsters'] as List).cast<int>().toList(),
        nextBackground = (j['randomBackground'] as List).cast<int>().toList();
    if (nextBackground.length != 3) throw const FormatException('存档战斗背景无效');
    final nextFlags = rawFlags
        .whereType<int>()
        .where((v) => v > 0 && v <= 2400)
        .toSet();
    // 旧版完整剧情导航先用了紫瞳魔灯的钥匙，导致三把钥匙耗尽却没有不点卡片。
    // 对这一明确状态补回一次；新快照带修订号，之后消耗、读档都不会重复补给。
    final repairKey =
        (j['navigationRevision'] as int? ?? 0) < 1 &&
        preferences['storyScope'] == 'complete' &&
        nextFlags.containsAll({264, 1077, 1095, 1114}) &&
        !nextFlags.contains(1099) &&
        !nextFlags.contains(2010) &&
        !nextFlags.contains(2302) &&
        (nextInventory['14:2'] ?? 0) == 0 &&
        (nextInventory['14:7'] ?? 0) == 0;
    if (repairKey) nextInventory['14:2'] = 1;
    players
      ..clear()
      ..addAll(nextPlayers);
    map = nextMap;
    cursor = ScriptCursor(nextScript)..running = false;
    sceneName = (j['scene'] as String? ?? nextMap.name).replaceAll(
      '\u0000',
      '',
    );
    screenX = j['screenX'] as int? ?? 0;
    screenY = j['screenY'] as int? ?? 0;
    money = (j['money'] as int? ?? 0).clamp(0, 2147483647);
    flags
      ..clear()
      ..addAll(nextFlags);
    variables.setAll(0, rawVars.cast<int>());
    inventory
      ..clear()
      ..addAll(nextInventory);
    npcs
      ..clear()
      ..addAll(nextNpcs);
    fightEnabled = j['fightEnabled'] == true;
    randomMonsters = nextMonsters;
    randomBackground = nextBackground;
    cursor?.timer = j['timer'] as int? ?? 0;
    cursor?.timerCounter = j['timerCounter'] as int? ?? 0;
    cursor?.timerEvent = j['timerEvent'] as int? ?? 0;
    navigation.cancel();
    disableSave = j['disableSave'] == true;
    allowMiss = j['allowMiss'] == true;
    allowTossArm = j['allowTossArm'] != false;
    screen = 'play';
    battle = null;
    operation = null;
    menus.clear();
    route.clear();
    error = '';
    intro = null;
    if (repairKey) notice = '已修复旧版导航进度：补回1把万能钥匙，可继续取得不点卡片';
    render();
  }

  void setPreference(String name, dynamic value) {
    if (!preferences.containsKey(name)) return;
    if (name == 'storyScope' && value != 'main' && value != 'complete') return;
    if (name == 'runSpeed' && (value is! int || value < 1 || value > 4)) return;
    if (name != 'runSpeed' && name != 'storyScope' && value is! bool) return;
    preferences[name] = value;
    if (name == 'wideView') {
      surface = PixelSurface(
        wide ? 320 : 160,
        wide ? 192 : 96,
        textLayout: textLayout,
      );
    }
    render();
    onSaveChanged?.call();
  }
}

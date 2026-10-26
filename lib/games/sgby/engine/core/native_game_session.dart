import 'dart:collection';
import 'dart:typed_data';

import '../../domain/models/game_world.dart';
import '../../domain/models/game_report.dart';
import '../../domain/models/game_battle.dart';
import '../../domain/models/game_options.dart';
import '../../domain/use_cases/game_enhancements.dart';
import '../rendering/baye_canvas.dart';
import '../rendering/game_scene_renderer.dart';
import '../resources/baye_database.dart';
import 'baye_movie_player.dart';

/// 游戏统一输入，方向、键盘、手柄与屏幕按钮共用同一消息入口。
enum NativeInput {
  up,
  down,
  left,
  right,
  confirm,
  cancel,
  pageUp,
  pageDown,
  search,
  help,
}

enum NativeScene {
  intro,
  mainMenu,
  periodMenu,
  rulers,
  credits,
  strategy,
  menu,
  cityInfo,
  miniMap,
  report,
  loadSlots,
  saveSlots,
  number,
  targetCity,
  battle,
  battleSituation,
  processing,
}

enum GameRequestType {
  exitApplication,
  loadSlot,
  saveSlot,
  autoSave,
  cityCommand,
  advanceTurn,
  roster,
  help,
  searchHistory,
}

/// 需要存储或宿主界面协助的命令，领域层不直接持有平台和BuildContext。
final class GameRequest {
  const GameRequest(this.type, {this.index, this.cityIndex, this.world});
  final GameRequestType type;
  final int? index;
  final int? cityIndex;

  /// 自动写盘只接受产生请求的同一局世界，避免读档后旧请求覆盖新进度。
  final GameWorld? world;
}

/// 原资源驱动的游戏会话。输入与逻辑时钟同步串行推进，没有隐藏的Timer。
///
/// 页面负责提供时钟、消费平台请求与提交帧；退出时dispose会清理引用和未消费
/// 命令。菜单回调只捕获本会话，所有界面异步操作在ViewModel层校验代次。
final class NativeGameSession {
  NativeGameSession(
    this.resources, {
    int Function()? seedProvider,
    GameOptions? options,
    List<dynamic>? searchHistory,
  }) : options = options ?? GameOptions(),
       _seedProvider =
           seedProvider ?? (() => DateTime.now().millisecondsSinceEpoch & 255) {
    canvas = BayeCanvas(resources);
    enhancements = GameEnhancements(
      resources,
      this.options,
      history: searchHistory,
    );
    renderer = GameSceneRenderer(resources, canvas);
    _play(3, NativeScene.intro, _showMain);
  }

  final BayeDatabase resources;
  final GameOptions options;
  late final GameEnhancements enhancements;
  GameBattle? activeBattle;
  bool resolvingTurn = false;
  bool mapRoadsVisible = true;
  bool legacySaveLoadEnabled = false;
  void Function(NativeInput)? onBattleInput;
  void Function(int, int)? onBattleTap;
  void Function(int, int)? onBattleSwipe;
  void Function(int)? onAdvance;
  void Function()? onBattleEndTurn;
  void Function()? onBattleRedraw;
  final int Function() _seedProvider;
  late final BayeCanvas canvas;
  late final GameSceneRenderer renderer;
  NativeScene scene = NativeScene.intro;
  GameWorld? world;
  int frameVersion = 0;
  int selection = 0;
  int _rulerTop = 0;
  int _cityTop = 0;
  int? _detailCity;
  bool _disposed = false;
  int _elapsedUs = 0;
  int _currentSpeed = 1;

  /// 当前逻辑倍率，自动按键用它保留原版最短可见间隔。
  int get currentSpeed => _currentSpeed;
  int _lastBlink = 0;
  int _movieWaitUs = 0;
  int _reportWaitUs = 0;
  bool _reportDismissible = true;
  GameReport? _visualReport;
  GameReport? get visualReport =>
      scene == NativeScene.report ? _visualReport : null;
  BayeMoviePlayer? _movie;
  BayeMovieVisual? _lastMovieVisual;

  /// 卡通绘制只读取当前动画信息，不持有播放器或推进领域状态。
  BayeMovieVisual? get movieVisual => _disposed ? null : _movie?.visual;

  /// 伤害数字阶段沿用刚结束的双方兵种与阵营，不退回通用步兵插画。
  BayeMovieVisual? get backdropMovie =>
      _disposed ? null : _movie?.visual ?? _lastMovieVisual;
  void Function()? _afterMovie;
  _GameMenu? _menu;
  Uint8List? _strategyBackground;
  Uint8List? _reportBackground;
  NativeScene? _reportReturn;
  final ListQueue<GameRequest> _requests = ListQueue<GameRequest>();
  _NumberPrompt? _number;
  void Function(int?)? _cityPick;
  List<String?> _slotTitles = List<String?>.filled(4, null);

  bool get isDisposed => _disposed;
  bool get hasWorld => world?.playerRulerIndex != null;
  bool get hasRequests => _requests.isNotEmpty;
  List<int> get rulers =>
      world == null ? const <int>[] : resources.rulers(world!);

  List<GameRequest> takeRequests() {
    final result = _requests.toList(growable: false);
    _requests.clear();
    return result;
  }

  /// 同一帧最多补偿200毫秒，避免后台恢复后一次追赶大量动画阻塞界面。
  void advance(Duration elapsed, {int speed = 1}) {
    if (_disposed) return;
    _currentSpeed = speed.clamp(1, 8);
    final delta = elapsed.inMicroseconds.clamp(0, 200000);
    _elapsedUs += delta * speed.clamp(1, 8);
    _advanceMovie(delta * speed.clamp(1, 8));
    if (scene == NativeScene.report && _reportWaitUs > 0) {
      _reportWaitUs -= delta * speed.clamp(1, 8);
      if (_reportWaitUs <= 0) closeReport();
    }
    if (scene == NativeScene.rulers && _elapsedUs ~/ 500000 != _lastBlink) {
      _lastBlink = _elapsedUs ~/ 500000;
      _drawRulers();
    }
    final menu = _menu;
    if (scene == NativeScene.menu &&
        menu != null &&
        menu.people == null &&
        menu.tools == null &&
        menu.entries.length > menu.rows) {
      menu.blinkElapsed += delta * speed.clamp(1, 8);
      if (menu.blinkElapsed >= 50000) {
        final toggles = menu.blinkElapsed ~/ 50000;
        menu.blinkElapsed %= 50000;
        if (toggles.isOdd) {
          menu.scrollBlink = !menu.scrollBlink;
          _drawMenu();
        }
      }
    }
    onAdvance?.call(delta * speed.clamp(1, 8));
  }

  void _play(int resourceId, NativeScene target, void Function() after) {
    scene = target;
    canvas.clear();
    final animation = resources.animation(resourceId);
    _afterMovie = after;
    _movieWaitUs = 0;
    _movie = animation == null
        ? null
        : BayeMoviePlayer(animation, resourceId: resourceId);
    if (_movie == null) {
      _afterMovie = null;
      after();
    } else {
      _advanceMovie(0);
    }
  }

  void _advanceMovie(int budget) {
    if (_movie == null) return;
    _movieWaitUs -= budget;
    var operations = 0;
    while (_movieWaitUs <= 0 && _movie != null && operations++ < 2048) {
      final movie = _movie!;
      final result = movie.step(canvas);
      _lastMovieVisual = movie.visual;
      if (result.$1) frameVersion++;
      if (movie.finished) {
        _movie = null;
        final callback = _afterMovie;
        _afterMovie = null;
        callback?.call();
        break;
      }
      _movieWaitUs += result.$2;
    }
  }

  void _showMain() {
    _menu = null;
    _movie = null;
    _afterMovie = null;
    world = null;
    scene = NativeScene.mainMenu;
    selection = 0;
    _drawPictureMenu();
  }

  void _drawPictureMenu() {
    if (scene == NativeScene.mainMenu) {
      renderer.mainMenu();
    } else {
      renderer.periodMenu();
    }
    final animation = resources.animation(
      (scene == NativeScene.mainMenu ? 100 : 104) + selection,
    );
    final menuScene = scene, menuSelection = selection;
    void replay() {
      if (_disposed ||
          scene != menuScene ||
          selection != menuSelection ||
          animation == null) {
        return;
      }
      _movie = BayeMoviePlayer(
        animation,
        resourceId:
            (menuScene == NativeScene.mainMenu ? 100 : 104) + menuSelection,
      );
      _movieWaitUs = 0;
      _afterMovie = replay;
    }

    _movie = null;
    _afterMovie = null;
    replay();
    _movieWaitUs = 0;
    frameVersion++;
    _advanceMovie(0);
  }

  void _drawRulers() {
    final data = world;
    if (data == null) return;
    renderer.rulerSelection(
      data,
      rulers,
      selection,
      _rulerTop,
      blink: _lastBlink.isOdd,
    );
    frameVersion++;
  }

  void showStrategy({bool resetRoads = true}) {
    if (_disposed || !hasWorld) return;
    if (resetRoads) mapRoadsVisible = true;
    _movie = null;
    _afterMovie = null;
    _menu = null;
    _number = null;
    _cityPick = null;
    scene = NativeScene.strategy;
    renderer.strategy(world!);
    _strategyBackground = canvas.snapshot();
    frameVersion++;
  }

  /// GameDevDrv在玩家阶段开始前检测结局，提示结束后回到主菜单。
  bool checkGameOver() {
    final data = world, ruler = world?.playerRulerIndex;
    if (data == null || ruler == null) return false;
    final lost = data.citiesOf(ruler).isEmpty;
    final won = data.cities.every(
      (city) => city.belong == 0 || city.belong == ruler + 1,
    );
    if (!lost && !won) return false;
    resolvingTurn = false;
    showReport(resources.text(64, lost ? 89 : 90));
    _afterReport = () {
      activeBattle = null;
      _strategyBackground = null;
      _requests.clear();
      _showMain();
    };
    return true;
  }

  /// ShowMapClear还原上一张战略底图。选择器不因世界数据刚刚改变而重绘侧栏。
  void showMapClear() {
    final background = _strategyBackground;
    if (background == null) {
      showStrategy();
      return;
    }
    _movie = null;
    _afterMovie = null;
    _menu = null;
    _number = null;
    _cityPick = null;
    canvas.restore(background);
    scene = NativeScene.strategy;
    frameVersion++;
  }

  /// 载入成功后替换整个世界，避免旧菜单和动画继续持有被替换的数据。
  void replaceWorld(GameWorld replacement) {
    if (_disposed || replacement.playerRulerIndex == null) return;
    if (legacySaveLoadEnabled) {
      replacement.random.restore(world?.random.state ?? _seedProvider());
    }
    world = replacement;
    _requests.clear();
    final synchronized = enhancements.synchronizeWorld(replacement);
    activeBattle = null;
    resolvingTurn = false;
    _lastMovieVisual = null;
    onBattleInput = null;
    onBattleTap = null;
    onBattleSwipe = null;
    onAdvance = null;
    onBattleEndTurn = null;
    onBattleRedraw = null;
    showStrategy();
    if (!checkGameOver() && !synchronized.isSuccess) {
      showReport(synchronized.message);
    }
  }

  void setSlotTitles(List<String?> values) {
    if (_disposed) return;
    _slotTitles = List<String?>.generate(
      4,
      (i) => i < values.length ? values[i] : null,
    );
    if (scene == NativeScene.loadSlots || scene == NativeScene.saveSlots) {
      _drawSlotFrame();
      frameVersion++;
    }
  }

  int get _slotCount => scene == NativeScene.loadSlots ? 4 : 3;
  void _drawSlotFrame() => renderer.saveSlots(
    _slotTitles.take(_slotCount).toList(growable: false),
    selection,
  );

  void openSaveMenu() {
    if (_disposed || !hasWorld) return;
    _menu = null;
    _movie = null;
    _afterMovie = null;
    scene = NativeScene.saveSlots;
    selection = 0;
    _drawSlotFrame();
    frameVersion++;
  }

  void input(NativeInput input) {
    if (_disposed) return;
    if (scene == NativeScene.processing) return;
    if (scene == NativeScene.intro || scene == NativeScene.credits) {
      _movie = null;
      _afterMovie = null;
      _showMain();
      return;
    }
    _movie = null;
    _afterMovie = null;
    switch (scene) {
      case NativeScene.mainMenu:
      case NativeScene.periodMenu:
        _pictureInput(input);
      case NativeScene.rulers:
        _rulerInput(input);
      case NativeScene.strategy:
      case NativeScene.targetCity:
        _strategyInput(input);
      case NativeScene.number:
        _numberInput(input);
      case NativeScene.battle:
      case NativeScene.battleSituation:
        onBattleInput?.call(input);
      case NativeScene.processing:
        break;
      case NativeScene.menu:
        _menuInput(input);
      case NativeScene.cityInfo:
        if (input == NativeInput.confirm || input == NativeInput.cancel) {
          showStrategy();
        } else {
          if (input == NativeInput.down ||
              input == NativeInput.right ||
              input == NativeInput.pageDown) {
            _cityTop = 9;
          } else if (input == NativeInput.up ||
              input == NativeInput.left ||
              input == NativeInput.pageUp) {
            _cityTop = 0;
          }
          final data = world;
          final city = _detailCity;
          if (data != null && city != null) {
            renderer.strategy(data);
            renderer.cityDetails(data, city, _cityTop);
            frameVersion++;
          }
        }
      case NativeScene.miniMap:
        showStrategy();
      case NativeScene.report:
        if (_reportDismissible) closeReport();
      case NativeScene.loadSlots:
      case NativeScene.saveSlots:
        if (input == NativeInput.cancel) {
          if (hasWorld) {
            showStrategy();
          } else {
            _showMain();
          }
        } else if (input == NativeInput.confirm) {
          _requests.add(
            GameRequest(
              scene == NativeScene.loadSlots
                  ? GameRequestType.loadSlot
                  : GameRequestType.saveSlot,
              index: selection,
            ),
          );
        } else if (input == NativeInput.up || input == NativeInput.down) {
          selection =
              (selection + (input == NativeInput.up ? _slotCount - 1 : 1)) %
              _slotCount;
          _drawSlotFrame();
          frameVersion++;
        }
      case NativeScene.intro:
      case NativeScene.credits:
        break;
    }
  }

  void _pictureInput(NativeInput input) {
    if (input == NativeInput.cancel) {
      _showMain();
      return;
    }
    if (input == NativeInput.up ||
        input == NativeInput.left ||
        input == NativeInput.down ||
        input == NativeInput.right) {
      selection =
          (selection +
              (input == NativeInput.up || input == NativeInput.left ? 3 : 1)) %
          4;
      _drawPictureMenu();
      return;
    }
    if (input != NativeInput.confirm) return;
    if (scene == NativeScene.periodMenu) {
      world = resources.loadPeriod(selection + 1, seed: _seedProvider());
      scene = NativeScene.rulers;
      selection = 0;
      _rulerTop = 0;
      _drawRulers();
      return;
    }
    switch (selection) {
      case 0:
        scene = NativeScene.periodMenu;
        selection = 0;
        _drawPictureMenu();
      case 1:
        scene = NativeScene.loadSlots;
        selection = 0;
        _drawSlotFrame();
        frameVersion++;
      case 2:
        _play(6, NativeScene.credits, _showMain);
      case 3:
        _requests.add(const GameRequest(GameRequestType.exitApplication));
    }
  }

  void _rulerInput(NativeInput input) {
    final data = world;
    final choices = rulers;
    if (data == null || choices.isEmpty) {
      _showMain();
      return;
    }
    if (input == NativeInput.cancel) {
      scene = NativeScene.periodMenu;
      selection = 0;
      _drawPictureMenu();
      return;
    }
    if (input == NativeInput.confirm) {
      resources.beginGame(data, choices[selection]);
      resources.assignSatraps(data);
      final synchronized = enhancements.synchronizeWorld(data);
      showStrategy();
      if (!synchronized.isSuccess) showReport(synchronized.message);
      return;
    }
    final step = input == NativeInput.pageUp || input == NativeInput.pageDown
        ? 10
        : 1;
    if (input == NativeInput.up ||
        input == NativeInput.left ||
        input == NativeInput.pageUp) {
      selection = (selection - step).clamp(0, choices.length - 1);
    } else if (input == NativeInput.down ||
        input == NativeInput.right ||
        input == NativeInput.pageDown) {
      selection = (selection + step).clamp(0, choices.length - 1);
    }
    if (selection < _rulerTop) _rulerTop = selection;
    if (selection >= _rulerTop + 10) _rulerTop = selection - 9;
    _drawRulers();
  }

  void _strategyInput(NativeInput input) {
    final data = world;
    if (data == null) return;
    if (input == NativeInput.cancel) {
      final pick = _cityPick;
      if (pick != null) {
        _cityPick = null;
        showStrategy();
        pick(null);
        return;
      }
      _openSystemMenu();
      return;
    }
    if (input == NativeInput.search) {
      scene = NativeScene.miniMap;
      renderer.miniMap();
      frameVersion++;
      return;
    }
    if (input == NativeInput.help) {
      _requests.add(const GameRequest(GameRequestType.help));
      return;
    }
    if (input == NativeInput.confirm) {
      _selectCity();
      return;
    }
    if (input == NativeInput.left) {
      data.cursorX = (data.cursorX - 1).clamp(0, resources.mapWidth - 1);
    }
    if (input == NativeInput.right) {
      data.cursorX = (data.cursorX + 1).clamp(0, resources.mapWidth - 1);
    }
    if (input == NativeInput.up) {
      data.cursorY = (data.cursorY - 1).clamp(0, resources.mapHeight - 1);
    }
    if (input == NativeInput.down) {
      data.cursorY = (data.cursorY + 1).clamp(0, resources.mapHeight - 1);
    }
    if (_cityPick != null) {
      renderer.strategy(data);
      frameVersion++;
    } else {
      showStrategy(resetRoads: false);
    }
  }

  void _selectCity() {
    final data = world;
    if (data == null) return;
    final cityIndex = renderer.selectedCity(data);
    if (cityIndex == null) return;
    final callback = _cityPick;
    if (callback != null) {
      _cityPick = null;
      callback(cityIndex);
      return;
    }
    final city = data.city(cityIndex);
    if (city == null) return;
    if (city.belong != (data.playerRulerIndex ?? -1) + 1) {
      showReport(resources.text(64, city.belong > 0 ? 54 : 56));
      return;
    }
    _openCityMenu(cityIndex);
  }

  void showCityInfo(int cityIndex) {
    final data = world;
    if (_disposed || data?.city(cityIndex) == null) return;
    _detailCity = cityIndex;
    _cityTop = 0;
    _menu = null;
    scene = NativeScene.cityInfo;
    renderer.strategy(data!);
    renderer.cityDetails(data, cityIndex, 0);
    frameVersion++;
  }

  void _openCityMenu(int cityIndex) {
    showStrategy();
    _openMenu(
      _splitMenu(37, 2),
      x: 79,
      y: 10,
      columns: 4,
      rows: 4,
      onCancel: showStrategy,
      onChoose: (category) {
        if (category == 3) {
          showCityInfo(cityIndex);
          return;
        }
        _openCitySubmenu(cityIndex, category);
      },
    );
  }

  void _openCitySubmenu(int cityIndex, int category) {
    final parent = _menu;
    if (parent == null) return;
    final entries = _splitMenu(38 + category, 2);
    _openMenu(
      entries,
      x: 119,
      y: 14 + category * 12,
      columns: 4,
      rows: (entries.length).clamp(1, category == 0 ? 10 : entries.length),
      onCancel: () {
        _menu = parent;
        scene = NativeScene.menu;
        _drawMenu();
      },
      onChoose: (index) {
        final command =
            (category == 0
                ? 1
                : category == 1
                ? 15
                : 23) +
            index;
        _requests.add(
          GameRequest(
            GameRequestType.cityCommand,
            index: command,
            cityIndex: cityIndex,
          ),
        );
      },
    );
  }

  void _openSystemMenu() {
    _openMenu(
      _splitMenu(121, 4),
      x: 79,
      y: 10,
      columns: 8,
      rows: 3,
      onCancel: showStrategy,
      onChoose: (index) {
        if (index == 0) {
          _requests.add(GameRequest(GameRequestType.advanceTurn, world: world));
        }
        if (index == 1) openSaveMenu();
        if (index == 2) {
          _openMenu(
            ['确定退出'],
            x: 79,
            y: 58,
            columns: 8,
            rows: 1,
            onChoose: (_) => _showMain(),
            onCancel: showStrategy,
          );
        }
      },
    );
  }

  List<String> _splitMenu(int item, int characters) {
    final source = resources.text(64, item);
    return <String>[
      for (var i = 0; i < source.length; i += characters)
        source.substring(i, (i + characters).clamp(0, source.length)),
    ];
  }

  void _openMenu(
    List<String> entries, {
    required int x,
    required int y,
    required int columns,
    required int rows,
    required void Function(int) onChoose,
    required void Function() onCancel,
    void Function(int)? onHighlight,
    int initialSelection = 0,
    int? pixelWidth,
  }) {
    _movie = null;
    _afterMovie = null;
    _menu = _GameMenu(
      entries,
      x,
      y,
      columns,
      rows,
      canvas.snapshot(),
      onChoose,
      onCancel,
      onHighlight: onHighlight,
      pixelWidth: pixelWidth,
    );
    _menu!.selected = initialSelection.clamp(0, entries.length - 1);
    _menu!.top = entries.length > rows
        ? _menu!.selected.clamp(0, entries.length - rows)
        : 0;
    scene = NativeScene.menu;
    _drawMenu();
  }

  void _drawMenu() {
    final menu = _menu;
    if (menu == null) return;
    canvas.restore(menu.background);
    menu.onHighlight?.call(menu.selected);
    final people = menu.people;
    final data = world;
    final tools = menu.tools;
    if (tools != null && data != null) {
      menu.nextColumn = renderer.goodsSelection(
        data,
        tools,
        menu.selected,
        menu.top,
        menu.column,
      );
      frameVersion++;
      return;
    }
    if (people != null && data != null) {
      menu.nextColumn = renderer.peopleSelection(
        data,
        people,
        menu.selected,
        menu.top,
        menu.column,
      );
      frameVersion++;
      return;
    }
    canvas.menu(
      menu.entries,
      menu.selected,
      x: menu.x,
      y: menu.y,
      columns: menu.columns,
      rows: menu.rows,
      topIndex: menu.top,
      pixelWidth: menu.pixelWidth,
      scrollBlink: menu.scrollBlink,
    );
    frameVersion++;
  }

  void _menuInput(NativeInput input) {
    final menu = _menu;
    if (menu == null) {
      showStrategy();
      return;
    }
    if (input == NativeInput.cancel) {
      menu.onCancel();
      return;
    }
    if (input == NativeInput.confirm) {
      menu.onChoose(menu.selected);
      return;
    }
    if ((menu.people != null || menu.tools != null) &&
        (input == NativeInput.left || input == NativeInput.right)) {
      if (input == NativeInput.right &&
          menu.nextColumn < (menu.tools == null ? 13 : 5)) {
        menu.columnsHistory.add(menu.column);
        menu.column = menu.nextColumn;
      } else if (input == NativeInput.left && menu.columnsHistory.isNotEmpty) {
        menu.column = menu.columnsHistory.removeLast();
      }
      _drawMenu();
      return;
    }
    final delta =
        input == NativeInput.up ||
            input == NativeInput.left ||
            input == NativeInput.pageUp
        ? -1
        : input == NativeInput.down ||
              input == NativeInput.right ||
              input == NativeInput.pageDown
        ? 1
        : 0;
    // 原版上下键在首尾循环；clamp会把第一项的上键吞掉。属性表左右键已在
    // 上方单独处理，因此此处不会把横向翻页误当成首尾选择。
    menu.selected = (menu.selected + delta) % menu.entries.length;
    if (menu.selected < menu.top) menu.top = menu.selected;
    if (menu.selected >= menu.top + menu.rows) {
      menu.top = menu.selected - menu.rows + 1;
    }
    _drawMenu();
  }

  /// 接收已经映射到原版逻辑画布的点击，不把手机像素直接当成游戏坐标。
  void tap(int x, int y) {
    if (_disposed ||
        x < 0 ||
        y < 0 ||
        x >= canvas.width ||
        y >= canvas.height) {
      return;
    }
    mapRoadsVisible = false;
    if (scene == NativeScene.battle || scene == NativeScene.battleSituation) {
      onBattleTap?.call(x, y);
      return;
    }
    if (scene == NativeScene.mainMenu || scene == NativeScene.periodMenu) {
      final rectangles = resources.ruleArray(
        scene == NativeScene.mainMenu
            ? 'mainMenuButtonRects'
            : 'periodMenuButtonRects',
      );
      for (var i = 0; i + 3 < rectangles.length; i += 4) {
        if (x >= rectangles[i] &&
            x <= rectangles[i + 2] &&
            y >= rectangles[i + 1] &&
            y <= rectangles[i + 3]) {
          selection = i ~/ 4;
          input(NativeInput.confirm);
          return;
        }
      }
      if (scene == NativeScene.periodMenu) input(NativeInput.cancel);
    } else if (scene == NativeScene.rulers) {
      if (x >= canvas.width - 28 && y <= 15) {
        input(NativeInput.cancel);
        return;
      }
      if (x >= 13 && x <= 53 && y >= 13 && y < 133) {
        final index = _rulerTop + (y - 13) ~/ 12;
        if (index < rulers.length) {
          if (index == selection) {
            input(NativeInput.confirm);
          } else {
            selection = index;
            _drawRulers();
          }
        }
      }
    } else if (scene == NativeScene.strategy ||
        scene == NativeScene.targetCity) {
      final data = world;
      if (data == null) return;
      final mapX = data.viewX + x ~/ 16;
      final mapY = data.viewY + y ~/ 16;
      if (mapX >= resources.mapWidth || mapY >= resources.mapHeight) return;
      if (data.cursorX == mapX && data.cursorY == mapY) {
        _selectCity();
      } else {
        data.cursorX = mapX;
        data.cursorY = mapY;
        if (_cityPick != null) {
          renderer.strategy(data);
          frameVersion++;
        } else {
          showStrategy();
        }
      }
    } else if (scene == NativeScene.menu) {
      final menu = _menu;
      if (menu == null) return;
      if (menu.people != null || menu.tools != null) {
        final row = (y - 15) ~/ 12;
        final index = menu.top + row;
        if (x < 4 ||
            x > (menu.tools == null ? 51 : 63) ||
            y < 15 ||
            row >= menu.rows ||
            index >= menu.entries.length) {
          menu.onCancel();
          return;
        }
        menu.selected = index;
        menu.onChoose(index);
        return;
      }
      if (x < menu.x - 3 ||
          x > menu.x + (menu.pixelWidth ?? menu.columns * 6) + 2 ||
          y < menu.y - 3 ||
          y > menu.y + menu.rows * 12 + 2) {
        menu.onCancel();
        return;
      }
      final row = (y - menu.y) ~/ 12;
      final index = menu.top + row;
      if (row < 0 || index >= menu.entries.length) return;
      if (index == menu.selected) {
        menu.onChoose(index);
      } else {
        menu.selected = index;
        _drawMenu();
      }
    } else if (scene == NativeScene.loadSlots ||
        scene == NativeScene.saveSlots) {
      final anchor = resources.ruleArray('saveFaceListAnchor');
      final ax = anchor.length >= 2 ? anchor[0] : 31;
      final ay = anchor.length >= 2 ? anchor[1] : 33;
      if (x >= ax && x <= ax + 95 && y >= ay && y < ay + _slotCount * 14) {
        final index = (y - ay) ~/ 14;
        if (selection == index) {
          input(NativeInput.confirm);
        } else {
          selection = index;
          _drawSlotFrame();
          frameVersion++;
        }
      } else {
        input(NativeInput.cancel);
      }
    } else if (scene == NativeScene.number) {
      final prompt = _number;
      if (prompt == null) return;
      final left = (canvas.width - 1 - 72) ~/ 2;
      final top = (canvas.height - 1 - 36) ~/ 2;
      if (y >= top + 39 && y <= top + 52) {
        if (x >= left - 10 && x < left + 20) {
          _numberInput(NativeInput.confirm);
        } else if (x >= left + 21 && x < left + 51) {
          _numberInput(NativeInput.help);
        } else if (x >= left + 52 && x < left + 82) {
          _numberInput(NativeInput.cancel);
        }
      } else if (y >= top + 12 && y <= top + 24) {
        prompt.digit = ((x - left - 42) ~/ 6).clamp(
          0,
          prompt.maximum.toString().length - 1,
        );
        _drawNumber();
      }
    } else {
      input(NativeInput.confirm);
    }
  }

  /// 手势位移使用游戏逻辑坐标；横向拖动属性表翻页，战场拖动只移动视口。
  void swipe(int deltaY, {int deltaX = 0}) {
    if (_disposed || (deltaY.abs() < 12 && deltaX.abs() < 12)) return;
    if (scene == NativeScene.battle || scene == NativeScene.battleSituation) {
      onBattleSwipe?.call(deltaX, deltaY);
    } else if (scene == NativeScene.rulers) {
      final lastTop = (rulers.length - 10).clamp(0, rulers.length);
      _rulerTop = (_rulerTop - deltaY ~/ 12).clamp(0, lastTop);
      _drawRulers();
    } else if (scene == NativeScene.cityInfo || scene == NativeScene.menu) {
      if (deltaX.abs() > deltaY.abs()) {
        input(deltaX < 0 ? NativeInput.right : NativeInput.left);
      } else {
        input(deltaY < 0 ? NativeInput.down : NativeInput.up);
      }
    }
  }

  bool longPress(int x, int y) {
    if (_disposed || scene != NativeScene.strategy) return false;
    final data = world;
    if (data == null) return false;
    final mx = data.viewX + x ~/ 16;
    final my = data.viewY + y ~/ 16;
    if (mx >= resources.mapWidth ||
        my >= resources.mapHeight ||
        mx < 0 ||
        my < 0) {
      return false;
    }
    final city = resources.constant(14)[my * resources.mapWidth + mx] - 1;
    final selected = data.city(city);
    if (selected != null &&
        selected.belong != 0 &&
        selected.belong != (data.playerRulerIndex ?? -1) + 1) {
      _requests.add(GameRequest(GameRequestType.roster, cityIndex: city));
      return true;
    }
    return false;
  }

  void showReport(
    String value, {
    int? person,
    int delayMilliseconds = 2000,
    GameReportKind kind = GameReportKind.text,
    int? actor,
    int? target,
    int? city,
  }) {
    if (_disposed) return;
    _visualReport = GameReport(
      value,
      person: person,
      kind: kind,
      actor: actor,
      target: target,
      city: city,
    );
    if (scene != NativeScene.report) {
      _reportReturn = scene;
      _reportBackground = canvas.snapshot();
    }
    _movie = null;
    _afterMovie = null;
    scene = NativeScene.report;
    _reportWaitUs = delayMilliseconds * 1000;
    _reportDismissible =
        kind == GameReportKind.text ||
        kind == GameReportKind.graphic ||
        kind != GameReportKind.attack &&
            resources.rule('responseNoteOfBettle') != 0;
    final data = world;
    if (kind == GameReportKind.graphic) {
      canvas.graphicMessage(value);
    } else if (kind != GameReportKind.text && data != null) {
      renderer.battleNote(data, kind, actor, target);
    } else if (person != null && data != null && data.person(person) != null) {
      renderer.generalReport(data, person, value);
    } else {
      renderer.report(value);
    }
    frameVersion++;
  }

  void closeReport() {
    final background = _reportBackground;
    if (_disposed || background == null) return;
    canvas.restore(background);
    scene = _reportReturn ?? NativeScene.strategy;
    _reportBackground = null;
    _reportReturn = null;
    _reportWaitUs = 0;
    _visualReport = null;
    frameVersion++;
    final callback = _afterReport;
    _afterReport = null;
    callback?.call();
  }

  void dispose() {
    _disposed = true;
    _lastMovieVisual = null;
    _visualReport = null;
    _movie = null;
    _afterMovie = null;
    _menu = null;
    _requests.clear();
    _reportBackground = null;
    world = null;
    _strategyBackground = null;
    _number = null;
    _cityPick = null;
    _afterReport = null;
    onBattleInput = null;
    onBattleTap = null;
    onBattleSwipe = null;
    onAdvance = null;
    onBattleEndTurn = null;
    onBattleRedraw = null;
    activeBattle = null;
  }

  /// 命令流程的原版武将选择器；取消返回空值，调用方决定回到哪个选择阶段。
  void choosePeople(
    List<int> ids,
    void Function(int?) selected, {
    int selectedIndex = 0,
  }) {
    if (_disposed || ids.isEmpty) {
      selected(null);
      return;
    }
    showMapClear();
    _openMenu(
      [for (final id in ids) resources.personName(world!.period, id)],
      x: 4,
      y: 2,
      columns: 38,
      rows: ((canvas.height - 5) ~/ 12 - 1).clamp(1, ids.length),
      onChoose: (index) => selected(ids[index]),
      onCancel: () => selected(null),
      initialSelection: selectedIndex,
    );
    _menu?.people = List<int>.of(ids);
    _drawMenu();
  }

  /// 道具属性表与武将选择表共用输入和翻页状态，回调返回列表中的序号。
  void chooseTools(
    List<int> ids,
    void Function(int?) selected, {
    int selectedIndex = 0,
  }) {
    if (_disposed || ids.isEmpty) {
      selected(null);
      return;
    }
    showMapClear();
    _openMenu(
      [for (final id in ids) resources.toolName(id)],
      x: 4,
      y: 2,
      columns: 38,
      rows: ((canvas.height - 5) ~/ 12 - 1).clamp(1, ids.length),
      onChoose: selected,
      onCancel: () => selected(null),
      initialSelection: selectedIndex,
    );
    _menu?.tools = List<int>.of(ids);
    _drawMenu();
  }

  void chooseOptions(List<String> entries, void Function(int?) selected) {
    if (_disposed || entries.isEmpty) {
      selected(null);
      return;
    }
    showStrategy();
    _openMenu(
      entries,
      x: 119,
      y: 14,
      columns: 12,
      rows: entries.length.clamp(1, 9),
      onChoose: selected,
      onCancel: () => selected(null),
    );
  }

  void chooseCity(void Function(int?) selected) {
    if (_disposed || world == null) {
      selected(null);
      return;
    }
    showStrategy();
    _cityPick = selected;
    scene = NativeScene.targetCity;
  }

  void chooseNumber(
    String title,
    int minimum,
    int maximum,
    void Function(int?) selected, {
    int? initial,
  }) {
    if (_disposed || maximum < minimum) {
      selected(null);
      return;
    }
    _number = _NumberPrompt(
      title,
      minimum,
      maximum,
      (initial ?? maximum).clamp(minimum, maximum),
      maximum.toString().length - 1,
      canvas.snapshot(),
      selected,
    );
    scene = NativeScene.number;
    _drawNumber();
  }

  void _drawNumber() {
    final prompt = _number;
    if (prompt == null) return;
    canvas.restore(prompt.background);
    renderer.number(
      prompt.title,
      prompt.minimum,
      prompt.maximum,
      prompt.value,
      prompt.digit,
    );
    frameVersion++;
  }

  void _numberInput(NativeInput input) {
    final prompt = _number;
    if (prompt == null) return;
    if (input == NativeInput.confirm || input == NativeInput.cancel) {
      _number = null;
      prompt.selected(input == NativeInput.confirm ? prompt.value : null);
      return;
    }
    final digits = prompt.maximum.toString().length;
    if (input == NativeInput.left) {
      prompt.digit = (prompt.digit - 1).clamp(0, digits - 1);
    }
    if (input == NativeInput.right) {
      prompt.digit = (prompt.digit + 1).clamp(0, digits - 1);
    }
    var step = 1;
    for (var i = prompt.digit + 1; i < digits; i++) {
      step *= 10;
    }
    if (input == NativeInput.up && prompt.value + step <= prompt.maximum) {
      prompt.value += step;
    }
    if (input == NativeInput.down && prompt.value - step >= prompt.minimum) {
      prompt.value -= step;
    }
    if (input == NativeInput.help) {
      prompt.value = prompt.value == prompt.maximum
          ? prompt.minimum
          : prompt.maximum;
    }
    _drawNumber();
  }

  void displayReports(List<GameReport> reports, {void Function()? completed}) {
    if (_disposed) return;
    // 报告仍走当前统一画布，完成回调仅由本会话持有。
    if (reports.isEmpty) {
      completed?.call();
      return;
    }
    showReport(
      reports.first.text,
      person: reports.first.person,
      delayMilliseconds: reports.first.kind == GameReportKind.attack
          ? 1000
          : reports.first.kind == GameReportKind.graphic
          ? 1000
          : reports.first.kind != GameReportKind.text ||
                reports.first.person != null
          ? 3000
          : 2000,
      kind: reports.first.kind,
      actor: reports.first.actor,
      target: reports.first.target,
      city: reports.first.city,
    );
    _afterReport = () => displayReports(
      reports.skip(1).toList(growable: false),
      completed: completed,
    );
  }

  void Function()? _afterReport;

  /// 原画布内的说明与形势图弹层。销毁会话后不保留背景或完成回调。
  void showCanvasReport(
    void Function() paint, {
    void Function()? completed,
    int delayMilliseconds = 0,
    bool dismissible = true,
  }) {
    if (_disposed) return;
    if (scene != NativeScene.report) {
      _reportReturn = scene;
      _reportBackground = canvas.snapshot();
    }
    _movie = null;
    _afterMovie = null;
    _reportWaitUs = delayMilliseconds * 1000;
    _reportDismissible = dismissible;
    scene = NativeScene.report;
    paint();
    _afterReport = completed;
    frameVersion++;
  }

  /// 战场菜单复用原版矩形菜单，背景由调用者先画好，不切回战略地图。
  void canvasMenu(
    List<String> entries,
    void Function(int?) selected, {
    int x = 8,
    int y = 8,
    int columns = 8,
    void Function(int)? onHighlight,
    int initialSelection = 0,
    int? pixelWidth,
  }) {
    if (_disposed || entries.isEmpty) return;
    _openMenu(
      entries,
      x: x,
      y: y,
      columns: columns,
      rows: entries.length.clamp(1, 9),
      onChoose: selected,
      onCancel: () => selected(null),
      onHighlight: onHighlight,
      initialSelection: initialSelection,
      pixelWidth: pixelWidth,
    );
  }

  /// 由游戏流程提交现有帧，不把Flutter绘制对象传入领域逻辑。
  void submitScene(NativeScene value) {
    if (!_disposed) {
      scene = value;
      frameVersion++;
    }
  }

  void requestAdvanceTurn() {
    if (!_disposed && !resolvingTurn && scene == NativeScene.strategy) {
      _requests.add(GameRequest(GameRequestType.advanceTurn, world: world));
    }
  }

  /// 本月所有报告和战后处理完成后，再排入自动存档与下一回合，保持FIFO顺序。
  void completeStrategyTurn() {
    final data = world;
    if (_disposed ||
        data == null ||
        resolvingTurn ||
        activeBattle != null ||
        scene != NativeScene.strategy) {
      return;
    }
    if (options.enabled('autoSaveAfterTurn')) {
      _requests.add(
        GameRequest(GameRequestType.autoSave, index: 0, world: data),
      );
    }
    if (options.enabled('autoEndTurn')) requestAdvanceTurn();
  }

  /// 播放原资源动画片段；完成回调与逻辑时钟同属本会话，dispose后不再触发。
  void playMovie(
    int resource, {
    required int first,
    required int last,
    required int x,
    required int y,
    required void Function() completed,
    String visualLabel = '',
    int? sourceType,
    int? targetType,
    bool sourceFriendly = true,
    bool targetFriendly = false,
    String visualEffect = '',
  }) {
    final animation = resources.animation(resource);
    if (_disposed) return;
    if (animation == null) {
      completed();
      return;
    }
    _movie = BayeMoviePlayer(
      animation,
      first: first,
      last: last,
      x: x,
      y: y,
      resourceId: resource,
      label: visualLabel,
      sourceType: sourceType,
      targetType: targetType,
      sourceFriendly: sourceFriendly,
      targetFriendly: targetFriendly,
      effect: visualEffect,
    );
    _lastMovieVisual = _movie?.visual;
    _movieWaitUs = 0;
    _afterMovie = completed;
    scene = NativeScene.processing;
    _advanceMovie(0);
  }
}

/// 当前菜单独占的状态，包含进入前的画面快照，关闭后整块释放。
final class _GameMenu {
  _GameMenu(
    this.entries,
    this.x,
    this.y,
    this.columns,
    this.rows,
    this.background,
    this.onChoose,
    this.onCancel, {
    this.onHighlight,
    this.pixelWidth,
  });
  final List<String> entries;
  final int x;
  final int y;
  final int columns;
  final int? pixelWidth;
  bool scrollBlink = false;
  int blinkElapsed = 0;
  final int rows;
  final Uint8List background;
  final void Function(int) onChoose;
  final void Function() onCancel;
  final void Function(int)? onHighlight;
  int selected = 0;
  int top = 0;
  List<int>? people;
  List<int>? tools;
  int column = 0;
  int nextColumn = 0;
  final List<int> columnsHistory = <int>[];
}

/// 数量选择保留光标位数，防止一次上下按键总是只修改个位。
final class _NumberPrompt {
  _NumberPrompt(
    this.title,
    this.minimum,
    this.maximum,
    this.value,
    this.digit,
    this.background,
    this.selected,
  );
  final String title;
  final int minimum;
  final int maximum;
  int value;
  int digit;
  final Uint8List background;
  final void Function(int?) selected;
}

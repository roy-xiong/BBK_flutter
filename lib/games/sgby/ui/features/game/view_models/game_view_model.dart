import 'dart:async';
import 'dart:collection';
import 'dart:ui' show AppLifecycleState;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../../../data/repositories/game_asset_repository.dart';
import '../../../../data/repositories/game_save_repository.dart';
import '../../../../data/services/game_platform_service.dart';
import '../../../../domain/models/game_definition.dart';
import '../../../../domain/models/general_roster.dart';
import '../../../../domain/models/sgby_battle_statistics.dart';
import '../../../../domain/use_cases/build_general_roster.dart';
import '../../../../engine/core/native_game_session.dart';
import '../../../../engine/core/strategy_command_flow.dart';
import '../../../../engine/core/strategy_turn_flow.dart';
import '../../../../engine/core/refined_help_flow.dart';
import '../../../../domain/models/game_options.dart';
import '../../../../domain/models/keyboard_bindings.dart';
import '../../../core/game_keyboard.dart';
import '../../../../domain/models/search_history.dart';
import '../../../../domain/models/enemy_city.dart';
import '../../../../domain/use_cases/strategy_commands.dart';
import 'game_frame_presenter.dart';
import '../../../../engine/rendering/game_display_enhancements.dart';
import '../../../../engine/rendering/cartoon_assets.dart';

export '../../../../domain/models/general_roster.dart';
export '../../../../domain/models/search_history.dart';
export '../../../../domain/models/enemy_city.dart';

/// 页面会话协调者。异步资源与存档操作校验代次，UI只在本isolate通知更新。
///
/// 原版引擎状态、Flutter图片和平台操作各有独立所有者。后台或弹出查询面板时
/// 停止逻辑时钟；销毁时清理回调、图片与会话，不让迟到的读取结果复活旧页面。
final class GameViewModel extends ChangeNotifier {
  GameViewModel({
    GameAssetRepository? assets,
    GameSaveRepository? saves,
    this.onExitRequested,
  }) : _assets = assets ?? GameAssetRepository(),
       _saves = saves ?? GameSaveRepository();

  /// 合集接管原版退出请求，避免关闭整个应用。
  final Future<void> Function()? onExitRequested;

  final GameAssetRepository _assets;
  final GameSaveRepository _saves;
  final GamePlatformService _platform = GamePlatformService();
  NativeGameSession? _session;
  GameFramePresenter? _frames;
  GameDisplayEnhancements? _display;
  CartoonAssets? _cartoonAssets;
  bool _artLoading = false;
  int _artToken = 0;
  Future<void>? _artTask;
  Future<void> get cartoonArtReady => _artTask ?? Future<void>.value();
  CartoonAssets? get cartoonAssets => _cartoonAssets;
  final ListQueue<GameRequest> _requests = ListQueue<GameRequest>();
  bool _disposed = false;
  Future<void>? _initializationTask;
  bool _foreground = true;
  bool _visible = true;
  bool _attached = true;
  bool _busy = false;
  bool _processing = false;
  bool _savingSettings = false;
  int _uiPauseDepth = 0;
  int _generation = 0;
  int _submittedFrame = -1;
  NativeScene? _notifiedScene;
  bool _notifiedWorld = false;
  int _historyRevision = 0;
  Duration? _lastTick;
  Map<String, Object?>? _pendingSettings;
  Object? error;
  bool isLoading = true;
  bool hapticsEnabled = true;
  bool controlsVisible = true;
  bool cartoonEnabled = false;
  KeyboardBindings keyboard = KeyboardBindings();
  final ValueNotifier<int> sceneRevision = ValueNotifier(0);
  bool landscape = false;
  int battleSpeedMultiplier = 2;
  String? notice;
  Future<void> Function(GameRequest)? onUiRequest;
  final ValueNotifier<SgbyBattleStatistics?> sgbyBattleStatistics =
      ValueNotifier(null);

  NativeGameSession? get session => _session;
  GameFramePresenter? get frames => _frames;
  bool get isBusy => _busy;
  bool get isReady => !isLoading && _session != null;
  bool get hasWorld => _session?.hasWorld ?? false;
  bool get sgbyAutoBattleEnabled =>
      _session?.options.enabled('autoBattle') ?? false;
  bool get sgbyAutoEndTurnEnabled =>
      _session?.options.enabled('autoEndTurn') ?? false;
  bool get sgbyShowTroopIconsEnabled =>
      _session?.options.enabled('showTroopIcons') ?? false;

  /// macOS 窗口失焦或遮挡后继续推进；移动平台仍按前后台暂停。
  bool get usesBackgroundClock =>
      !kIsWeb &&
      [
        TargetPlatform.macOS,
        TargetPlatform.windows,
      ].contains(defaultTargetPlatform);
  bool get paused =>
      !_attached ||
      (!_foreground && !usesBackgroundClock) ||
      _uiPauseDepth > 0 ||
      _busy;

  /// 合集宿主提前启动加载；页面再次挂载时复用任务，避免构建中重复通知和重复会话。
  Future<void> initialize() {
    if (_disposed) return Future<void>.value();
    return _initializationTask ??= _initialize().whenComplete(() {
      _initializationTask = null;
    });
  }

  Future<void> _initialize() async {
    final generation = ++_generation;
    isLoading = true;
    error = null;
    _notify();
    try {
      final resources = await _assets.load();
      final settings = await _saves.loadSettings();
      if (!_current(generation)) return;
      hapticsEnabled = settings['hapticsEnabled'] != false;
      controlsVisible = settings['controlsVisible'] != false;
      cartoonEnabled = settings['cartoonEnabled'] == true;
      keyboard = KeyboardBindings(settings['keyboardBindings']);
      final speed = settings['battleSpeedMultiplier'];
      if (speed is int && sgbyGameSpeedMultipliers.contains(speed)) {
        battleSpeedMultiplier = speed;
      }
      _session?.dispose();
      _frames?.dispose();
      final optionData = settings['gameOptions'];
      _session = NativeGameSession(
        resources,
        options: GameOptions(
          optionData is Map ? Map<String, Object?>.from(optionData) : null,
        ),
        searchHistory: settings['searchHistory'] is List
            ? settings['searchHistory'] as List
            : null,
      );
      _frames = GameFramePresenter(
        width: resources.logicalWidth * resources.scale,
        height: resources.logicalHeight * resources.scale,
      );
      _display = GameDisplayEnhancements(resources);
      _submittedFrame = -1;
      _lastTick = null;
      isLoading = false;
      _submitFrame();
      _notify();
      _platform.start(send);
      if (cartoonEnabled) _loadCartoonArt();
      unawaited(_platform.setScreenAwake(_foreground));
      await _refreshSlots(generation);
    } catch (exception) {
      if (_current(generation)) {
        error = exception;
        isLoading = false;
        _notify();
      }
    }
  }

  bool _current(int generation) => !_disposed && generation == _generation;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void tick(Duration elapsed) {
    final previous = _lastTick;
    _lastTick = elapsed;
    if (_disposed || previous == null || paused) return;
    _session?.advance(elapsed - previous, speed: battleSpeedMultiplier);
    _submitFrame();
    sgbyBattleStatistics.value = _session?.world?.battleRecord.statistics;
    if (_session != null &&
        _historyRevision != _session!.enhancements.revision) {
      _historyRevision = _session!.enhancements.revision;
      _persistSettings();
    }
    if (_session?.hasRequests ?? false) _afterInput(_session?.world);
  }

  void setForeground(bool active) {
    if (_disposed) return;
    _foreground = active;
    _lastTick = null;
    unawaited(_platform.setScreenAwake(active && isReady));
  }

  /// detached 始终停止逻辑；macOS 的 inactive/hidden 仅表示失焦或不可见。
  void setLifecycleState(AppLifecycleState state) {
    if (_disposed) return;
    _attached = state != AppLifecycleState.detached;
    _visible =
        state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive;
    setForeground(state == AppLifecycleState.resumed);
  }

  /// 查询面板复用旧接口名，但暂停的对象已经是原生会话时钟。
  Future<T> withSgbyAutomationPaused<T>(Future<T> Function() operation) async {
    _uiPauseDepth++;
    try {
      return await operation();
    } finally {
      _uiPauseDepth--;
      _lastTick = null;
    }
  }

  void send(GameInput action) {
    if (_disposed || !isReady || paused) return;
    final dataBefore = _session?.world;
    final input = switch (action) {
      GameInput.up => NativeInput.up,
      GameInput.down => NativeInput.down,
      GameInput.left => NativeInput.left,
      GameInput.right => NativeInput.right,
      GameInput.confirm => NativeInput.confirm,
      GameInput.cancel => NativeInput.cancel,
      GameInput.pageUp => NativeInput.pageUp,
      GameInput.pageDown => NativeInput.pageDown,
      GameInput.search => NativeInput.search,
      GameInput.help => NativeInput.help,
      _ => null,
    };
    if (input != null) {
      _session?.input(input);
    } else if (action == GameInput.toggleBattleSpeed) {
      battleSpeedMultiplier = nextSgbyGameSpeedMultiplier(
        battleSpeedMultiplier,
      );
      _persistSettings();
    } else if (action == GameInput.toggleTroopIcons) {
      _session?.options.toggle('showTroopIcons');
      if (_session?.scene == NativeScene.battle) {
        _session?.onBattleRedraw?.call();
      }
      _persistSettings();
    } else if (action == GameInput.generalRoster) {
      _requests.add(const GameRequest(GameRequestType.roster));
    } else if (action == GameInput.searchHistory) {
      _requests.add(const GameRequest(GameRequestType.searchHistory));
    } else if (action == GameInput.autoBattle ||
        action == GameInput.autoEndTurn) {
      final option = action == GameInput.autoBattle
          ? 'autoBattle'
          : 'autoEndTurn';
      _session?.options.toggle(option);
      _persistSettings();
      if (option == 'autoEndTurn' && sgbyAutoEndTurnEnabled) {
        _session?.requestAdvanceTurn();
      }
    } else if (action == GameInput.battleInfo &&
        _session?.activeBattle != null) {
      _session?.onBattleInput?.call(NativeInput.search);
    } else if (action == GameInput.quickExpedition &&
        _session?.scene == NativeScene.strategy &&
        !(_session?.resolvingTurn ?? true)) {
      final current = _session!;
      final city = current.renderer.selectedCity(current.world!);
      if (city != null) {
        current.options.toggle('autoEndTurn', enabled: false);
        StrategyCommandFlow(current, city, 27).start(quickExpedition: true);
        _persistSettings();
      }
    } else if (action == GameInput.endTurn && _session?.activeBattle != null) {
      _session?.onBattleEndTurn?.call();
    } else if (action == GameInput.endTurn &&
        _session?.scene == NativeScene.strategy) {
      _requests.add(const GameRequest(GameRequestType.advanceTurn));
    } else {
      showNotice('当前操作暂不可用');
    }
    _afterInput(dataBefore);
  }

  void tap(num x, num y) {
    if (_disposed || paused) return;
    final before = _session?.world;
    _session?.tap(x.floor(), y.floor());
    _afterInput(before);
  }

  void swipe(int deltaY, {int deltaX = 0}) {
    if (_disposed || paused) return;
    _session?.swipe(deltaY, deltaX: deltaX);
    _afterInput(_session?.world);
  }

  bool longPress(num x, num y) {
    if (_disposed || paused) return false;
    final accepted = _session?.longPress(x.floor(), y.floor()) ?? false;
    if (accepted) _afterInput(_session?.world);
    return accepted;
  }

  SgbyEnemyCityInfo? enemyCityInfo(int cityIndex) {
    final current = _session,
        world = _session?.world,
        city = _session?.world?.city(cityIndex);
    if (current == null ||
        world == null ||
        city == null ||
        city.belong == 0 ||
        city.belong == (world.playerRulerIndex ?? -1) + 1) {
      return null;
    }
    final commands = StrategyCommands(current.resources);
    return SgbyEnemyCityInfo(
      name: current.resources.cityName(cityIndex),
      rulerName: current.resources.personName(world.period, city.belong - 1),
      generals: [
        for (final id in world.personsInCity(cityIndex))
          if (world.person(id)!.belong == city.belong ||
              world.person(id)!.belong == 65535)
            SgbyEnemyCityGeneralInfo(
              name: current.resources.personName(world.period, id),
              level: world.person(id)!.level,
              force: world.person(id)!.force,
              iq: world.person(id)!.iq,
              devotion: world.person(id)!.devotion,
              arms: world.person(id)!.arms,
              armsType: commands.armType(world, world.person(id)!),
              isCaptive: world.person(id)!.belong == 65535,
            ),
      ],
    );
  }

  void _afterInput(Object? previousWorld) {
    final current = _session;
    if (current == null) return;
    if (current.hasWorld &&
        (!identical(previousWorld, current.world) ||
            sgbyBattleStatistics.value == null)) {
      current.enhancements.applyPersistent(current.world!);
      sgbyBattleStatistics.value = current.world?.battleRecord.statistics;
    } else if (!current.hasWorld) {
      sgbyBattleStatistics.value = null;
    }
    _requests.addAll(current.takeRequests());
    _submitFrame();
    _notify();
    if (!_processing) unawaited(_processRequests());
  }

  void _submitFrame() {
    // macOS 完全不可见时只推进逻辑；停止 GPU 图片上传，避免旧图片等待绘制后
    // 释放的回调在没有窗口帧时无限积压。重新可见后的下一次 tick 上传最新帧。
    if (!_visible) return;
    final current = _session;
    final presenter = _frames;
    if (current == null ||
        presenter == null ||
        _submittedFrame == current.frameVersion) {
      return;
    }
    _submittedFrame = current.frameVersion;
    // 绘图帧只通知画布；场景结构改变时还需刷新侧栏和操作区，防止战斗仍显示出征键。
    final structuralChange =
        _notifiedScene != current.scene || _notifiedWorld != current.hasWorld;
    _notifiedScene = current.scene;
    _notifiedWorld = current.hasWorld;
    sceneRevision.value++;
    if (structuralChange) _notify();
    if (cartoonEnabled) return;
    final display = _display;
    if (display == null) return;
    presenter.submit(
      display.frame(
        current.canvas.surface,
        current.world,
        strategy:
            current.scene == NativeScene.strategy ||
            current.scene == NativeScene.targetCity,
        roads: current.mapRoadsVisible,
        factionColors: current.options.enabled('factionColors'),
        playerBattle: current.activeBattle?.result == 0,
      ),
    );
  }

  Future<void> _processRequests() async {
    _processing = true;
    final generation = _generation;
    try {
      while (_current(generation) && _requests.isNotEmpty) {
        final request = _requests.removeFirst();
        _busy = true;
        _notify();
        try {
          switch (request.type) {
            case GameRequestType.exitApplication:
              final exit = onExitRequested;
              if (exit != null) {
                await exit();
              } else {
                await SystemNavigator.pop();
              }
            case GameRequestType.loadSlot:
              final index = request.index;
              if (index == null) break;
              final loaded = await _saves.load(index);
              if (!_current(generation)) break;
              if (loaded == null) {
                _session?.showReport('打开文件失败!');
              } else {
                _session?.replaceWorld(loaded);
              }
            case GameRequestType.saveSlot:
              final index = request.index;
              final world = _session?.world;
              if (index == null || world == null) break;
              await _saves.save(index, world);
              if (!_current(generation)) break;
              await _refreshSlots(generation);
              _session?.showStrategy();
              showNotice('进度已保存');
            case GameRequestType.autoSave:
              final current = _session;
              final world = current?.world;
              if (current == null ||
                  world == null ||
                  !identical(world, request.world) ||
                  !current.options.enabled('autoSaveAfterTurn') ||
                  current.resolvingTurn ||
                  current.activeBattle != null ||
                  current.scene != NativeScene.strategy) {
                break;
              }
              try {
                await _saves.save(0, world);
                if (!_current(generation)) break;
                await _refreshSlots(generation);
              } catch (_) {
                if (_current(generation)) showNotice('策略结束自动存档失败，请手动保存');
              }
            case GameRequestType.roster:
            case GameRequestType.searchHistory:
              final handler = onUiRequest;
              if (handler != null) {
                await handler(request);
              } else {
                showNotice('当前操作暂不可用');
              }
            case GameRequestType.help:
              final current = _session;
              if (current != null) RefinedHelpFlow(current).start();
            case GameRequestType.advanceTurn:
              final current = _session;
              if (current != null &&
                  (request.world == null ||
                      identical(request.world, current.world))) {
                StrategyTurnFlow(current).start();
              }
            case GameRequestType.cityCommand:
              final current = _session;
              final city = request.cityIndex;
              final command = request.index;
              if (current != null && city != null && command != null) {
                StrategyCommandFlow(current, city, command).start();
              }
          }
        } catch (exception) {
          if (_current(generation)) showNotice('操作失败：$exception');
        } finally {
          if (_current(generation)) {
            _busy = false;
            _submitFrame();
            _notify();
          }
        }
      }
    } finally {
      _processing = false;
    }
  }

  Future<void> _refreshSlots(int generation) async {
    final titles = <String?>[];
    for (var i = 0; i < 4; i++) {
      try {
        final saved = await _saves.load(i);
        if (!_current(generation)) return;
        final ruler = saved?.playerRulerIndex;
        titles.add(
          saved == null || ruler == null
              ? null
              : _session?.resources.saveTitle(saved),
        );
      } catch (_) {
        titles.add('存档损坏');
      }
    }
    if (_current(generation)) {
      _session?.setSlotTitles(titles);
      _submitFrame();
    }
  }

  void openSaveMenu() {
    if (_disposed || !hasWorld || paused) return;
    if (_session?.resolvingTurn ?? false) {
      showNotice('请在本月结算完成后存档');
      return;
    }
    _session?.openSaveMenu();
    _submitFrame();
    _notify();
  }

  Future<SgbyCheatData> getSgbyCheatData() async {
    final current = _session;
    final world = current?.world;
    if (_disposed || current == null || world == null) {
      return const SgbyCheatData(
        isSuccess: false,
        message: '请先开始或载入一局游戏',
        maxLevel: 20,
        generals: [],
      );
    }
    return BuildGeneralRoster(current.resources)(
      world,
      battle: current.activeBattle,
    );
  }

  Future<Map<String, bool>> getCheatState() async {
    final options = _session?.options;
    if (options == null) return {};
    return {
      for (final key in GameOptions.booleans) key: options.enabled(key),
      'postBattleCaptiveRecruit':
          options.choice('postBattleCaptiveAction') == 'recruit',
      'postBattleCaptiveExecute':
          options.choice('postBattleCaptiveAction') == 'execute',
      'postBattleCaptiveExile':
          options.choice('postBattleCaptiveAction') == 'exile',
      'searchOutcomeAll': options.choice('searchOutcome') == 'all',
      'searchOutcomeNone': options.choice('searchOutcome') == 'none',
      'battleLoserOutcomeOriginal': options.loserOutcome == 0,
      'battleLoserOutcomeDeath': options.loserOutcome == 1,
      'battleLoserOutcomeCaptive': options.loserOutcome == 2,
      'battleLoserOutcomeEscape': options.loserOutcome == 3,
      'battleLoserOutcomeWild': options.loserOutcome == 4,
    };
  }

  /// 单条偏好损坏只跳过该条记录，避免历史面板因强制类型转换而打不开。
  Future<SgbySearchHistoryData> getSgbySearchHistory() async {
    final records = <SgbySearchHistoryRecord>[];
    for (final value in _session?.enhancements.history ?? const []) {
      if (value is! Map) continue;
      try {
        records.add(
          SgbySearchHistoryRecord.fromJson(Map<String, dynamic>.from(value)),
        );
      } on FormatException {
        continue;
      } on TypeError {
        continue;
      }
    }
    return SgbySearchHistoryData(isSuccess: _session != null, records: records);
  }

  int get worldActivity => _session?.options.worldActivity ?? 50;
  Future<int?> getSgbyEnemyArmsLimit() async =>
      _session?.options.enemyArmsLimit;
  void setWorldActivity(int value) {
    _session?.options.setActivity(value);
    _persistSettings();
    _notify();
  }

  /// 只接受白名单的我方将领属性操作，不执行来自界面或存档的代码片段。
  Future<CheatResult> applyCheat(
    String action, {
    Map<String, Object?>? parameters,
  }) async {
    final current = _session;
    final world = current?.world;
    if (_disposed || current == null || world == null) {
      return const CheatResult(isSuccess: false, message: '请先开始或载入一局游戏');
    }
    if (action == 'sgby_hide_special_generals' &&
        (current.resolvingTurn ||
            current.activeBattle != null ||
            current.scene != NativeScene.strategy)) {
      return const CheatResult(isSuccess: false, message: '请回到战略地图后切换特殊武将隐藏');
    }
    final index = parameters?['generalIndex'];
    if (!action.startsWith('sgby_general_')) {
      final result = current.enhancements.apply(
        world,
        action,
        parameters: parameters,
        selectedCity: current.renderer.selectedCity(world),
        battle: current.activeBattle,
      );
      _persistSettings();
      if (current.scene == NativeScene.strategy) current.showStrategy();
      _submitFrame();
      _notify();
      return result;
    }
    if (index is! int) {
      return const CheatResult(isSuccess: false, message: '请选择有效的我方武将');
    }
    final person = world.person(index);
    if (person == null || person.belong != (world.playerRulerIndex ?? -1) + 1) {
      return const CheatResult(isSuccess: false, message: '请选择有效的我方武将');
    }
    final replacement = switch (action) {
      'sgby_general_force' => person.copyWith(force: 100),
      'sgby_general_iq' => person.copyWith(iq: 100),
      'sgby_general_thew' => person.copyWith(thew: 100),
      'sgby_general_devotion' => person.copyWith(devotion: 100),
      'sgby_general_level' => person.copyWith(
        level: current.resources.rule('maxLevel', 20),
        experience: 0,
      ),
      'sgby_general_arms' => person.copyWith(arms: 65535),
      'sgby_general_all' => person.copyWith(
        force: 100,
        iq: 100,
        thew: 100,
        devotion: 100,
        level: current.resources.rule('maxLevel', 20),
        experience: 0,
        arms: 65535,
      ),
      _ => null,
    };
    if (action == 'sgby_general_move' || action == 'sgby_general_restore') {
      final battle = current.activeBattle;
      final slot = battle?.people.indexOf(index) ?? -1;
      if (battle == null || slot < 0 || slot >= 10) {
        return const CheatResult(isSuccess: false, message: '当前武将不在我方战场队列中');
      }
      final unit = battle.units[slot];
      if (action == 'sgby_general_move') {
        unit.move = 8;
        unit.active = 0;
      } else {
        unit.hp = 100;
        unit.mp = 100;
        unit.state = 0;
        unit.active = 0;
      }
    } else if (action == 'sgby_general_arm_type') {
      final type = parameters?['armsType'];
      if (type is! int || type < 0 || type > 5) {
        return const CheatResult(isSuccess: false, message: '兵种参数无效');
      }
      world.setPerson(index, person.copyWith(armsType: type));
    } else if (replacement != null) {
      world.setPerson(index, replacement);
    } else {
      return const CheatResult(isSuccess: false, message: '当前操作暂不可用');
    }
    if (current.scene == NativeScene.strategy) current.showStrategy();
    _submitFrame();
    _notify();
    return const CheatResult(isSuccess: true, message: '武将属性已更新');
  }

  void setHaptics(bool enabled) {
    hapticsEnabled = enabled;
    _persistSettings();
    _notify();
  }

  void setControls(bool enabled) {
    if (_disposed) return;
    controlsVisible = enabled;
    _persistSettings();
    _notify();
  }

  /// 只切换表现层，保持当前选将、数字输入、战场行动和存档世界不变。
  void toggleCartoon() {
    if (_disposed) return;
    cartoonEnabled = !cartoonEnabled;
    if (cartoonEnabled) _loadCartoonArt();
    _submittedFrame = -1;
    _submitFrame();
    _persistSettings();
    _notify();
  }

  /// 美术资源延迟加载；只持有一份图集，完成时校验代次，销毁后不回调界面。
  void _loadCartoonArt() {
    if (_disposed || _artLoading || _cartoonAssets != null) return;
    _artLoading = true;
    final token = ++_artToken;
    _artTask = () async {
      try {
        final art = await CartoonAssets.load();
        if (_disposed || token != _artToken) {
          art.dispose();
          return;
        }
        _cartoonAssets = art;
        sceneRevision.value++;
        _notify();
      } catch (error) {
        if (!_disposed && token == _artToken) showNotice('卡通素材加载失败：$error');
      } finally {
        if (token == _artToken) _artLoading = false;
      }
    }();
    unawaited(_artTask);
  }

  GameInput? keyboardAction(int key) =>
      keyboard.resolve(key, GameKeyboard.defaults);
  void bindKeyboard(GameInput action, int key) {
    if ([
      LogicalKeyboardKey.f9.keyId,
      LogicalKeyboardKey.f10.keyId,
    ].contains(key)) {
      showNotice('F9 / F10 保留给画风与界面显隐');
      return;
    }
    if (_disposed || !keyboard.bind(action, key, GameKeyboard.defaults)) return;
    _persistSettings();
    _notify();
  }

  void resetKeyboard() {
    if (_disposed) return;
    keyboard.reset();
    _persistSettings();
    _notify();
  }

  void setLandscape(bool enabled) {
    landscape = enabled;
    _notify();
  }

  void showNotice(String message) {
    if (!_disposed) {
      notice = message;
      _notify();
    }
  }

  String? takeNotice() {
    final value = notice;
    notice = null;
    return value;
  }

  void _persistSettings() {
    _pendingSettings = <String, Object?>{
      'hapticsEnabled': hapticsEnabled,
      'controlsVisible': controlsVisible,
      'cartoonEnabled': cartoonEnabled,
      'keyboardBindings': keyboard.toJson(),
      'battleSpeedMultiplier': battleSpeedMultiplier,
      'gameOptions': _session?.options.toJson(),
      'searchHistory': _session?.enhancements.history,
    };
    if (!_savingSettings) unawaited(_saveSettings());
  }

  Future<void> _saveSettings() async {
    _savingSettings = true;
    try {
      while (_pendingSettings != null) {
        final snapshot = _pendingSettings!;
        _pendingSettings = null;
        await _saves.saveSettings(snapshot);
      }
    } catch (exception) {
      if (!_disposed) showNotice('设置保存失败：$exception');
    } finally {
      _savingSettings = false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _artToken++;
    _cartoonAssets?.dispose();
    _cartoonAssets = null;
    _generation++;
    onUiRequest = null;
    _requests.clear();
    _session?.dispose();
    _session = null;
    _frames?.dispose();
    _frames = null;
    _display = null;
    sgbyBattleStatistics.dispose();
    sceneRevision.dispose();
    unawaited(_platform.dispose());
    super.dispose();
  }
}

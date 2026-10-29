import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../data/game_data.dart';
import '../data/save_repository.dart';
import '../engine/game_engine.dart';
import '../engine/pixel_surface.dart';
import 'system_font_layout.dart';
import 'modern_art.dart';
import 'modern_map_camera.dart';
import 'game_keyboard_bindings.dart';

/// 前台会话与 Flutter 帧桥接；同一时刻最多解码一张图片，销毁后及时释放 GPU 资源。
final class GameViewModel extends ChangeNotifier {
  GameViewModel({SaveRepository? repository})
    : repository = repository ?? SaveRepository();
  final SaveRepository repository;
  GameEngine? engine;
  GameKeyboardBindings keyboardBindings = GameKeyboardBindings.defaults;

  /// 与 BBK 保持相同的多键绑定、冲突迁移及即时保存行为。
  void setKeyboardBindings(GameKeyboardBindings value) {
    if (_disposed) return;
    keyboardBindings = value;
    _held = null;
    notifyListeners();
    unawaited(persist());
  }

  ui.Image? image;
  ModernArt? modernArt;
  Object? modernArtError;
  Future<void>? _artLoading;

  /// 同一会话只解码一次；切换样式不重建游戏状态。销毁后的异步结果立即释放。
  Future<void> prepareModernArt() => _artLoading ??= _loadModernArt();
  Future<void> _loadModernArt() async {
    try {
      final art = await ModernArt.load();
      if (_disposed) {
        art.dispose();
        return;
      }
      modernArt = art;
      notifyListeners();
    } catch (error, stack) {
      modernArtError = error;
      if (kDebugMode) {
        debugPrintStack(label: '新版美术加载失败：$error', stackTrace: stack);
      }
      if (!_disposed) {
        engine?.notice = '新版美术加载失败，可切换经典 UI 继续游戏';
        notifyListeners();
      }
    }
  }

  List<SystemTextRun> textRuns = const [];
  String? failure;
  Map<String, dynamic>? _lastAutosave;
  bool loading = true,
      paused = false,
      _disposed = false,
      _decoding = false,
      _dirty = false;
  bool _windowVisible = true;
  Timer? _timer;
  GameKey? _held;
  int _heldElapsed = 0, _autosaveTicks = 0;
  bool _heldRepeating = false;
  Uint32List? _previous;
  bool? _previousHd;
  int imageLogicalWidth = 320, imageLogicalHeight = 192;
  String? _presentationKey, _sceneKey;

  /// 静止场景不因菜单、提示条或定时器通知而再次光栅化。
  int sceneRevision = 0;
  Future<void> initialize() async {
    try {
      final binary = rootBundle.load('assets/fmj/game/DAT.LIB');
      final encoding = rootBundle.loadString('assets/fmj/game/gbk.json');
      final guide = rootBundle.loadString('assets/fmj/game/FmjGuideData.json');
      final stages = rootBundle.loadString('assets/fmj/game/FmjStageData.json');
      final bytes = await binary;
      final data = GameData(
        bytes: bytes.buffer.asUint8List(
          bytes.offsetInBytes,
          bytes.lengthInBytes,
        ),
        encoding: GameEncoding(GameData.decodeObject(await encoding)),
        guide: GameData.decodeObject(await guide),
        stages: (jsonDecode(await stages) as List)
            .map((v) => Map<String, dynamic>.from(v as Map))
            .toList(),
      );
      final game = GameEngine(data, textLayout: FlutterSystemFontLayout());
      final saved = await repository.read();
      if (_disposed) return;
      engine = game;
      if (saved != null) {
        keyboardBindings = GameKeyboardBindings.fromJson(
          saved['keyboardBindings'],
        );
        game.retainStageBackup(saved['stageBackup'] as String?);
        final prefs = saved['preferences'];
        if (prefs is Map) {
          for (final entry in prefs.entries) {
            game.setPreference('${entry.key}', entry.value);
          }
        }
        final slots = saved['slots'];
        if (slots is List) {
          for (var i = 0; i < 3 && i < slots.length; i++) {
            final slot = slots[i];
            if (slot is Map) game.saves[i] = Map<String, dynamic>.from(slot);
          }
        }
        final autosave = saved['autosave'];
        if (autosave is Map) {
          _lastAutosave = Map<String, dynamic>.from(autosave);
        }
        if (autosave is Map) {
          try {
            game.restore(Map<String, dynamic>.from(autosave));
          } catch (_) {
            game.notice = '自动存档不可用，可尝试读取手动档位';
          }
        }
      }
      game.onSaveChanged = () => unawaited(persist());
      loading = false;
      _timer = Timer.periodic(
        const Duration(milliseconds: 40),
        (_) => advanceFrame(),
      );
      _render();
      notifyListeners();
    } catch (e) {
      if (!_disposed) {
        failure = '加载失败：$e';
        loading = false;
        notifyListeners();
      }
    }
  }

  /// 推进一次40ms前台帧；输入的长按门槛使用真实时间，游戏模拟仍按所选倍速推进。
  ///
  /// 与虚拟方向键保持相同的320ms长按识别门槛，不能将它也除以倍速，否则四倍速
  /// 下80ms的普通短按就会进入连走。进入长按后才按倍速累计105ms的游戏重复间隔。
  void advanceFrame() {
    final game = engine;
    if (_disposed || paused || game == null) return;
    final held = _held;
    if (held != null) {
      if (!_heldRepeating) {
        _heldElapsed += 40;
        if (_heldElapsed >= 320) {
          _heldElapsed = (_heldElapsed - 320) * game.runSpeed;
          _heldRepeating = true;
        }
      } else {
        _heldElapsed += 40 * game.runSpeed;
      }
      while (_heldRepeating && _heldElapsed >= 105) {
        _heldElapsed -= 105;
        game.key(held);
        if (game.operation != null ||
            game.battle != null ||
            game.cursor?.running == true) {
          _heldElapsed = 0;
          break;
        }
      }
    }
    game.update();
    if (_windowVisible) _render(force: false);
    if (++_autosaveTicks >= 125) {
      _autosaveTicks = 0;
      if (game.canSave) unawaited(persist());
    }
  }

  void down(GameKey key) {
    final game = engine;
    if (game == null || paused || _disposed) return;
    if (_held == key) return; // 同一方向按住期间不因重复KeyDown重发第一步。
    _held = key.index < 4 ? key : null;
    _heldElapsed = 0;
    _heldRepeating = false;
    game.key(key);
    _render();
  }

  void up(GameKey key) {
    if (_held == key) _held = null;
    engine?.key(key, down: false);
    _render();
  }

  void press(GameKey key) {
    engine?.press(key);
    _render();
  }

  void action(void Function(GameEngine game) action) {
    final game = engine;
    if (game != null) {
      action(game);
      game.render();
      _render();
    }
  }

  /// 将实际显示区域中的鼠标/触屏坐标还原成同一镜头的地图格；弹窗、战斗不透传。
  /// 新点击会取消旧导航与刷钱；不可达目标只提交最近可达格，仍经正常方向输入行走。
  void tapMap(ui.Offset position, ui.Size size, {bool classic = false}) {
    final game = engine, map = engine?.map, player = engine?.player;
    if (_disposed ||
        paused ||
        game == null ||
        map == null ||
        player == null ||
        game.screen != 'play' ||
        game.operation != null ||
        game.battle != null ||
        game.cursor?.running == true ||
        game.menus.isNotEmpty ||
        size.isEmpty ||
        !(ui.Offset.zero & size).contains(position)) {
      return;
    }
    final camera = ModernMapCamera(
      mapWidth: map.width,
      mapHeight: map.height,
      playerX: player.x,
      playerY: player.y,
      wide: game.wide,
    );
    final x = (camera.left + position.dx / size.width * camera.columns).floor();
    final y = (camera.top + position.dy / size.height * camera.rows).floor();
    game.moneyFarm.stop();
    game.navigation.cancel();
    game.notice = game.walkTo(x, y, nearest: true)
        ? '正在前往点击位置'
        : '前方有阻碍，无法继续前进';
    _render();
  }

  void setPaused(bool value) {
    paused = value;
    _held = null;
    if (value) unawaited(persist());
    notifyListeners();
  }

  /// 释放物理按键状态，不取消已启动的导航和自动战斗。
  void releaseHeldKeys() {
    _held = null;
    _heldElapsed = 0;
    _heldRepeating = false;
  }

  /// 最小化后只推进逻辑；恢复可见时上传最新画面，避免后台积压GPU图片。
  void setWindowVisible(bool value) {
    if (_disposed || _windowVisible == value) return;
    _windowVisible = value;
    if (value) _render();
  }

  /// 合集退出前可要求保存失败向上传递，防止失败后仍关闭会话。
  Future<void> persist({bool rethrowOnFailure = false}) async {
    final game = engine;
    if (game == null) return;
    try {
      if (game.canSave) {
        _lastAutosave = GameData.decodeObject(jsonEncode(game.snapshot()));
      }
      await repository.write({
        'schema': 1,
        'keyboardBindings': keyboardBindings.toJson(),
        'preferences': Map<String, dynamic>.from(game.preferences),
        'slots': game.saves,
        'autosave': _lastAutosave,
        'stageBackup': game.stageBackup,
      });
    } catch (e) {
      if (!_disposed) {
        game.notice = '保存失败：$e';
        notifyListeners();
      }
      if (rethrowOnFailure) rethrow;
    }
  }

  void _render({bool force = true}) {
    final game = engine;
    if (_disposed || game == null) return;
    if (_decoding) {
      _dirty = true;
      return;
    }
    if (game.preferences['modernUi'] == true) {
      final animated =
          game.battle != null ||
          game.screen == 'intro' ||
          game.operation?.movie != null ||
          game.operation?.kind == 'credits';
      final sceneKey =
          '${game.map?.id}/${game.cursor?.script.id}/'
          '${game.wide}/${game.preferences['hd']}/${game.flags}/'
          '${animated ? game.ticks : 0}/${game.route}/'
          '${[...game.npcs.values, ?game.player].map((a) => '${a.type},${a.index},${a.sprite},${a.x},${a.y},${a.direction},'
              '${a.step},${a.state},${a.visible}').join(';')}';
      if (_sceneKey != sceneKey) {
        _sceneKey = sceneKey;
        sceneRevision++;
      }
      final op = game.operation;
      final key =
          '$sceneKey/${game.screen}/${game.sceneName}/${game.money}/'
          '${game.notice}/${game.error}/${game.preferences}/'
          '${identityHashCode(op)}/${op?.start}/${op?.next}/${op?.selected}/'
          '${game.menus.map((m) => '${identityHashCode(m)},${m.selected},${m.page},${m.revision}').join(';')}/'
          '${game.players.map((a) => '${a.hp},${a.maxHp},${a.mp},${a.maxMp},${a.level},${a.equipment}').join(';')}/'
          '${game.navigation.active?.label}/${game.navigation.planning}/'
          '${game.moneyFarm.active}/${game.moneyFarm.rounds}';
      if (!force && _presentationKey == key) return;
      _presentationKey = key;
      _previous = null;
      textRuns = game.surface.textRuns.map((run) => run.copy()).toList();
      notifyListeners();
      return;
    }
    final surface = game.surface,
        hd = game.preferences['hd'] == true && !game.forceClassic;
    final source = surface.pixels, previous = _previous;
    var changed =
        previous == null ||
        previous.length != source.length ||
        hd != _previousHd;
    if (!changed) {
      for (var i = 0; i < source.length; i++) {
        if (source[i] != previous[i]) {
          changed = true;
          break;
        }
      }
    }
    if (!changed) {
      textRuns = surface.textRuns.map((run) => run.copy()).toList();
      notifyListeners();
      return;
    }
    _decoding = true;
    _dirty = false;
    _previous = Uint32List.fromList(source);
    _previousHd = hd;
    final pixels = hd ? surface.enhancedPixels() : Uint32List.fromList(source),
        scale = hd ? 3 : 1;
    final runs = surface.textRuns.map((run) => run.copy()).toList(),
        width = surface.width,
        height = surface.height;
    ui.decodeImageFromPixels(
      pixels.buffer.asUint8List(),
      width * scale,
      height * scale,
      ui.PixelFormat.rgba8888,
      (next) {
        _decoding = false;
        if (_disposed) {
          next.dispose();
          return;
        }
        final old = image;
        image = next;
        textRuns = runs;
        imageLogicalWidth = width;
        imageLogicalHeight = height;
        old?.dispose();
        notifyListeners();
        if (_dirty) _render();
      },
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    _held = null;
    engine?.onSaveChanged = null;
    engine?.moneyFarm.stop();
    engine?.navigation.cancel();
    image?.dispose();
    image = null;
    modernArt?.dispose();
    modernArt = null;
    super.dispose();
  }
}

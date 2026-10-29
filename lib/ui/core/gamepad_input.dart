import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gamepads/gamepads.dart';

/// 两款游戏共用的手柄动作，与引擎枚举和键盘自定义配置解耦。
enum GamepadAction {
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
  menu,
  quickTravel,
}

/// 手柄边沿、死区及长按状态机：方向和RT按住320ms后每105ms连发，A/B不连发。
/// 十字键优先，摇杆选单个主方向。失焦、遮挡和断连清除状态，恢复不补发旧操作。
final class GamepadInputRouter {
  GamepadInputRouter({required this.onInput, required this.enabled});
  final ValueChanged<GamepadAction> onInput;
  final bool Function() enabled;
  final _pads = <String, _PadState>{};
  final _delays = <GamepadAction, Timer>{}, _repeats = <GamepadAction, Timer>{};
  Set<String> _nativeControllers = {};
  GamepadAction? _direction;
  bool _disposed = false;
  static const _dpad = {
    GamepadButton.dpadUp: GamepadAction.up,
    GamepadButton.dpadDown: GamepadAction.down,
    GamepadButton.dpadLeft: GamepadAction.left,
    GamepadButton.dpadRight: GamepadAction.right,
  };
  void handle(NormalizedGamepadEvent event) {
    if (_disposed || !event.value.isFinite) return;
    if (!enabled()) {
      reset();
      return;
    }
    final pad = _pads.putIfAbsent(event.gamepadId, _PadState.new),
        button = event.button;
    if (button != null) {
      final pressed = event.value > .5;
      if (!(pressed ? pad.buttons.add(button) : pad.buttons.remove(button))) {
        return;
      }
      if (_dpad.containsKey(button)) {
        _syncDirection();
        return;
      }
      final action = switch (button) {
        GamepadButton.a => GamepadAction.confirm,
        GamepadButton.b || GamepadButton.back => GamepadAction.cancel,
        GamepadButton.x => GamepadAction.search,
        GamepadButton.y => GamepadAction.help,
        GamepadButton.leftBumper => GamepadAction.pageUp,
        GamepadButton.rightBumper => GamepadAction.pageDown,
        GamepadButton.start => GamepadAction.menu,
        GamepadButton.rightTrigger => GamepadAction.quickTravel,
        _ => null,
      };
      if (action == GamepadAction.quickTravel) {
        if (pressed) {
          _start(GamepadAction.quickTravel);
        } else {
          _stop(GamepadAction.quickTravel);
        }
      } else if (pressed && action != null) {
        _pulse(action);
      }
    } else if (event.axis == GamepadAxis.leftStickX ||
        event.axis == GamepadAxis.leftStickY) {
      if (event.axis == GamepadAxis.leftStickX) {
        pad.x = event.value.clamp(-1, 1);
      } else {
        pad.y = event.value.clamp(-1, 1);
      }
      _syncDirection();
    } else if (event.axis == GamepadAxis.rightTrigger) {
      final pressed = event.value >= (pad.trigger ? .35 : .5);
      if (pressed != pad.trigger) {
        pad.trigger = pressed;
        if (pressed) {
          _start(GamepadAction.quickTravel);
        } else {
          _stop(GamepadAction.quickTravel);
        }
      }
    }
  }

  void _syncDirection() {
    GamepadAction? next;
    for (final pad in _pads.values) {
      for (final entry in _dpad.entries) {
        if (pad.buttons.contains(entry.key)) {
          next = entry.value;
          break;
        }
      }
      if (next != null) break;
    }
    if (next == null) {
      for (final pad in _pads.values) {
        if (math.max(pad.x.abs(), pad.y.abs()) <
            (_direction == null ? .5 : .35)) {
          continue;
        }
        // 保留当前主轴，另一轴超过0.15才切换，避免45度附近噪声反复触发第一步。
        final horizontal =
            pad.stickDirection == GamepadAction.left ||
            pad.stickDirection == GamepadAction.right;
        final vertical =
            pad.stickDirection == GamepadAction.up ||
            pad.stickDirection == GamepadAction.down;
        final useX =
            horizontal && pad.x.abs() >= .35 && pad.y.abs() < pad.x.abs() + .15
            ? true
            : vertical && pad.y.abs() >= .35 && pad.x.abs() < pad.y.abs() + .15
            ? false
            : pad.x.abs() > pad.y.abs();
        next = useX
            ? (pad.x > 0 ? GamepadAction.right : GamepadAction.left)
            : (pad.y > 0 ? GamepadAction.up : GamepadAction.down);
        pad.stickDirection = next;
        break;
      }
    }
    if (next == _direction) return;
    final previous = _direction;
    _direction = next;
    if (previous != null) _stop(previous);
    if (next != null) _start(next);
  }

  void _pulse(GamepadAction action) {
    if (_disposed) return;
    if (!enabled()) {
      reset();
      return;
    }
    onInput(action);
  }

  void _start(GamepadAction action) {
    if (_delays.containsKey(action) || _repeats.containsKey(action)) return;
    _pulse(action);
    if (_disposed || !enabled()) {
      reset();
      return;
    }
    _delays[action] = Timer(const Duration(milliseconds: 320), () {
      _delays.remove(action);
      if (_disposed || !enabled()) {
        reset();
        return;
      }
      _pulse(action);
      if (_disposed || !enabled()) {
        reset();
        return;
      }
      _repeats[action] = Timer.periodic(
        const Duration(milliseconds: 105),
        (_) => _pulse(action),
      );
    });
  }

  void _stop(GamepadAction action) {
    _delays.remove(action)?.cancel();
    _repeats.remove(action)?.cancel();
  }

  /// 标准GameController可用时停用HID后备，避免同一只手柄重复发送操作。
  void setNativeControllers(Set<String> ids) {
    _nativeControllers = Set.of(ids);
    if (ids.isNotEmpty && _pads.keys.any((id) => id.startsWith('hid:'))) {
      _pads.removeWhere((id, _) => id.startsWith('hid:'));
      _syncDirection();
      _stop(GamepadAction.quickTravel);
    }
  }

  /// 原生桥仅匹配045e:028e，不监听键盘鼠标或猜测未知HID的按钮序号。
  void handleHid(dynamic raw) {
    if (_nativeControllers.isNotEmpty || raw is! Map) return;
    final id = raw['id'];
    if (id is! String || !id.startsWith('hid:')) return;
    if (raw['disconnected'] == true) {
      disconnect(id);
      return;
    }
    final page = raw['page'], usage = raw['usage'], value = raw['value'];
    if (page is! int || usage is! int || value is! num || !value.isFinite) {
      return;
    }
    GamepadButton? button;
    GamepadAxis? axis;
    double normalized = value.toDouble();
    if (page == 9) {
      button = const {
        1: GamepadButton.a,
        2: GamepadButton.b,
        3: GamepadButton.x,
        4: GamepadButton.y,
        5: GamepadButton.leftBumper,
        6: GamepadButton.rightBumper,
        7: GamepadButton.back,
        8: GamepadButton.start,
        12: GamepadButton.dpadUp,
        13: GamepadButton.dpadDown,
        14: GamepadButton.dpadLeft,
        15: GamepadButton.dpadRight,
      }[usage];
    } else if (page == 1 && (usage == 0x30 || usage == 0x31 || usage == 0x35)) {
      final low = raw['min'], high = raw['max'];
      if (low is! num ||
          high is! num ||
          !low.isFinite ||
          !high.isFinite ||
          high <= low) {
        return;
      }
      normalized = ((value - low) / (high - low)).clamp(0, 1).toDouble();
      if (usage == 0x35) {
        axis = GamepadAxis.rightTrigger;
      } else {
        axis = usage == 0x30 ? GamepadAxis.leftStickX : GamepadAxis.leftStickY;
        normalized = normalized * 2 - 1;
        if (usage == 0x31) normalized = -normalized;
      }
    }
    if (button == null && axis == null) return;
    handle(
      NormalizedGamepadEvent(
        gamepadId: id,
        timestamp: 0,
        button: button,
        axis: axis,
        value: normalized,
        rawEvent: GamepadEvent(
          gamepadId: id,
          timestamp: 0,
          type: button == null ? KeyType.analog : KeyType.button,
          key: '$page:$usage',
          value: normalized,
        ),
      ),
    );
  }

  void disconnect(String id) {
    _pads.remove(id);
    _syncDirection();
    if (!_pads.values.any(
      (p) => p.trigger || p.buttons.contains(GamepadButton.rightTrigger),
    )) {
      _stop(GamepadAction.quickTravel);
    }
  }

  void reset() {
    for (final timer in [..._delays.values, ..._repeats.values]) {
      timer.cancel();
    }
    _delays.clear();
    _repeats.clear();
    _pads.clear();
    _direction = null;
  }

  void dispose() {
    _disposed = true;
    reset();
  }
}

final class _PadState {
  final buttons = <GamepadButton>{};
  double x = 0, y = 0;
  bool trigger = false;
  GamepadAction? stickDirection;
}

/// 页面拥有订阅和生命周期。失焦时游戏可继续模拟，但实体手柄停止控制。
final class GamepadListener extends StatefulWidget {
  const GamepadListener({
    super.key,
    required this.onInput,
    required this.enabled,
    required this.child,
  });
  final ValueChanged<GamepadAction> onInput;
  final bool Function() enabled;
  final Widget child;
  @override
  State<GamepadListener> createState() => _GamepadListenerState();
}

final class _GamepadListenerState extends State<GamepadListener>
    with WidgetsBindingObserver {
  static final _hidEvents = const EventChannel(
    'bbk_flutter/hid_gamepad',
  ).receiveBroadcastStream();
  late final GamepadInputRouter _router;
  StreamSubscription<NormalizedGamepadEvent>? _events;
  StreamSubscription<GamepadConnectionEvent>? _connections;
  StreamSubscription<dynamic>? _hid;
  final _nativeIds = <String>{};
  bool _foreground = true;
  bool _enabled() =>
      mounted &&
      _foreground &&
      widget.enabled() &&
      ModalRoute.of(context)?.isCurrent != false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _router = GamepadInputRouter(
      onInput: (input) => widget.onInput(input),
      enabled: _enabled,
    );
    unawaited(_start());
  }

  Future<void> _start() async {
    _events = Gamepads.normalizedEvents.listen(
      _router.handle,
      onError: (_) => _router.reset(),
    );
    _connections = Gamepads.connectionEvents.listen((event) {
      if (event.type == GamepadConnectionEventType.connected) {
        _nativeIds.add(event.gamepadId);
      } else {
        _nativeIds.remove(event.gamepadId);
        _router.disconnect(event.gamepadId);
      }
      _router.setNativeControllers(_nativeIds);
    }, onError: (_) => _router.reset());
    try {
      final pads = await Gamepads.list();
      if (mounted) {
        _nativeIds.addAll(pads.map((p) => p.id));
        _router.setNativeControllers(_nativeIds);
      }
      for (final pad in pads) {
        await pad.dispose();
      }
    } on MissingPluginException {
      /* 无原生实现时继续支持键盘和屏幕按键。 */
    } on PlatformException {
      /* 枚举失败不阻断入口。 */
    }
    if (!mounted) return;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.macOS) {
      _hid = _hidEvents.listen(
        _router.handleHid,
        onError: (_) => _router.reset(),
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) _router.reset();
  }

  @override
  Widget build(BuildContext context) => widget.child;
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _router.dispose();
    unawaited(_events?.cancel());
    unawaited(_connections?.cancel());
    unawaited(_hid?.cancel());
    super.dispose();
  }
}

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../domain/models/game_definition.dart';

/// 平台工具服务，仅处理Android摇杆消息及窗口常亮，不处理游戏状态。
final class GamePlatformService {
  static const _events = EventChannel('sgby_flutter/controller');
  static const _methods = MethodChannel('sgby_flutter/platform');
  StreamSubscription<dynamic>? _subscription;
  bool _disposed = false;
  bool get _android =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  void start(void Function(GameInput) onInput) {
    if (!_android || _disposed || _subscription != null) return;
    _subscription = _events.receiveBroadcastStream().listen(
      (value) {
        if (_disposed || value is! String) return;
        final input = GameInput.fromWireValue(value);
        if (input != null) onInput(input);
      },
      onError: (Object _) {
        /* 实体键盘和屏幕按钮仍可独立使用。 */
      },
    );
  }

  Future<void> setScreenAwake(bool enabled) async {
    if (!_android || (_disposed && enabled)) return;
    try {
      await _methods.invokeMethod<void>('setScreenAwake', {'enabled': enabled});
    } on MissingPluginException {
      // 非标准宿主或测试环境没有平台注册时，不影响纯Dart游戏状态。
    } on PlatformException {
      // 窗口已经销毁的迟到调用不能影响退出流程。
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    final subscription = _subscription;
    _subscription = null;
    try {
      await subscription?.cancel();
    } on MissingPluginException {
      // 平台通道已随Activity释放。
    } on PlatformException {
      /* 引擎已分离。 */
    }
    await setScreenAwake(false);
  }
}

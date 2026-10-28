import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// 两款游戏共用的桌面窗口规则；窗口失焦不等于游戏暂停，移动端继续遵守生命周期。
abstract final class DesktopWindowService {
  static const _channel = MethodChannel('bbk_flutter/window');
  static bool get supported =>
      !kIsWeb &&
      const {
        TargetPlatform.macOS,
        TargetPlatform.windows,
      }.contains(defaultTargetPlatform);

  static bool runsIn(AppLifecycleState state) =>
      state != AppLifecycleState.detached &&
      (supported || state == AppLifecycleState.resumed);

  /// Esc由窗口处理，X/虚拟B仍为游戏取消；抬起及系统重复事件不再次最小化。
  static bool handleKey(KeyEvent event) {
    if (!supported || event.logicalKey != LogicalKeyboardKey.escape) {
      return false;
    }
    if (event is KeyDownEvent) unawaited(minimize());
    return true;
  }

  static Future<void> minimize() async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<void>('minimize');
    } on MissingPluginException {
      // 独立游戏或测试宿主未注册窗口通道时，不向游戏透传Esc造成误操作。
    } on PlatformException {
      // 窗口正在退出时忽略迟到请求。
    }
  }
}

/// 窗口快捷键先于路由和弹窗处理，避免Esc被对话框解释成“关闭”而误改游戏选择。
final class DesktopWindowShortcuts extends StatefulWidget {
  const DesktopWindowShortcuts({super.key, required this.child});
  final Widget child;
  @override
  State<DesktopWindowShortcuts> createState() => _DesktopWindowShortcutsState();
}

final class _DesktopWindowShortcutsState extends State<DesktopWindowShortcuts> {
  KeyEventResult _key(KeyEvent event) => DesktopWindowService.handleKey(event)
      ? KeyEventResult.handled
      : KeyEventResult.ignored;
  @override
  void initState() {
    super.initState();
    FocusManager.instance.addEarlyKeyEventHandler(_key);
  }

  @override
  void dispose() {
    FocusManager.instance.removeEarlyKeyEventHandler(_key);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

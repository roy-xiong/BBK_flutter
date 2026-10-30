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

  /// Esc交还游戏和当前弹窗处理，不再由宿主拦截或触发最小化。
  static bool handleKey(KeyEvent event) => false;

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

  static Future<void> _layoutTail = Future<void>.value();

  /// 串行处理方向/全屏请求，丢弃页面离开或被更新请求替代的旧操作。
  /// null解除首页竖屏锁；横屏隐藏系统栏，macOS进入原生全屏空间。
  static Future<void> applyGameLayout({
    required bool? portrait,
    required bool Function() isCurrent,
  }) {
    final task = _layoutTail.then((_) async {
      if (kIsWeb || !isCurrent()) return;
      try {
        if (defaultTargetPlatform == TargetPlatform.macOS) {
          if (portrait != null) {
            await _channel.invokeMethod<void>('setGameLayout', {
              'portrait': portrait,
            });
          }
        } else if (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.android) {
          await SystemChrome.setPreferredOrientations(
            portrait == null
                ? DeviceOrientation.values
                : portrait
                ? [DeviceOrientation.portraitUp]
                : [
                    DeviceOrientation.landscapeLeft,
                    DeviceOrientation.landscapeRight,
                  ],
          );
          if (!isCurrent()) return;
          await SystemChrome.setEnabledSystemUIMode(
            portrait == false
                ? SystemUiMode.immersiveSticky
                : SystemUiMode.edgeToEdge,
          );
        }
      } on MissingPluginException {
        // 无窗口通道的平台继续使用Flutter的自适应布局。
      } on PlatformException {
        // 系统拒绝切换时不让平台异常中断游戏会话。
      }
    });
    _layoutTail = task.catchError((Object error, StackTrace stack) {});
    return _layoutTail;
  }
}

/// 保留宿主包装接口；不注册全局按键监听，Esc遵循当前游戏或弹窗的返回语义。
final class DesktopWindowShortcuts extends StatelessWidget {
  const DesktopWindowShortcuts({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => child;
}

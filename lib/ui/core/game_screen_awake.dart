import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// 每个游戏路由/会话拥有一份租约；快速切换时旧页面释放不能关闭新页面的常亮。
/// 所有平台调用串行执行，应用后台或租约全部释放后恢复系统原有锁屏策略。
final class GameScreenAwakeController {
  static final _owners = <GameScreenAwakeController>{};
  static Future<void> _tail = Future.value();
  static bool _desired = false;
  Future<void> setEnabled(bool enabled) {
    if (enabled) {
      _owners.add(this);
    } else {
      _owners.remove(this);
    }
    final desired = _owners.isNotEmpty;
    if (desired == _desired) return _tail;
    _desired = desired;
    _tail = _tail.then((_) async {
      try {
        await WakelockPlus.toggle(enable: desired);
      } catch (error) {
        if (kDebugMode) debugPrint('屏幕常亮设置暂不可用：$error');
      }
    });
    return _tail;
  }
}

/// 两款游戏的宿主路由持有屏幕常亮，游戏内菜单仍属于同一租约。
final class GameScreenAwake extends StatefulWidget {
  const GameScreenAwake({super.key, required this.child});
  final Widget child;
  @override
  State<GameScreenAwake> createState() => _GameScreenAwakeState();
}

final class _GameScreenAwakeState extends State<GameScreenAwake>
    with WidgetsBindingObserver {
  final _controller = GameScreenAwakeController();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    unawaited(
      _controller.setEnabled(
        state == null || state == AppLifecycleState.resumed,
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      unawaited(_controller.setEnabled(state == AppLifecycleState.resumed));
  @override
  Widget build(BuildContext context) => widget.child;
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_controller.setEnabled(false));
    super.dispose();
  }
}

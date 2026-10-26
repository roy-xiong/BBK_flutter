import 'dart:async';

/// 不依赖窗口供帧的 macOS 游戏时钟，供窗口失焦、遮挡和最小化时继续推进逻辑。
///
/// Timer 回调在 UI isolate 串行执行，仍由 ViewModel 检查弹窗、存档和销毁状态。
/// 使用周期编号生成单调时间，恢复延迟由会话的 200ms 上限约束，不会无限追赶。
final class BackgroundGameClock {
  BackgroundGameClock(this.onTick);
  final void Function(Duration) onTick;
  static const _interval = Duration(milliseconds: 16);
  Timer? _timer;
  bool _disposed = false;

  void start() {
    if (_disposed || _timer != null) return;
    _timer = Timer.periodic(_interval, (timer) {
      if (!_disposed) {
        onTick(Duration(microseconds: _interval.inMicroseconds * timer.tick));
      }
    });
  }

  /// 页面退出必须取消时钟，避免 Timer 持有已销毁的 ViewModel。
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
  }
}

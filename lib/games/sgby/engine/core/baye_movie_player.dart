import 'dart:typed_data';

import '../rendering/baye_canvas.dart';
import '../resources/baye_picture.dart';

/// 动画的只读表现快照。卡通画面复用原动画帧号，不建立第二套计时器。
typedef BayeMovieVisual = ({
  int resource,
  int first,
  int last,
  int frame,
  int x,
  int y,
  String label,
  int? sourceType,
  int? targetType,
  bool sourceFriendly,
  bool targetFriendly,
  String effect,
});

/// PlcMovie的可暂停迭代状态，保留清除延时与推进延时两个独立计数。
///
/// step只推进一次原版循环，不创建Timer。会话根据返回的等待时间调度，输入、
/// 暂停或读档可以同步取消播放器，不会留下持有旧页面的异步回调。
final class BayeMoviePlayer {
  BayeMoviePlayer(
    this.animation, {
    this.x = 0,
    this.y = 0,
    this.keepBackground = false,
    this.resourceId = 0,
    this.label = '',
    this.sourceType,
    this.targetType,
    this.sourceFriendly = true,
    this.targetFriendly = false,
    this.effect = '',
    int first = 0,
    int? last,
  }) {
    _firstFrame = first.clamp(0, animation.endFrame);
    _frames = animation.frames.sublist(
      first.clamp(0, animation.endFrame),
      (last ?? animation.endFrame).clamp(
            first.clamp(0, animation.endFrame),
            animation.endFrame,
          ) +
          1,
    );
    _clear = Uint8List.fromList([
      for (final frame in _frames) frame.clearDelay,
    ]);
    _next = Uint8List.fromList([for (final frame in _frames) frame.nextDelay]);
  }

  final BayeAnimation animation;
  final int x;
  final int y;
  final bool keepBackground;
  final int resourceId;
  final String label;
  final int? sourceType, targetType;
  final bool sourceFriendly, targetFriendly;
  final String effect;
  late final int _firstFrame;

  /// 返回值不暴露可写播放器，暂停、倍率和动画开关均继续由原会话管理。
  BayeMovieVisual get visual => (
    resource: resourceId,
    first: _firstFrame,
    last: _firstFrame + _frames.length - 1,
    frame: _firstFrame + _previous,
    x: x,
    y: y,
    label: label,
    sourceType: sourceType,
    targetType: targetType,
    sourceFriendly: sourceFriendly,
    targetFriendly: targetFriendly,
    effect: effect,
  );
  late final List<BayeAnimationFrame> _frames;
  late final Uint8List _clear;
  late final Uint8List _next;
  int _current = 0;
  int _previous = 0;
  bool _clearRequested = true;
  bool _showRequested = true;
  bool finished = false;

  /// 返回(是否提交新画面, 下次迭代前等待微秒)。每个无绘制循环等待10毫秒。
  (bool, int) step(BayeCanvas canvas) {
    if (finished) return (false, 0);
    for (var i = 0; i <= _current; i++) {
      if (_clear[i] == 1) {
        if (!keepBackground) {
          final frame = _frames[i];
          final bitmap = animation.pictures[frame.pictureIndex];
          canvas.fill(
            x + frame.x,
            y + frame.y,
            x + frame.x + bitmap.width ~/ canvas.scale - 1,
            y + frame.y + bitmap.height ~/ canvas.scale - 1,
            0,
            resourceId,
          );
        }
        _clearRequested = true;
      }
      if (_clear[i] != 0) _clear[i]--;
    }
    if (_clearRequested) {
      for (var i = 0; i <= _previous; i++) {
        if (_clear[i] != 0) _draw(canvas, i);
      }
    }
    if (_showRequested) {
      for (var i = _previous + 1; i <= _current; i++) {
        if (_clear[i] != 0) _draw(canvas, i);
      }
      _previous = _current;
    }
    final changed = _showRequested || _clearRequested;
    _showRequested = false;
    _clearRequested = false;
    if (_next[_current] > 0) _next[_current]--;
    while (_next[_current] <= 1 && _current < _frames.length - 1) {
      _current++;
      _showRequested = true;
    }
    if (_current >= _frames.length - 1) {
      finished = true;
      for (var i = 0; i <= _current; i++) {
        if (_clear[i] > 1) {
          finished = false;
          break;
        }
      }
    }
    return (changed, changed ? 0 : 10000);
  }

  void _draw(BayeCanvas canvas, int index) {
    final frame = _frames[index];
    canvas.drawBitmap(
      animation.pictures[frame.pictureIndex],
      x + frame.x,
      y + frame.y,
      resource: resourceId,
      frame: _firstFrame + index,
    );
  }
}

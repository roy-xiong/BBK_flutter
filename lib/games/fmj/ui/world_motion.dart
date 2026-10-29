import 'dart:ui';
import 'package:flutter/foundation.dart';
import '../engine/game_actor.dart';
import '../engine/game_engine.dart';

/// 仅供显示的格间插值。真实人物、碰撞、事件、寻路和存档始终保留整数格坐标。
///
/// 每次逻辑移动从当前可见位置出发；快速连走或切换倍速也不会向旧起点回跳。
/// 切图、传送、战斗及关闭选项立即对齐。时钟可注入，测试无需等真实时间。
final class WorldMotion extends ChangeNotifier {
  WorldMotion({Duration Function()? clock}) {
    if (clock != null) {
      _clock = clock;
    } else {
      final stopwatch = Stopwatch()..start();
      _clock = () => stopwatch.elapsed;
    }
  }
  late final Duration Function() _clock;
  final Map<GameActor, _Step> _steps = {};
  String? _scene;
  bool _enabled = false, _disposed = false;
  double get _now => _clock().inMicroseconds / 1000;
  bool get moving =>
      !_disposed && _enabled && _steps.values.any((s) => s.progress(_now) < 1);

  Offset position(GameActor actor) => _enabled
      ? _steps[actor]?.sample(_now) ??
            Offset(actor.x.toDouble(), actor.y.toDouble())
      : Offset(actor.x.toDouble(), actor.y.toDouble());

  void capture(GameEngine game) {
    if (_disposed) return;
    final scene = '${game.map?.id}/${game.cursor?.script.id}';
    final enabled =
        game.preferences['smoothWalking'] == true &&
        game.screen == 'play' &&
        game.battle == null;
    final reset = !_enabled || !enabled || scene != _scene;
    _scene = scene;
    _enabled = enabled;
    final actors = {...game.npcs.values, ?game.player};
    _steps.removeWhere((actor, _) => !actors.contains(actor));
    final now = _now;
    var changed = reset;
    for (final actor in actors) {
      final target = Offset(actor.x.toDouble(), actor.y.toDouble()),
          previous = _steps[actor];
      if (reset || previous == null || (target - previous.to).distance > 1.01) {
        _steps[actor] = _Step(target, target, now, 0);
        changed = true;
      } else if (target != previous.to) {
        _steps[actor] = _Step(
          previous.sample(now),
          target,
          now,
          105 / game.runSpeed,
        );
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  /// 页面VSync只在插值尚未结束时调用，不建立后台Timer或不断重建整页。
  void pulse() {
    if (!_disposed) notifyListeners();
  }

  void settle() {
    if (_disposed) return;
    final now = _now;
    for (final actor in _steps.keys.toList()) {
      final target = Offset(actor.x.toDouble(), actor.y.toDouble());
      _steps[actor] = _Step(target, target, now, 0);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _steps.clear();
    super.dispose();
  }
}

final class _Step {
  const _Step(this.from, this.to, this.start, this.duration);
  final Offset from, to;
  final double start, duration;
  double progress(double now) =>
      duration <= 0 ? 1 : ((now - start) / duration).clamp(0.0, 1.0);
  Offset sample(double now) => Offset.lerp(from, to, progress(now)) ?? to;
}

import 'package:flutter/foundation.dart';
import '../../../../data/repositories/launcher_repository.dart';
import '../../../../domain/models/library_game.dart';

/// 首页只维护选择及路由互斥状态，不持有引擎、页面上下文或图像。
final class LauncherViewModel extends ChangeNotifier {
  LauncherViewModel(this.repository);
  final LauncherRepository repository;
  LibraryGame selected = LibraryGame.fmj;
  bool loading = true;
  bool opening = false;
  bool _disposed = false;

  Future<void> load() async {
    try {
      final previous = await repository.readSelection();
      if (!_disposed && previous != null) selected = previous;
    } catch (_) {
      // 首页偏好读取失败不影响打开游戏及各游戏自己的存档。
    } finally {
      if (!_disposed) {
        loading = false;
        notifyListeners();
      }
    }
  }

  void select(LibraryGame game) {
    if (_disposed || opening || selected == game) return;
    selected = game;
    notifyListeners();
  }

  bool beginOpening(LibraryGame game) {
    if (_disposed || opening) return false;
    selected = game;
    opening = true;
    notifyListeners();
    return true;
  }

  Future<void> rememberSelection() async {
    try {
      await repository.saveSelection(selected);
    } catch (_) {
      // 非关键偏好写入失败不阻断用户进入已经内置的游戏。
    }
  }

  void finishOpening() {
    if (_disposed) return;
    opening = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

import 'package:flutter/material.dart';
import 'data/repositories/launcher_repository.dart';
import 'games/fmj/data/save_repository.dart' as fmj;
import 'games/sgby/data/repositories/game_save_repository.dart' as sgby;
import 'ui/core/app_theme.dart';
import 'ui/core/desktop_window_service.dart';
import 'ui/features/launcher/views/launcher_page.dart';

/// 应用级存档仓库跨页面复用，确保快速退出、重进时仍遵守同一写入队列。
final class BbkApp extends StatefulWidget {
  const BbkApp({super.key});
  @override
  State<BbkApp> createState() => _BbkAppState();
}

final class _BbkAppState extends State<BbkApp> {
  final _launcher = LauncherRepository();
  final _fmj = fmj.SaveRepository();
  final _sgby = sgby.GameSaveRepository();

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '步步高经典游戏2',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.dark(),
    builder: (context, child) =>
        DesktopWindowShortcuts(child: child ?? const SizedBox.shrink()),
    home: LauncherPage(repository: _launcher, fmjSaves: _fmj, sgbySaves: _sgby),
  );
}

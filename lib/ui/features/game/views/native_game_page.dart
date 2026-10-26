import 'dart:async';
import 'package:flutter/material.dart';
import '../../../../domain/models/library_game.dart';
import '../../../../games/fmj/data/save_repository.dart' as fmj_data;
import '../../../../games/fmj/ui/game_page.dart' as fmj;
import '../../../../games/fmj/ui/game_view_model.dart' as fmj_vm;
import '../../../../games/sgby/data/repositories/game_save_repository.dart'
    as sgby_data;
import '../../../../games/sgby/ui/features/game/views/game_page.dart' as sgby;
import '../../../../games/sgby/ui/features/game/view_models/game_view_model.dart'
    as sgby_vm;
import '../../../../games/sgby/ui/core/app_theme.dart' as sgby_theme;

/// 一次路由只创建一款游戏；统一处理返回确认、会话暂停和资源所有权。
final class NativeGamePage extends StatefulWidget {
  const NativeGamePage({
    super.key,
    required this.game,
    required this.fmjSaves,
    required this.sgbySaves,
  });
  final LibraryGame game;
  final fmj_data.SaveRepository fmjSaves;
  final sgby_data.GameSaveRepository sgbySaves;
  @override
  State<NativeGamePage> createState() => _NativeGamePageState();
}

final class _NativeGamePageState extends State<NativeGamePage> {
  fmj_vm.GameViewModel? _fmj;
  sgby_vm.GameViewModel? _sgby;
  bool _asking = false;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    if (widget.game == LibraryGame.fmj) {
      final model = fmj_vm.GameViewModel(repository: widget.fmjSaves);
      _fmj = model;
      unawaited(model.initialize());
    } else {
      _sgby = sgby_vm.GameViewModel(
        saves: widget.sgbySaves,
        onExitRequested: () => _requestLeave(fromEngine: true),
      );
    }
  }

  Future<void> _requestLeave({bool fromEngine = false}) async {
    if (!mounted || _asking || _leaving) return;
    if (!fromEngine && _sgby?.isBusy == true) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('当前操作尚未完成，请稍后返回。')));
      return;
    }
    _asking = true;
    final fmjModel = _fmj;
    fmjModel?.setPaused(true);
    Future<void> confirmAndLeave() async {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('返回游戏库？'),
          content: Text(
            widget.game == LibraryGame.fmj
                ? '将保存当前可保存的进度与设置。'
                : '已保存的进度会保留。未保存的战局会结束，请先使用游戏内的存档功能。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('继续游戏'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('返回游戏库'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      await fmjModel?.persist(rethrowOnFailure: true);
      if (!mounted) return;
      setState(() => _leaving = true);
      // 先让 PopScope 接收新的 canPop，再发出 pop；防止程序化返回被自身拦截。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
    }

    try {
      final sgbyModel = _sgby;
      if (sgbyModel == null) {
        await confirmAndLeave();
      } else {
        await sgbyModel.withSgbyAutomationPaused(confirmAndLeave);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('保存失败，已保留当前游戏：$error')));
      }
    } finally {
      _asking = false;
      if (mounted && !_leaving) fmjModel?.setPaused(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmjModel = _fmj;
    final sgbyModel = _sgby;
    final Widget game;
    if (fmjModel != null) {
      game = Theme(
        data: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xffc6a56b),
            brightness: Brightness.dark,
          ),
          scaffoldBackgroundColor: const Color(0xff11191d),
          useMaterial3: true,
        ),
        child: fmj.GamePage(
          viewModel: fmjModel,
          onReturnToLibrary: _requestLeave,
        ),
      );
    } else if (sgbyModel != null) {
      game = AnimatedBuilder(
        animation: sgbyModel,
        builder: (context, _) => Theme(
          data: sgbyModel.cartoonEnabled
              ? ThemeData(
                  colorScheme: ColorScheme.fromSeed(
                    seedColor: const Color(0xff3d8b85),
                  ),
                  useMaterial3: true,
                  scaffoldBackgroundColor: const Color(0xffeef6ed),
                  appBarTheme: const AppBarTheme(
                    backgroundColor: Color(0xfffffcf2),
                    foregroundColor: Color(0xff29475b),
                  ),
                )
              : sgby_theme.AppTheme.dark(),
          child: sgby.GamePage(
            viewModel: sgbyModel,
            onReturnToLibrary: _requestLeave,
          ),
        ),
      );
    } else {
      game = const Scaffold(body: Center(child: Text('游戏暂不可用')));
    }
    return PopScope(
      canPop: _leaving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_requestLeave());
      },
      child: game,
    );
  }

  @override
  void dispose() {
    _fmj?.dispose();
    _sgby?.dispose();
    super.dispose();
  }
}

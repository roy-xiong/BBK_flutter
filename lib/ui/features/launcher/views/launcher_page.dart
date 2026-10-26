import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../data/repositories/launcher_repository.dart';
import '../../../../domain/models/library_game.dart';
import '../../../../games/fmj/data/save_repository.dart' as fmj;
import '../../../../games/sgby/data/repositories/game_save_repository.dart'
    as sgby;
import '../../../core/image_manager.dart';
import '../../game/views/native_game_page.dart';
import '../view_models/launcher_view_model.dart';

/// 沿用 BBK 的竖向游戏库及双列方形封面，窄窗口、放大字体时自然换行。
final class LauncherPage extends StatefulWidget {
  const LauncherPage({
    super.key,
    required this.repository,
    required this.fmjSaves,
    required this.sgbySaves,
  });
  final LauncherRepository repository;
  final fmj.SaveRepository fmjSaves;
  final sgby.GameSaveRepository sgbySaves;
  @override
  State<LauncherPage> createState() => _LauncherPageState();
}

final class _LauncherPageState extends State<LauncherPage> {
  late final LauncherViewModel _model;
  @override
  void initState() {
    super.initState();
    _model = LauncherViewModel(widget.repository);
    unawaited(_model.load());
    unawaited(_restoreChrome());
  }

  /// 桌面不调用移动平台方向接口；从游戏返回后恢复首页竖屏与系统边栏。
  Future<void> _restoreChrome() async {
    if (kIsWeb ||
        !{
          TargetPlatform.android,
          TargetPlatform.iOS,
        }.contains(defaultTargetPlatform)) {
      return;
    }
    try {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
      if (!mounted) return;
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    } on PlatformException {
      // 平台拒绝方向请求时继续展示自适应首页。
    }
  }

  Future<void> _open(LibraryGame game) async {
    if (!mounted || !_model.beginOpening(game)) return;
    try {
      unawaited(_model.rememberSelection());
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => NativeGamePage(
            game: game,
            fmjSaves: widget.fmjSaves,
            sgbySaves: widget.sgbySaves,
          ),
        ),
      );
    } finally {
      if (mounted) {
        _model.finishOpening();
        await _restoreChrome();
      }
    }
  }

  void _about() => showAboutDialog(
    context: context,
    applicationName: '步步高经典游戏2',
    applicationVersion: const String.fromEnvironment(
      'BBK_VERSION',
      defaultValue: '1.0.0',
    ),
    applicationIcon: SizedBox(
      width: 56,
      height: 56,
      child: ImageManager.asset('assets/branding/icon-light.png'),
    ),
    children: [const Text('伏魔记 · 三国霸业\n点击封面开始游戏。画风、按键映射和存档可在各游戏内设置。')],
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('步步高经典游戏2'),
      actions: [
        IconButton(
          tooltip: '关于与设置说明',
          onPressed: _about,
          icon: const Icon(Icons.settings_outlined),
        ),
      ],
    ),
    body: SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: ListenableBuilder(
            listenable: _model,
            builder: (context, _) {
              if (_model.loading) {
                return const Center(child: CircularProgressIndicator());
              }
              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '选择游戏',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        Text(
                          '2 款',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '点击封面直接进入游戏',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 22),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        const spacing = 16.0;
                        final columns = constraints.maxWidth >= 260 ? 2 : 1;
                        final width =
                            (constraints.maxWidth - spacing * (columns - 1)) /
                            columns;
                        return FocusTraversalGroup(
                          child: Wrap(
                            spacing: spacing,
                            runSpacing: 18,
                            children: [
                              for (final game in LibraryGame.values)
                                SizedBox(
                                  width: width,
                                  child: _GameTile(
                                    game: game,
                                    selected: game == _model.selected,
                                    onSelect: _model.opening
                                        ? null
                                        : () => _model.select(game),
                                    onOpen: _model.opening
                                        ? null
                                        : () => _open(game),
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    ),
  );

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }
}

/// 封面保持完整比例；高亮边框等宽，鼠标、触摸、键盘均使用同一个入口。
final class _GameTile extends StatelessWidget {
  const _GameTile({
    required this.game,
    required this.selected,
    required this.onSelect,
    required this.onOpen,
  });
  final LibraryGame game;
  final bool selected;
  final VoidCallback? onSelect;
  final VoidCallback? onOpen;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: '进入${game.title}',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AspectRatio(
          aspectRatio: 1,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected
                    ? const Color(0xff53e2d1)
                    : const Color(0xff303438),
                width: 3,
              ),
            ),
            child: Material(
              color: Colors.black,
              borderRadius: BorderRadius.circular(6),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onOpen,
                onFocusChange: (focused) {
                  if (focused) onSelect?.call();
                },
                child: ImageManager.asset(game.coverAsset),
              ),
            ),
          ),
        ),
        const SizedBox(height: 9),
        Text(
          game.title,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 3),
        Text(
          game.subtitle,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    ),
  );
}

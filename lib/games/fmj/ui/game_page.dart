import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../engine/game_engine.dart';
import '../engine/pixel_surface.dart';
import 'game_view_model.dart';
import 'game_controls.dart';
import 'modern_game_view.dart';
import 'system_font_layout.dart';
import 'game_keyboard_bindings.dart';
import 'game_keyboard_mapping_sheet.dart';
import 'game_cheat_panel.dart';
import 'package:bbk_flutter/ui/core/desktop_window_service.dart';

/// 页面只管理输入、生命周期与面板；所有游戏结果由 GameEngine 决定。
final class GamePage extends StatefulWidget {
  const GamePage({super.key, this.viewModel, this.onReturnToLibrary});

  /// 合集宿主提供的返回入口；独立运行时继续使用游戏标题页。
  final Future<void> Function()? onReturnToLibrary;
  final GameViewModel? viewModel;
  @override
  State<GamePage> createState() => _GamePageState();
}

final class _GamePageState extends State<GamePage> with WidgetsBindingObserver {
  late final GameViewModel model;
  bool _sheetOpen = false, _foreground = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    model = widget.viewModel ?? GameViewModel();
    if (widget.viewModel == null) unawaited(model.initialize());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = DesktopWindowService.runsIn(state);
    if (state != AppLifecycleState.resumed) {
      _stopQuickTravel();
      model.releaseHeldKeys();
    }
    model.setPaused(!_foreground || _sheetOpen);
    model.setWindowVisible(
      state == AppLifecycleState.resumed || state == AppLifecycleState.inactive,
    );
  }

  @override
  void dispose() {
    _stopQuickTravel();
    WidgetsBinding.instance.removeObserver(this);
    unawaited(model.persist());
    if (widget.viewModel == null) model.dispose();
    super.dispose();
  }

  Future<void> _sheet(Widget child, {bool compact = false}) async {
    if (_sheetOpen) return;
    _stopQuickTravel();
    _sheetOpen = true;
    model.setPaused(true);
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        useSafeArea: true,
        backgroundColor: const Color(0xff1b272d),
        builder: (context) => compact
            ? child
            : SizedBox(
                height: math.min(MediaQuery.sizeOf(context).height * .85, 720),
                child: child,
              ),
      );
    } finally {
      _sheetOpen = false;
      if (mounted) model.setPaused(!_foreground);
    }
  }

  KeyEventResult _keyboard(FocusNode node, KeyEvent event) {
    if (DesktopWindowService.handleKey(event)) return KeyEventResult.handled;
    if (_sheetOpen) return KeyEventResult.ignored;
    final code = GameKeyboardBindings.codeFor(event.physicalKey);
    final action = code == null ? null : model.keyboardBindings.actionFor(code);
    if (action == null) return KeyEventResult.ignored;
    final gameKey = action.index < GameKey.values.length
        ? GameKey.values[action.index]
        : null;
    if (gameKey != null) {
      if (event is KeyDownEvent) model.down(gameKey);
      if (event is KeyUpEvent) model.up(gameKey);
    } else if (action == GameControl.quickTravel) {
      if (event is KeyDownEvent) _startQuickTravel();
      if (event is KeyUpEvent) _stopQuickTravel();
    } else if (event is KeyDownEvent) {
      _control(action);
    }
    return KeyEventResult.handled;
  }

  Future<void> _keyMapping() async {
    if (_sheetOpen) return;
    _stopQuickTravel();
    _sheetOpen = true;
    model.setPaused(true);
    try {
      await showGameKeyboardMappingSheet(context, model);
    } finally {
      _sheetOpen = false;
      if (mounted) model.setPaused(!_foreground);
    }
  }

  Future<void> _leaveGame() async {
    _stopQuickTravel();
    final returnToLibrary = widget.onReturnToLibrary;
    if (returnToLibrary != null) {
      await returnToLibrary();
      return;
    }
    if (_sheetOpen) return;
    _sheetOpen = true;
    model.setPaused(true);
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('退出游戏？'),
          content: const Text('保留最近的存档并返回标题。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('继续游戏'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('退出'),
            ),
          ],
        ),
      );
      if (confirmed == true && mounted) {
        await model.persist();
        model.action((g) {
          g.navigation.cancel();
          g.menus.clear();
          g.operation = null;
          g.battle = null;
          g.screen = 'title';
          g.intro = null;
        });
      }
    } finally {
      _sheetOpen = false;
      if (mounted) model.setPaused(!_foreground);
    }
  }

  Offset? _toolbarPosition;
  Offset? _toolbarDragOrigin, _toolbarPointerOrigin;
  Timer? _quickTravelDelay, _quickTravelRepeat;
  bool _quickTravelHeld = false;

  /// 与方向键一致：320ms识别长按，之后按真实时间105ms连续触发，松开或失焦即清理。
  void _startQuickTravel() {
    if (_quickTravelHeld) return;
    _quickTravelHeld = true;
    _control(GameControl.quickTravel);
    _quickTravelDelay = Timer(const Duration(milliseconds: 320), () {
      if (!mounted || !_quickTravelHeld || _sheetOpen || model.paused) return;
      _control(GameControl.quickTravel);
      _quickTravelRepeat = Timer.periodic(const Duration(milliseconds: 105), (
        _,
      ) {
        if (mounted && _quickTravelHeld && !_sheetOpen && !model.paused) {
          _control(GameControl.quickTravel);
        }
      });
    });
  }

  void _stopQuickTravel() {
    _quickTravelHeld = false;
    _quickTravelDelay?.cancel();
    _quickTravelDelay = null;
    _quickTravelRepeat?.cancel();
    _quickTravelRepeat = null;
  }

  /// 控制区只分发命令；按钮长按延迟 320ms，之后每 105ms 重复，完全沿用原版。
  void _control(GameControl input) {
    if (input.index < GameKey.values.length) {
      model.press(GameKey.values[input.index]);
      return;
    }
    switch (input) {
      case GameControl.quickTravel:
        model.action((g) {
          if (g.screen != 'play' ||
              g.battle != null ||
              g.operation != null ||
              g.cursor?.running == true ||
              g.menus.isNotEmpty) {
            g.press(GameKey.confirm);
          } else if (!g.navigation.planning && g.navigation.active == null) {
            unawaited(g.navigation.startGoal());
          }
        });
      case GameControl.selectFmjStage:
        _sheet(_StagePanel(model: model));
      case GameControl.cycleFmjRunSpeed:
        model.action(
          (g) => g.setPreference(
            'runSpeed',
            (g.preferences['runSpeed'] as int? ?? 1) % 4 + 1,
          ),
        );
      case GameControl.toggleFmjAutoBattle:
        model.action(
          (g) => g.setPreference(
            'autoBattle',
            g.preferences['autoBattle'] != true,
          ),
        );
      case GameControl.toggleWideView:
        model.action((g) => g.setPreference('wideView', !g.wide));
      case GameControl.search:
        model.press(GameKey.pageUp);
      case GameControl.help:
        model.press(GameKey.pageDown);
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) => Focus(
    autofocus: true,
    onKeyEvent: _keyboard,
    child: AnimatedBuilder(
      animation: model,
      builder: (context, _) {
        final game = model.engine,
            modern = game?.preferences['modernUi'] == true,
            dark = game?.preferences['darkControls'] != false,
            controlsVisible = game?.preferences['controlsVisible'] != false;
        final desktop = {
          TargetPlatform.macOS,
          TargetPlatform.windows,
          TargetPlatform.linux,
        }.contains(Theme.of(context).platform);
        return Scaffold(
          backgroundColor: Colors.black,
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final portrait = game?.preferences['manualLayout'] == true
                    ? game?.preferences['portraitControls'] == true
                    : constraints.maxHeight >= constraints.maxWidth;
                final sceneHeight = math.min(
                  constraints.maxWidth * 3 / 5,
                  constraints.maxHeight * .48,
                );
                final gameWidth = sceneHeight * 5 / 3;
                final gameHeight =
                    sceneHeight +
                    (modern ? ModernGameView.informationHeight(gameWidth) : 0);
                // 原版悬浮按键占地不变；新版画面在横屏时避开两侧输入区，避免血条和
                // 目标被十字键、A/B 及辅助按钮遮住。关闭屏幕按键后恢复完整画面。
                final sideButton = (constraints.biggest.shortestSide * .14)
                    .clamp(46.0, 68.0);
                final sideGap = (sideButton * .12).clamp(6.0, 10.0);
                final leftInputWidth = 18 + sideButton * 3 + sideGap * 2 + 12;
                const rightInputWidth = 18 + 280.0 + 12;
                final insetModern =
                    modern &&
                    !portrait &&
                    controlsVisible &&
                    constraints.maxWidth - leftInputWidth - rightInputWidth >=
                        240;
                final modernWidth =
                    constraints.maxWidth - leftInputWidth - rightInputWidth;
                final modernHeight = math.min(
                  constraints.maxHeight,
                  modernWidth * 3 / 5 +
                      ModernGameView.informationHeight(modernWidth),
                );
                final toolbarWidth = math.min(constraints.maxWidth - 16, 396.0);
                final toolbar = _toolbarPosition ?? const Offset(8, 8);
                final toolbarX = toolbar.dx.clamp(
                      0.0,
                      math.max(0.0, constraints.maxWidth - toolbarWidth),
                    ),
                    toolbarY = toolbar.dy.clamp(
                      0.0,
                      math.max(0.0, constraints.maxHeight - 44),
                    );
                Widget surface;
                if (model.loading) {
                  surface = const Center(child: CircularProgressIndicator());
                } else if (model.failure != null ||
                    game?.error.isNotEmpty == true) {
                  surface = Center(
                    child: SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(model.failure ?? game?.error ?? ''),
                      ),
                    ),
                  );
                } else {
                  surface = modern
                      ? LayoutBuilder(
                          builder: (context, available) {
                            final width = math.min(
                              available.maxWidth,
                              math.max(
                                    0.0,
                                    available.maxHeight -
                                        ModernGameView.informationHeight(
                                          available.maxWidth,
                                        ),
                                  ) *
                                  5 /
                                  3,
                            );
                            return Center(
                              child: SizedBox(
                                width: width,
                                height:
                                    width * 3 / 5 +
                                    ModernGameView.informationHeight(width),
                                child: RepaintBoundary(
                                  child: ModernGameView(model: model),
                                ),
                              ),
                            );
                          },
                        )
                      : Center(
                          child: AspectRatio(
                            aspectRatio: 5 / 3,
                            child: RepaintBoundary(
                              child: _ClassicGameView(model: model),
                            ),
                          ),
                        );
                }
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    ColoredBox(
                      color: dark
                          ? const Color(0xff1b1e22)
                          : const Color(0xffd8d5cd),
                    ),
                    Positioned(
                      key: const ValueKey('game-surface-layout'),
                      left: portrait
                          ? (constraints.maxWidth - gameWidth) / 2
                          : insetModern
                          ? leftInputWidth
                          : 0,
                      top: insetModern
                          ? (constraints.maxHeight - modernHeight) / 2
                          : 0,
                      width: portrait
                          ? gameWidth
                          : insetModern
                          ? modernWidth
                          : constraints.maxWidth,
                      height: portrait
                          ? gameHeight
                          : insetModern
                          ? modernHeight
                          : constraints.maxHeight,
                      child: ColoredBox(color: Colors.black, child: surface),
                    ),
                    if (game != null && controlsVisible && portrait)
                      Positioned(
                        top: gameHeight,
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: PortraitGameControlsPanel(
                          isDarkTheme: dark,
                          onInput: _control,
                          hapticsEnabled:
                              game.preferences['hapticsEnabled'] != false,
                          fmjWideViewEnabled: game.wide,
                          fmjAutoBattleEnabled:
                              game.preferences['autoBattle'] == true,
                          fmjRunSpeed:
                              game.preferences['runSpeed'] as int? ?? 1,
                        ),
                      ),
                    if (game != null && controlsVisible && !portrait)
                      GameControlsOverlay(
                        onInput: _control,
                        hapticsEnabled:
                            game.preferences['hapticsEnabled'] != false,
                        fmjWideViewEnabled: game.wide,
                        fmjAutoBattleEnabled:
                            game.preferences['autoBattle'] == true,
                        fmjRunSpeed: game.preferences['runSpeed'] as int? ?? 1,
                      ),
                    if (game != null)
                      Positioned(
                        left: toolbarX.toDouble(),
                        top: toolbarY.toDouble(),
                        child: GestureDetector(
                          dragStartBehavior: DragStartBehavior.down,
                          onPanStart: (details) {
                            _toolbarDragOrigin = Offset(
                              toolbarX.toDouble(),
                              toolbarY.toDouble(),
                            );
                            _toolbarPointerOrigin = details.globalPosition;
                          },
                          onPanUpdate: (details) => setState(() {
                            // 使用起点和全局指针差，避免同一帧多次事件引用旧布局位置，
                            // 也避免控件移动后其局部坐标系变化造成拖动回弹。
                            final origin = _toolbarDragOrigin,
                                pointer = _toolbarPointerOrigin;
                            if (origin == null || pointer == null) return;
                            final next =
                                origin + details.globalPosition - pointer;
                            _toolbarPosition = Offset(
                              next.dx.clamp(
                                0.0,
                                math.max(
                                  0.0,
                                  constraints.maxWidth - toolbarWidth,
                                ),
                              ),
                              next.dy.clamp(
                                0.0,
                                math.max(0.0, constraints.maxHeight - 44),
                              ),
                            );
                          }),
                          onPanEnd: (_) {
                            _toolbarDragOrigin = null;
                            _toolbarPointerOrigin = null;
                          },
                          onPanCancel: () {
                            _toolbarDragOrigin = null;
                            _toolbarPointerOrigin = null;
                          },
                          child: SizedBox(
                            width: toolbarWidth,
                            height: 44,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: const Color(0x99000000),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    _tool(
                                      '返回游戏选择',
                                      Icons.arrow_back,
                                      () => unawaited(_leaveGame()),
                                    ),
                                    _tool(
                                      '打开存档界面',
                                      Icons.save,
                                      () =>
                                          model.action((g) => g.openSaveMenu()),
                                    ),
                                    _tool(
                                      '控制设置',
                                      Icons.settings,
                                      () => _sheet(
                                        _SettingsPanel(model: model),
                                        compact: true,
                                      ),
                                    ),
                                    _tool(
                                      '作弊系统',
                                      Icons.auto_fix_high,
                                      () =>
                                          _sheet(GameCheatPanel(model: model)),
                                    ),
                                    _tool(
                                      '剧情帮助与任务',
                                      Icons.map,
                                      () => _sheet(_GuidePanel(model: model)),
                                    ),
                                    _tool(
                                      game.preferences['hd'] == true
                                          ? '切换经典画质'
                                          : '切换高清画质',
                                      Icons.hd,
                                      () => model.action(
                                        (g) => g.setPreference(
                                          'hd',
                                          g.preferences['hd'] != true,
                                        ),
                                      ),
                                      active: game.preferences['hd'] == true,
                                    ),
                                    _tool(
                                      '切换控制区明暗主题',
                                      Icons.brightness_6,
                                      () => model.action(
                                        (g) => g.setPreference(
                                          'darkControls',
                                          !dark,
                                        ),
                                      ),
                                    ),
                                    _tool(
                                      desktop
                                          ? '键盘映射'
                                          : portrait
                                          ? '切换横屏'
                                          : '切换竖屏',
                                      desktop
                                          ? Icons.keyboard
                                          : portrait
                                          ? Icons.stay_current_landscape
                                          : Icons.stay_current_portrait,
                                      () {
                                        if (desktop) {
                                          unawaited(_keyMapping());
                                        } else {
                                          unawaited(
                                            SystemChrome.setPreferredOrientations(
                                              portrait
                                                  ? [
                                                      DeviceOrientation
                                                          .landscapeLeft,
                                                      DeviceOrientation
                                                          .landscapeRight,
                                                    ]
                                                  : [
                                                      DeviceOrientation
                                                          .portraitUp,
                                                    ],
                                            ),
                                          );
                                          model.action(
                                            (g) => g.setPreference(
                                              'manualLayout',
                                              false,
                                            ),
                                          );
                                        }
                                      },
                                    ),
                                    _tool(
                                      modern ? '切换经典 UI' : '切换仙侠新版',
                                      Icons.auto_awesome,
                                      () async {
                                        // 完成解码后再切换，避免首次切换出现半幅画面或空底。
                                        if (!modern &&
                                            model.modernArt == null) {
                                          await model.prepareModernArt();
                                          if (!mounted ||
                                              model.modernArt == null) {
                                            return;
                                          }
                                        }
                                        model.action(
                                          (g) => g.setPreference(
                                            'modernUi',
                                            !modern,
                                          ),
                                        );
                                      },
                                      active: modern,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (game?.notice.isNotEmpty == true)
                      Positioned(
                        left: 12,
                        right: 12,
                        bottom: 4,
                        child: IgnorePointer(
                          child: Center(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: const Color(0xb3000000),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                child: Text(
                                  game?.notice ?? '',
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Color(0xffe0ce9a),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        );
      },
    ),
  );

  Widget _tool(
    String label,
    IconData icon,
    VoidCallback onPressed, {
    bool active = false,
  }) => IconButton(
    tooltip: label,
    constraints: const BoxConstraints.tightFor(width: 44, height: 44),
    padding: EdgeInsets.zero,
    onPressed: onPressed,
    icon: Icon(icon, color: active ? const Color(0xffffd166) : Colors.white),
  );
}

final class _ClassicGameView extends StatelessWidget {
  const _ClassicGameView({required this.model});
  final GameViewModel model;
  @override
  Widget build(BuildContext context) {
    final game = model.engine, expected = game?.operation;
    final box = game != null && expected != null
        ? game.choiceLayout(expected)
        : null;
    final width = model.imageLogicalWidth, height = model.imageLogicalHeight;
    return LayoutBuilder(
      builder: (context, constraints) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (details) {
          if (game == null ||
              expected == null ||
              !identical(game.operation, expected) ||
              width != (game.wide ? 320 : 160)) {
            return;
          }
          if (expected.kind == 'choice' || expected.kind == 'menu') {
            if (box == null) return;
            final x = details.localPosition.dx * width / constraints.maxWidth,
                y = details.localPosition.dy * height / constraints.maxHeight;
            if (x < box.left ||
                x > box.right ||
                y < box.top ||
                y > box.top + box.rows * box.rowHeight + 8) {
              return;
            }
            final index =
                box.first +
                ((y - box.top - 4) / box.rowHeight)
                    .floor()
                    .clamp(0, math.max(0, box.rows - 1))
                    .toInt();
            model.action((g) => g.choose(index, expected: expected));
          } else if (['dialogue', 'message', 'timed'].contains(expected.kind)) {
            model.press(GameKey.confirm);
          }
        },
        child: CustomPaint(
          painter: ClassicFramePainter(
            model.image,
            model.textRuns,
            width,
            height,
            game?.preferences['hd'] == true,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

/// 原始图像使用最近邻采样，文字由 Flutter 系统字体在相同逻辑坐标合成。
final class ClassicFramePainter extends CustomPainter {
  const ClassicFramePainter(
    this.image,
    this.text,
    this.width,
    this.height,
    this.hd,
  );
  final ui.Image? image;
  final List<SystemTextRun> text;
  final int width, height;
  final bool hd;
  @override
  void paint(Canvas canvas, Size size) {
    final image = this.image;
    if (image == null) return;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Offset.zero & size,
      Paint()..filterQuality = FilterQuality.none,
    );
    canvas.scale(size.width / width, size.height / height);
    for (final run in text) {
      final color = run.selected
          ? (hd ? const Color(0xffd8d8cf) : const Color(0xffb4b4b4))
          : (hd ? const Color(0xff181b1d) : Colors.black);
      final painter = TextPainter(
        text: TextSpan(
          text: run.text,
          style: FlutterSystemFontLayout.style(
            color: color,
          ).copyWith(fontSize: run.fontSize),
        ),
        textDirection: TextDirection.ltr,
        strutStyle: StrutStyle(
          fontSize: run.fontSize,
          height: 16 / 14,
          forceStrutHeight: true,
        ),
        maxLines: math.max(1, (run.height / (16 * run.fontSize / 14)).floor()),
      );
      painter.layout(maxWidth: run.width.toDouble());
      canvas.save();
      canvas.clipRect(
        Rect.fromLTWH(
          run.x.toDouble(),
          run.y.toDouble(),
          run.width.toDouble(),
          run.height.toDouble(),
        ),
      );
      if (run.selected) {
        canvas.drawRect(
          Rect.fromLTWH(
            run.x.toDouble(),
            run.y.toDouble(),
            painter.width,
            painter.height,
          ),
          Paint()..color = (hd ? const Color(0xff181b1d) : Colors.black),
        );
      }
      final hidden = run.hiddenRows.toList()..sort();
      for (var i = 0; i < hidden.length; i++) {
        final first = hidden[i];
        var last = first;
        while (i + 1 < hidden.length && hidden[i + 1] == last + 1) {
          i++;
          last = hidden[i];
        }
        canvas.clipRect(
          Rect.fromLTWH(
            run.x.toDouble(),
            first.toDouble(),
            run.width.toDouble(),
            (last - first + 1).toDouble(),
          ),
          clipOp: ui.ClipOp.difference,
          doAntiAlias: false,
        );
      }
      painter.paint(canvas, Offset(run.x.toDouble(), run.y.toDouble()));
      canvas.restore();
      painter.dispose();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant ClassicFramePainter old) =>
      image != old.image ||
      text != old.text ||
      width != old.width ||
      hd != old.hd;
}

final class _StagePanel extends StatefulWidget {
  const _StagePanel({required this.model});
  final GameViewModel model;
  @override
  State<_StagePanel> createState() => _StagePanelState();
}

final class _StagePanelState extends State<_StagePanel> {
  String filter = '';
  @override
  Widget build(BuildContext context) {
    final stages =
        widget.model.engine?.data.stages
            .where(
              (s) =>
                  '${s['title']}${s['scene']}${s['chapter']}'.contains(filter),
            )
            .toList() ??
        [];
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const Text('故事选关', style: TextStyle(fontSize: 21)),
          const SizedBox(height: 12),
          TextField(
            decoration: const InputDecoration(
              hintText: '搜索主线、支线与机关',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (v) => setState(() => filter = v),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ListView.builder(
              itemCount: stages.length,
              itemBuilder: (context, i) {
                final stage = stages[i];
                return ListTile(
                  title: Text(stage['title'] as String),
                  subtitle: Text(
                    '${stage['chapter']} · ${stage['scene']}',
                    style: const TextStyle(fontSize: 11),
                  ),
                  trailing: Text(
                    stage['kind'] as String,
                    style: const TextStyle(
                      color: Color(0xffc6ac77),
                      fontSize: 11,
                    ),
                  ),
                  onTap: () {
                    widget.model.action((g) => g.selectStage(stage));
                    Navigator.pop(context);
                  },
                );
              },
            ),
          ),
          TextButton(
            onPressed: () {
              widget.model.action((g) => g.restoreBeforeStage());
              Navigator.pop(context);
            },
            child: const Text('恢复选关前的进度'),
          ),
        ],
      ),
    );
  }
}

/// 控制设置只保留 BBK 对应的屏幕按键、震动和高清画质三项。
final class _SettingsPanel extends StatelessWidget {
  const _SettingsPanel({required this.model});
  final GameViewModel model;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: model,
    builder: (context, _) {
      final game = model.engine;
      if (game == null) return const SizedBox.shrink();
      return SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final entry in [
                ('controlsVisible', '屏幕按键', Icons.sports_esports),
                ('hapticsEnabled', '按键震动', Icons.vibration),
                ('hd', '角色扮演游戏高清画质', Icons.hd),
              ])
                SwitchListTile(
                  secondary: Icon(entry.$3),
                  title: Text(entry.$2),
                  value: game.preferences[entry.$1] == true,
                  onChanged: (value) =>
                      model.action((g) => g.setPreference(entry.$1, value)),
                ),
            ],
          ),
        ),
      );
    },
  );
}

final class _GuidePanel extends StatelessWidget {
  const _GuidePanel({required this.model});
  final GameViewModel model;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: model,
    builder: (context, _) {
      final game = model.engine;
      if (game == null) return const SizedBox.shrink();
      final goal = game.navigation.nextGoal;
      void go(GameGoal goal) {
        Navigator.pop(context);
        model.action((g) => unawaited(g.navigation.startGoal(goal)));
      }

      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('江湖见闻', style: TextStyle(fontSize: 21)),
          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '当前目标',
                    style: TextStyle(fontSize: 11, color: Colors.white54),
                  ),
                  const SizedBox(height: 7),
                  Text(goal.label, style: const TextStyle(fontSize: 18)),
                  const SizedBox(height: 7),
                  Text(goal.hint, style: const TextStyle(fontSize: 12)),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: () => go(goal),
                    icon: const Icon(Icons.route),
                    label: const Text('前往当前目标'),
                  ),
                ],
              ),
            ),
          ),
          SwitchListTile(
            title: const Text('完整流程：包含支线与分支'),
            value: game.preferences['storyScope'] == 'complete',
            onChanged: (value) => model.action(
              (g) => g.setPreference('storyScope', value ? 'complete' : 'main'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              '万能钥匙 ${game.inventory['14:2'] ?? 0} 把 · 引路石 ${game.inventory['13:1'] ?? 0} 颗',
              style: const TextStyle(color: Color(0xffc9b284)),
            ),
          ),
          for (final task in game.navigation.sideGoals)
            ListTile(
              title: Text(task.label, style: const TextStyle(fontSize: 13)),
              subtitle: Text(
                '${task.done
                    ? '已完成'
                    : task.ready
                    ? '可前往'
                    : '前置条件或剧情窗口不满足'} · ${task.hint}',
                style: const TextStyle(fontSize: 11),
              ),
              trailing: task.ready
                  ? IconButton(
                      icon: const Icon(Icons.near_me_outlined),
                      onPressed: () => go(task),
                    )
                  : Icon(
                      task.done
                          ? Icons.check_circle_outline
                          : Icons.lock_outline,
                      size: 17,
                      color: task.done ? Colors.greenAccent : Colors.white30,
                    ),
            ),
        ],
      );
    },
  );
}

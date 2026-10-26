import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../../../domain/models/game_definition.dart';
import '../../../../engine/core/native_game_session.dart';
import '../../../core/background_game_clock.dart';
import '../../../../engine/rendering/modern_game_painter.dart';
import '../../../../engine/rendering/realistic_game_painter.dart';
import 'cartoon_status_panel.dart';
import 'game_keyboard_sheet.dart';
import '../view_models/game_view_model.dart';
import 'game_controls_overlay.dart';
import 'game_general_roster_sheet.dart';
import 'game_cheat_sheet.dart';
import 'game_search_history_sheet.dart';
import 'game_enemy_city_sheet.dart';

/// 独立游戏入口，原版画面与复用的宿主控制区分开布局。
final class GamePage extends StatefulWidget {
  const GamePage({super.key, this.viewModel, this.onReturnToLibrary});

  /// 返回合集游戏库，隐藏控制区时也保留菜单入口。
  final Future<void> Function()? onReturnToLibrary;
  final GameViewModel? viewModel;
  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final GameViewModel _viewModel;
  Ticker? _ticker;
  BackgroundGameClock? _backgroundClock;
  final FocusNode _focus = FocusNode(debugLabel: 'sgby-input');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _viewModel = widget.viewModel ?? GameViewModel();
    _viewModel.onUiRequest = _handleRequest;
    _viewModel.addListener(_onStateChanged);
    if (_viewModel.usesBackgroundClock) {
      _backgroundClock = BackgroundGameClock(_viewModel.tick)..start();
    } else {
      _ticker = createTicker(_viewModel.tick)..start();
    }
    if (!_viewModel.isReady) unawaited(_viewModel.initialize());
  }

  void _onStateChanged() {
    if (!mounted) return;
    final notice = _viewModel.takeNotice();
    if (notice != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(notice)));
        }
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _viewModel.setLifecycleState(state);
  }

  Future<void> _handleRequest(GameRequest request) async {
    if (!mounted) return;
    if (request.type == GameRequestType.roster && request.cityIndex == null) {
      await showSgbyGeneralRosterSheet(context, viewModel: _viewModel);
    } else if (request.type == GameRequestType.roster &&
        request.cityIndex != null) {
      await _showCityRoster(request.cityIndex!);
    } else if (request.type == GameRequestType.searchHistory) {
      await showSgbySearchHistorySheet(context, viewModel: _viewModel);
    } else if (request.type == GameRequestType.help) {
      await _viewModel.withSgbyAutomationPaused(
        () => showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('游戏操作'),
            content: const SingleChildScrollView(
              child: Text(
                '方向键移动光标，确认键选择，取消键返回菜单。\n\n地图上的城市再次点击即可打开城市指令；长按城市查看武将。出征时连续选择武将，取消结束选将，再选择粮草和目标城池。\n\n战斗中选择我方武将，再选择移动位置与指令；取消键打开战斗菜单。搜索键查看战场形势，帮助键查看当前单位或地形。\n\nF9 切换黑白／卡通，F10 显示／隐藏按钮。键盘按钮可修改全部游戏按键；隐藏界面后点击右上角入口恢复。',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('关闭'),
              ),
            ],
          ),
        ),
      );
    } else {
      _viewModel.showNotice('当前操作暂不可用');
    }
  }

  Future<void> _showCityRoster(int index) async {
    final data = _viewModel.enemyCityInfo(index);
    if (data == null) return;
    await _viewModel.withSgbyAutomationPaused(
      () => showSgbyEnemyCitySheet(context, city: data),
    );
  }

  Future<void> _toggleOrientation() async {
    final landscape = !_viewModel.landscape;
    _viewModel.setLandscape(landscape);
    try {
      await SystemChrome.setPreferredOrientations(
        landscape
            ? [
                DeviceOrientation.landscapeLeft,
                DeviceOrientation.landscapeRight,
              ]
            : [DeviceOrientation.portraitUp],
      );
    } catch (exception) {
      _viewModel.showNotice('无法切换屏幕方向：$exception');
    }
  }

  Future<void> _showSettings() async {
    await _viewModel.withSgbyAutomationPaused(
      () => showDialog<void>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, update) => AlertDialog(
            title: const Text('控制设置'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    title: Text('世界活跃度：${_viewModel.worldActivity}'),
                    subtitle: Slider(
                      value: _viewModel.worldActivity.toDouble(),
                      min: 0,
                      max: 100,
                      divisions: 100,
                      onChanged: (value) {
                        _viewModel.setWorldActivity(value.round());
                        update(() {});
                      },
                    ),
                  ),
                  SwitchListTile(
                    title: const Text('屏幕按键'),
                    value: _viewModel.controlsVisible,
                    onChanged: (value) {
                      _viewModel.setControls(value);
                      update(() {});
                    },
                  ),
                  SwitchListTile(
                    title: const Text('彩色卡通模式'),
                    value: _viewModel.cartoonEnabled,
                    onChanged: (_) {
                      _viewModel.toggleCartoon();
                      update(() {});
                    },
                  ),
                  SwitchListTile(
                    title: const Text('点击震动'),
                    value: _viewModel.hapticsEnabled,
                    onChanged: (value) {
                      _viewModel.setHaptics(value);
                      update(() {});
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('完成'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        // 合集由外层统一确认返回；独立游戏继续将系统返回映射为取消键。
        if (!didPop && widget.onReturnToLibrary == null) {
          _viewModel.send(GameInput.cancel);
        }
      },
      child: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: (_, event) {
          if (ModalRoute.of(context)?.isCurrent != true || _viewModel.paused) {
            return KeyEventResult.ignored;
          }
          if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
            return KeyEventResult.ignored;
          }
          if (event.logicalKey == LogicalKeyboardKey.f9) {
            if (event is KeyDownEvent) _viewModel.toggleCartoon();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.f10) {
            if (event is KeyDownEvent) {
              _viewModel.setControls(!_viewModel.controlsVisible);
            }
            return KeyEventResult.handled;
          }
          final action = _viewModel.keyboardAction(event.logicalKey.keyId);
          if (action == null) return KeyEventResult.ignored;
          _viewModel.send(action);
          return KeyEventResult.handled;
        },
        child: AnimatedBuilder(
          animation: _viewModel,
          builder: (context, _) => Scaffold(
            backgroundColor: _viewModel.cartoonEnabled
                ? const Color(0xffeef6ed)
                : const Color(0xff101214),
            appBar: !_viewModel.controlsVisible
                ? null
                : AppBar(
                    leading: widget.onReturnToLibrary == null
                        ? null
                        : IconButton(
                            tooltip: '返回游戏库',
                            onPressed: widget.onReturnToLibrary,
                            icon: const Icon(Icons.arrow_back),
                          ),
                    title: const Text('三国霸业'),
                    toolbarHeight: 44,
                    actions: [
                      IconButton(
                        tooltip: _viewModel.cartoonEnabled
                            ? '切换黑白模式'
                            : '切换彩色卡通',
                        onPressed: _viewModel.toggleCartoon,
                        icon: Icon(
                          _viewModel.cartoonEnabled
                              ? Icons.contrast
                              : Icons.palette_outlined,
                        ),
                      ),
                      IconButton(
                        tooltip: '隐藏全部界面按钮',
                        onPressed: () => _viewModel.setControls(false),
                        icon: const Icon(Icons.visibility_off_outlined),
                      ),
                      if (MediaQuery.sizeOf(context).width >= 700) ...[
                        IconButton(
                          tooltip: '键盘映射',
                          onPressed: () async {
                            await showGameKeyboardSheet(context, _viewModel);
                            if (mounted) _focus.requestFocus();
                          },
                          icon: const Icon(Icons.keyboard_outlined),
                        ),
                        IconButton(
                          tooltip: '存储进度',
                          onPressed: _viewModel.hasWorld
                              ? _viewModel.openSaveMenu
                              : null,
                          icon: const Icon(Icons.save_outlined),
                        ),
                      ],
                      PopupMenuButton<String>(
                        tooltip: '游戏工具',
                        onSelected: (action) async {
                          if (!context.mounted) return;
                          switch (action) {
                            case 'keys':
                              await showGameKeyboardSheet(context, _viewModel);
                            case 'settings':
                              await _showSettings();
                            case 'orientation':
                              await _toggleOrientation();
                            case 'save':
                              _viewModel.openSaveMenu();
                            case 'roster':
                              _viewModel.send(GameInput.generalRoster);
                            case 'cheats':
                              await showGameCheatSheet(
                                context,
                                viewModel: _viewModel,
                              );
                          }
                          if (mounted) _focus.requestFocus();
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                            value: 'keys',
                            child: Text('键盘映射'),
                          ),
                          const PopupMenuItem(
                            value: 'settings',
                            child: Text('控制设置'),
                          ),
                          const PopupMenuItem(
                            value: 'orientation',
                            child: Text('横竖屏'),
                          ),
                          PopupMenuItem(
                            value: 'save',
                            enabled: _viewModel.hasWorld,
                            child: const Text('存储进度'),
                          ),
                          PopupMenuItem(
                            value: 'roster',
                            enabled: _viewModel.hasWorld,
                            child: const Text('将领列表'),
                          ),
                          PopupMenuItem(
                            value: 'cheats',
                            enabled: _viewModel.hasWorld,
                            child: const Text('作弊系统'),
                          ),
                        ],
                      ),
                    ],
                  ),
            body: Stack(
              children: [
                Positioned.fill(child: _body()),
                if (!_viewModel.controlsVisible)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: SafeArea(
                      child: PopupMenuButton<String>(
                        tooltip: '显示界面控件',
                        icon: const Icon(Icons.more_horiz),
                        color: Theme.of(context).colorScheme.surface,
                        onSelected: (action) async {
                          if (action == 'library') {
                            await widget.onReturnToLibrary?.call();
                            return;
                          }
                          if (action == 'show') _viewModel.setControls(true);
                          if (action == 'art') _viewModel.toggleCartoon();
                          if (action == 'keys') {
                            await showGameKeyboardSheet(context, _viewModel);
                          }
                          if (action == 'settings') await _showSettings();
                          if (mounted) _focus.requestFocus();
                        },
                        itemBuilder: (_) => [
                          if (widget.onReturnToLibrary != null)
                            const PopupMenuItem(
                              value: 'library',
                              child: Text('返回游戏库'),
                            ),
                          const PopupMenuItem(
                            value: 'show',
                            child: Text('显示全部界面按钮'),
                          ),
                          PopupMenuItem(
                            value: 'art',
                            child: Text(
                              _viewModel.cartoonEnabled ? '切换黑白模式' : '切换彩色卡通',
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'keys',
                            child: Text('键盘映射'),
                          ),
                          const PopupMenuItem(
                            value: 'settings',
                            child: Text('控制设置'),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _body() {
    if (_viewModel.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    final error = _viewModel.error;
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('游戏资源加载失败'),
              const SizedBox(height: 12),
              Text('$error'),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _viewModel.initialize,
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, bounds) {
        final landscape = bounds.maxWidth > bounds.maxHeight;
        final canvas = _GameCanvasView(viewModel: _viewModel);
        final controls = _viewModel.controlsVisible;
        // 彩色模式继续使用原来的手柄操作面板；美术加载和场景切换不更换按键布局。
        Widget content;
        if (landscape || !controls) {
          content = Stack(
            children: [
              Positioned.fill(child: canvas),
              if (controls)
                Positioned.fill(
                  child: GameControlsOverlay(
                    isDarkTheme: !_viewModel.cartoonEnabled,
                    hapticsEnabled: _viewModel.hapticsEnabled,
                    onInput: _viewModel.send,
                    showSgbyUtilityButtons: true,
                    battleSpeedMultiplier: _viewModel.battleSpeedMultiplier,
                    sgbyAutoBattleEnabled: _viewModel.sgbyAutoBattleEnabled,
                    sgbyAutoEndTurnEnabled: _viewModel.sgbyAutoEndTurnEnabled,
                    sgbyShowTroopIconsEnabled:
                        _viewModel.sgbyShowTroopIconsEnabled,
                    sgbyBattleStatistics: _viewModel.sgbyBattleStatistics,
                  ),
                ),
            ],
          );
        } else {
          final gameHeight = math.min(
            bounds.maxWidth * 3 / 5,
            bounds.maxHeight * .48,
          );
          final remaining = math.max(0.0, bounds.maxHeight - gameHeight);
          content = Column(
            children: [
              SizedBox(height: gameHeight, child: canvas),
              Expanded(
                child: SingleChildScrollView(
                  child: SizedBox(
                    height: math.max(380.0, remaining),
                    child: PortraitGameControlsPanel(
                      isDarkTheme: !_viewModel.cartoonEnabled,
                      hapticsEnabled: _viewModel.hapticsEnabled,
                      onInput: _viewModel.send,
                      showSgbyUtilityButtons: true,
                      battleSpeedMultiplier: _viewModel.battleSpeedMultiplier,
                      sgbyAutoBattleEnabled: _viewModel.sgbyAutoBattleEnabled,
                      sgbyAutoEndTurnEnabled: _viewModel.sgbyAutoEndTurnEnabled,
                      sgbyShowTroopIconsEnabled:
                          _viewModel.sgbyShowTroopIconsEnabled,
                      sgbyBattleStatistics: _viewModel.sgbyBattleStatistics,
                    ),
                  ),
                ),
              ),
            ],
          );
        }
        return Stack(
          children: [
            Positioned.fill(child: content),
            if (_viewModel.isBusy)
              const Positioned(
                top: 4,
                right: 6,
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.dispose();
    _backgroundClock?.dispose();
    _focus.dispose();
    _viewModel.removeListener(_onStateChanged);
    _viewModel.onUiRequest = null;
    if (widget.viewModel == null) _viewModel.dispose();
    super.dispose();
  }
}

/// 原画面显示与触摸映射。每次点击先排除黑边，再转换为240×144逻辑坐标。
class _GameCanvasView extends StatefulWidget {
  const _GameCanvasView({required this.viewModel});
  final GameViewModel viewModel;
  @override
  State<_GameCanvasView> createState() => _GameCanvasViewState();
}

class _GameCanvasViewState extends State<_GameCanvasView>
    with WidgetsBindingObserver {
  int? _pointer;
  Offset? _start;
  Offset? _last;
  Timer? _longPress;
  bool _longTriggered = false;
  bool _moved = false;
  Size _size = Size.zero;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  Offset? _toGame(Offset local) {
    final session = widget.viewModel.session;
    if (session == null || _size.isEmpty) return null;
    final scale = math.min(
      _size.width / session.canvas.width,
      _size.height / session.canvas.height,
    );
    if (scale <= 0) return null;
    final left = (_size.width - session.canvas.width * scale) / 2;
    final top = (_size.height - session.canvas.height * scale) / 2;
    final point = Offset((local.dx - left) / scale, (local.dy - top) / scale);
    if (point.dx < 0 ||
        point.dy < 0 ||
        point.dx >= session.canvas.width ||
        point.dy >= session.canvas.height) {
      return null;
    }
    return point;
  }

  void _down(PointerDownEvent event) {
    if (_pointer != null || _toGame(event.localPosition) == null) return;
    _pointer = event.pointer;
    _start = event.localPosition;
    _last = _start;
    _longTriggered = false;
    _moved = false;
    _longPress = Timer(const Duration(milliseconds: 600), () {
      if (!mounted || _pointer == null || _moved) return;
      final local = _last;
      final point = local == null ? null : _toGame(local);
      if (point != null &&
          widget.viewModel.session?.scene == NativeScene.strategy) {
        _longTriggered = widget.viewModel.longPress(point.dx, point.dy);
      }
    });
  }

  void _move(PointerMoveEvent event) {
    if (_pointer != event.pointer) return;
    _last = event.localPosition;
    final start = _start;
    if (start != null && (event.localPosition - start).distance > 12) {
      _moved = true;
      _longPress?.cancel();
      _longPress = null;
    }
  }

  void _up(PointerUpEvent event) {
    if (_pointer != event.pointer) return;
    final start = _start;
    final point = _toGame(event.localPosition);
    if (!_longTriggered && point != null) {
      if (_moved && start != null) {
        final first = _toGame(start);
        if (first != null) {
          widget.viewModel.swipe(
            (point.dy - first.dy).round(),
            deltaX: (point.dx - first.dx).round(),
          );
        }
      } else {
        widget.viewModel.tap(point.dx, point.dy);
      }
    }
    _cancel();
  }

  void _cancel() {
    _longPress?.cancel();
    _longPress = null;
    _pointer = null;
    _start = null;
    _last = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _cancel();
    }
  }

  @override
  Widget build(BuildContext context) {
    final presenter = widget.viewModel.frames;
    if (presenter == null) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, bounds) {
        final nextSize = bounds.biggest;
        if (_size != nextSize) _cancel();
        _size = nextSize;
        final surface = Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: _down,
          onPointerMove: _move,
          onPointerUp: _up,
          onPointerCancel: (_) => _cancel(),
          child: ColoredBox(
            color: Colors.black,
            child: ListenableBuilder(
              listenable: Listenable.merge([
                presenter,
                widget.viewModel.sceneRevision,
              ]),
              builder: (_, _) {
                final current = widget.viewModel.session;
                if (widget.viewModel.cartoonEnabled && current != null) {
                  return RepaintBoundary(
                    child: CustomPaint(
                      size: bounds.biggest,
                      painter: widget.viewModel.cartoonAssets == null
                          ? ModernGamePainter(current)
                          : RealisticGamePainter(
                              current,
                              widget.viewModel.cartoonAssets!,
                              revision: widget.viewModel.sceneRevision.value,
                            ),
                    ),
                  );
                }
                if (presenter.error != null) {
                  return const Center(child: Text('画面加载失败'));
                }
                final image = presenter.image;
                return image == null
                    ? const Center(child: CircularProgressIndicator())
                    : Center(
                        child: RawImage(
                          image: image,
                          fit: BoxFit.contain,
                          width: bounds.maxWidth,
                          height: bounds.maxHeight,
                          filterQuality: FilterQuality.low,
                          isAntiAlias: false,
                        ),
                      );
              },
            ),
          ),
        );
        final vm = widget.viewModel;
        final scale = vm.session == null
            ? 0.0
            : math.min(bounds.maxWidth / 240, bounds.maxHeight / 144);
        final left = (bounds.maxWidth - 240 * scale) / 2,
            top = (bounds.maxHeight - 144 * scale) / 2;
        return Stack(
          children: [
            Positioned.fill(child: surface),
            if (vm.cartoonEnabled &&
                vm.cartoonAssets != null &&
                vm.controlsVisible)
              Positioned(
                left: left + 5,
                top: top + 5,
                width: math.min(180, math.max(100, bounds.maxWidth * .2)),
                child: CartoonBattleOverview(viewModel: vm),
              ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    _cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

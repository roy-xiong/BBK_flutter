import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 与 BBK 控制区一一对应的输入；游戏按键与外部辅助操作由页面统一分发。
enum GameControl {
  up,
  down,
  left,
  right,
  pageUp,
  pageDown,
  confirm,
  cancel,
  quickTravel,
  selectFmjStage,
  cycleFmjRunSpeed,
  toggleFmjAutoBattle,
  toggleWideView,
  search,
  help,
  toggleMoneyFarm,
}

/// 按 BBK 原版尺寸、位置、配色和长按节奏保留的横屏悬浮控制区。
class GameControlsOverlay extends StatelessWidget {
  const GameControlsOverlay({
    super.key,
    this.hapticsEnabled = true,
    required this.onInput,
    this.showFmjUtilityButtons = true,
    this.fmjWideViewEnabled = true,
    this.fmjAutoBattleEnabled = false,
    this.fmjRunSpeed = 1,
    this.fmjMoneyFarmActive = false,
  });
  final bool hapticsEnabled,
      showFmjUtilityButtons,
      fmjWideViewEnabled,
      fmjAutoBattleEnabled,
      fmjMoneyFarmActive;
  final int fmjRunSpeed;
  final ValueChanged<GameControl> onInput;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final shortestSide = constraints.biggest.shortestSide;
        final buttonSize = (shortestSide * 0.14).clamp(46.0, 68.0);
        final gap = (buttonSize * 0.12).clamp(6.0, 10.0);
        return Stack(
          children: [
            Positioned(
              left: 18,
              bottom: 42,
              child: _DirectionPad(
                buttonSize: buttonSize,
                gap: gap,
                hapticsEnabled: hapticsEnabled,
                onInput: onInput,
              ),
            ),
            if (showFmjUtilityButtons)
              Positioned(
                right: 18,
                bottom: buttonSize * 2.5 + gap * 2,
                child: _FmjUtilityButtons(
                  hapticsEnabled: hapticsEnabled,
                  wideViewEnabled: fmjWideViewEnabled,
                  autoBattleEnabled: fmjAutoBattleEnabled,
                  runSpeed: fmjRunSpeed,
                  moneyFarmActive: fmjMoneyFarmActive,
                  onInput: onInput,
                ),
              ),
            Positioned(
              right: 18,
              bottom: 18,
              child: _ActionPad(
                buttonSize: buttonSize,
                gap: gap,
                hapticsEnabled: hapticsEnabled,
                onInput: onInput,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 竖屏模式下的红白机风格控制区。
///
/// 控制区使用剩余窗口空间居中布局，宽屏设备限制最大宽度，避免方向键和动作键被无限
/// 拉伸。SELECT/START 分别映射为上翻页和下翻页，保持两款游戏的完整操作能力。
class PortraitGameControlsPanel extends StatelessWidget {
  const PortraitGameControlsPanel({
    super.key,
    this.isDarkTheme = true,

    this.hapticsEnabled = true,
    required this.onInput,
    this.showFmjUtilityButtons = true,
    this.fmjWideViewEnabled = true,
    this.fmjAutoBattleEnabled = false,
    this.fmjRunSpeed = 1,
    this.fmjMoneyFarmActive = false,
  });
  final bool isDarkTheme;
  final bool hapticsEnabled,
      showFmjUtilityButtons,
      fmjWideViewEnabled,
      fmjAutoBattleEnabled,
      fmjMoneyFarmActive;
  final int fmjRunSpeed;
  final ValueChanged<GameControl> onInput;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final contentWidth = constraints.maxWidth.clamp(280.0, 560.0);
          final directionButtonSize = (contentWidth * 0.13).clamp(44.0, 60.0);
          final actionButtonSize = (contentWidth * 0.16).clamp(52.0, 76.0);
          final panelColor = isDarkTheme
              ? const Color(0xFF1B1E22)
              : const Color(0xFFD8D5CD);
          return ColoredBox(
            color: panelColor,
            child: Column(
              children: [
                const SizedBox(height: 10),
                _NesStripe(isDarkTheme: isDarkTheme),
                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Transform.translate(
                          // 功能区首行不能平移到父容器之外，否则按钮上半部可见却无法点击。
                          offset: Offset(0, showFmjUtilityButtons ? 0 : -24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (showFmjUtilityButtons) ...[
                                _FmjUtilityButtons(
                                  hapticsEnabled: hapticsEnabled,
                                  wideViewEnabled: fmjWideViewEnabled,
                                  autoBattleEnabled: fmjAutoBattleEnabled,
                                  runSpeed: fmjRunSpeed,
                                  moneyFarmActive: fmjMoneyFarmActive,
                                  onInput: onInput,
                                ),
                                const SizedBox(height: 14),
                              ],
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  _NesDirectionPad(
                                    buttonSize: directionButtonSize,
                                    hapticsEnabled: hapticsEnabled,
                                    onInput: onInput,
                                  ),
                                  Flexible(
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: _NesSystemButtons(
                                        isDarkTheme: isDarkTheme,
                                        hapticsEnabled: hapticsEnabled,
                                        onInput: onInput,
                                      ),
                                    ),
                                  ),
                                  _NesActionButtons(
                                    buttonSize: actionButtonSize,
                                    hapticsEnabled: hapticsEnabled,
                                    onInput: onInput,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                _NesStripe(isDarkTheme: isDarkTheme),
                const SizedBox(height: 10),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// 伏魔记控制区的一键前往入口。
///
/// 横竖屏使用同一个输入动作，由引擎按最新剧情状态决定目标；不打开地图子面板，
/// 不缓存目标，避免读档或对话完成后继续使用旧节点。
class _FmjUtilityButtons extends StatelessWidget {
  const _FmjUtilityButtons({
    required this.hapticsEnabled,
    required this.wideViewEnabled,
    required this.autoBattleEnabled,
    required this.runSpeed,
    required this.moneyFarmActive,
    required this.onInput,
  });

  final bool hapticsEnabled;
  final bool wideViewEnabled;
  final bool autoBattleEnabled;
  final int runSpeed;
  final bool moneyFarmActive;
  final ValueChanged<GameControl> onInput;

  @override
  Widget build(BuildContext context) {
    Widget button(
      String label,
      String text,
      GameControl action, {
      double width = 88,
      bool active = false,
    }) {
      return Tooltip(
        message: label,
        // 快捷前往的长按用于连发，不能让Tooltip的LongPress识别器抢走指针。
        triggerMode: action == GameControl.quickTravel
            ? TooltipTriggerMode.manual
            : null,
        child: _NesInputButton(
          width: width,
          height: 40,
          color: active ? const Color(0xFF23594E) : const Color(0xFF354D6A),
          pressedColor: const Color(0xFF163C35),
          borderRadius: BorderRadius.circular(7),
          repeatable: action == GameControl.quickTravel,
          hapticsEnabled: hapticsEnabled,
          label: label,
          onPressed: () => onInput(action),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              text,
              maxLines: 1,
              style: const TextStyle(color: Color(0xFFF0EEE8), fontSize: 12),
            ),
          ),
        ),
      );
    }

    // 快捷前往保持至少56dp真实触控高度；只有次要按钮可缩放。
    return SizedBox(
      width: 284,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Tooltip(
            message: '一键前往当前目标',
            triggerMode: TooltipTriggerMode.manual,
            child: _NesInputButton(
              key: const ValueKey('fmj-quick-travel-large'),
              width: 284,
              height: 58,
              color: const Color(0xFF23594E),
              pressedColor: const Color(0xFF163C35),
              borderRadius: BorderRadius.circular(9),
              repeatable: true,
              hapticsEnabled: hapticsEnabled,
              label: '一键前往当前目标',
              onPressed: () => onInput(GameControl.quickTravel),
              child: const Text(
                '一键前往当前目标',
                style: TextStyle(color: Color(0xFFF0EEE8), fontSize: 15),
              ),
            ),
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                button('选择关卡', '选择关卡', GameControl.selectFmjStage, width: 62),
                const SizedBox(width: 5),
                button(
                  '切换自动跑路倍速',
                  '奔跑 $runSpeed×',
                  GameControl.cycleFmjRunSpeed,
                  width: 67,
                ),
                const SizedBox(width: 5),
                button(
                  autoBattleEnabled ? '关闭自动战斗' : '开启自动战斗',
                  autoBattleEnabled ? '自动战斗 开' : '自动战斗 关',
                  GameControl.toggleFmjAutoBattle,
                  width: 78,
                  active: autoBattleEnabled,
                ),
                const SizedBox(width: 5),
                button(
                  wideViewEnabled ? '切换原视野' : '切换远视野',
                  wideViewEnabled ? '远视野 2×' : '原视野 1×',
                  GameControl.toggleWideView,
                  width: 62,
                  active: wideViewEnabled,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NesStripe extends StatelessWidget {
  const _NesStripe({required this.isDarkTheme});

  final bool isDarkTheme;

  @override
  Widget build(BuildContext context) {
    final color = isDarkTheme
        ? const Color(0xFF7F2630)
        : const Color(0xFF9F1F2B);
    return Column(
      children: [
        ColoredBox(color: color, child: const SizedBox(height: 5)),
        const SizedBox(height: 4),
        ColoredBox(color: color, child: const SizedBox(height: 2)),
      ],
    );
  }
}

class _NesDirectionPad extends StatelessWidget {
  const _NesDirectionPad({
    required this.buttonSize,
    required this.hapticsEnabled,
    required this.onInput,
  });

  final double buttonSize;
  final bool hapticsEnabled;
  final ValueChanged<GameControl> onInput;

  @override
  Widget build(BuildContext context) {
    Widget button(GameControl input, IconData icon, String label) {
      return _NesInputButton(
        width: buttonSize,
        height: buttonSize,
        color: const Color(0xFF252629),
        pressedColor: const Color(0xFF08090A),
        borderRadius: BorderRadius.circular(3),
        repeatable: true,
        hapticsEnabled: hapticsEnabled,
        label: label,
        onPressed: () => onInput(input),
        child: Icon(
          icon,
          color: const Color(0xFFB7B5AE),
          size: buttonSize * 0.68,
        ),
      );
    }

    final center = Container(
      width: buttonSize,
      height: buttonSize,
      color: const Color(0xFF252629),
      alignment: Alignment.center,
      child: Container(
        width: buttonSize * 0.34,
        height: buttonSize * 0.34,
        decoration: const BoxDecoration(
          color: Color(0xFF18191B),
          shape: BoxShape.circle,
        ),
      ),
    );
    final empty = SizedBox.square(dimension: buttonSize);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            empty,
            button(GameControl.up, Icons.arrow_drop_up, '上'),
            empty,
          ],
        ),
        Row(
          children: [
            button(GameControl.left, Icons.arrow_left, '左'),
            center,
            button(GameControl.right, Icons.arrow_right, '右'),
          ],
        ),
        Row(
          children: [
            empty,
            button(GameControl.down, Icons.arrow_drop_down, '下'),
            empty,
          ],
        ),
      ],
    );
  }
}

class _NesSystemButtons extends StatelessWidget {
  const _NesSystemButtons({
    required this.isDarkTheme,
    required this.hapticsEnabled,
    required this.onInput,
  });

  final bool isDarkTheme;
  final bool hapticsEnabled;
  final ValueChanged<GameControl> onInput;

  @override
  Widget build(BuildContext context) {
    Widget button(String text, GameControl input, String label) {
      return _NesInputButton(
        width: 68,
        height: 28,
        color: isDarkTheme ? const Color(0xFF4A4D52) : const Color(0xFF343539),
        pressedColor: const Color(0xFF111214),
        borderRadius: BorderRadius.circular(12),
        repeatable: true,
        hapticsEnabled: hapticsEnabled,
        label: label,
        onPressed: () => onInput(input),
        child: Text(
          text,
          style: const TextStyle(
            color: Color(0xFFF0EEE8),
            fontSize: 9,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        button('SELECT', GameControl.pageUp, '上翻页'),
        const SizedBox(height: 12),
        button('START', GameControl.pageDown, '下翻页'),
      ],
    );
  }
}

class _NesActionButtons extends StatelessWidget {
  const _NesActionButtons({
    required this.buttonSize,
    required this.hapticsEnabled,
    required this.onInput,
  });

  final double buttonSize;
  final bool hapticsEnabled;
  final ValueChanged<GameControl> onInput;

  @override
  Widget build(BuildContext context) {
    Widget button(String text, GameControl input, String label) {
      return _NesInputButton(
        width: buttonSize,
        height: buttonSize,
        color: const Color(0xFFB32632),
        pressedColor: const Color(0xFF7F141F),
        borderRadius: BorderRadius.circular(buttonSize / 2),
        hapticsEnabled: hapticsEnabled,
        label: label,
        onPressed: () => onInput(input),
        child: Text(
          text,
          style: TextStyle(
            color: const Color(0xFFF7F3EA),
            fontSize: buttonSize * 0.36,
            fontWeight: FontWeight.w800,
          ),
        ),
      );
    }

    return Transform.rotate(
      angle: -0.12,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          button('B', GameControl.cancel, '返回'),
          const SizedBox(width: 10),
          Padding(
            padding: EdgeInsets.only(bottom: buttonSize * 0.28),
            child: button('A', GameControl.confirm, '确认'),
          ),
        ],
      ),
    );
  }
}

class _NesInputButton extends StatefulWidget {
  const _NesInputButton({
    super.key,
    required this.width,
    required this.height,
    required this.color,
    required this.pressedColor,
    required this.borderRadius,
    required this.hapticsEnabled,
    required this.label,
    required this.onPressed,
    required this.child,
    this.repeatable = false,
  });

  final double width;
  final double height;
  final Color color;
  final Color pressedColor;
  final BorderRadius borderRadius;
  final bool hapticsEnabled;
  final String label;
  final VoidCallback onPressed;
  final Widget child;
  final bool repeatable;

  @override
  State<_NesInputButton> createState() => _NesInputButtonState();
}

class _NesInputButtonState extends State<_NesInputButton> {
  Timer? _delayTimer;
  Timer? _repeatTimer;
  bool _pressed = false;

  @override
  void dispose() {
    _delayTimer?.cancel();
    _repeatTimer?.cancel();
    super.dispose();
  }

  void _start() {
    if (_pressed) return;
    setState(() => _pressed = true);
    if (widget.hapticsEnabled) unawaited(HapticFeedback.selectionClick());
    widget.onPressed();
    if (widget.repeatable) {
      _delayTimer = Timer(const Duration(milliseconds: 320), () {
        _repeatTimer = Timer.periodic(
          const Duration(milliseconds: 105),
          (_) => widget.onPressed(),
        );
      });
    }
  }

  void _stop() {
    _delayTimer?.cancel();
    _repeatTimer?.cancel();
    _delayTimer = null;
    _repeatTimer = null;
    if (_pressed && mounted) {
      setState(() => _pressed = false);
    } else {
      _pressed = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _start(),
        onTapUp: (_) => _stop(),
        onTapCancel: _stop,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 65),
          width: widget.width,
          height: widget.height,
          alignment: Alignment.center,
          transform: Matrix4.translationValues(0, _pressed ? 2 : 0, 0),
          decoration: BoxDecoration(
            color: _pressed ? widget.pressedColor : widget.color,
            borderRadius: widget.borderRadius,
            border: Border.all(color: const Color(0xFF0D0E10), width: 1.5),
            boxShadow: _pressed
                ? const []
                : const [
                    BoxShadow(
                      color: Color(0x66000000),
                      offset: Offset(0, 3),
                      blurRadius: 0,
                    ),
                  ],
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

class _DirectionPad extends StatelessWidget {
  const _DirectionPad({
    required this.buttonSize,
    required this.gap,
    required this.hapticsEnabled,
    required this.onInput,
  });

  final double buttonSize;
  final double gap;
  final bool hapticsEnabled;
  final ValueChanged<GameControl> onInput;

  @override
  Widget build(BuildContext context) {
    Widget button(GameControl input, IconData icon, String label) {
      return _HoldButton(
        size: buttonSize,
        label: label,
        repeatable: true,
        hapticsEnabled: hapticsEnabled,
        onPressed: () => onInput(input),
        child: Icon(icon),
      );
    }

    Widget empty() => SizedBox.square(dimension: buttonSize);
    return Column(
      children: [
        Row(
          children: [
            empty(),
            SizedBox(width: gap),
            button(GameControl.up, Icons.keyboard_arrow_up, '上'),
            SizedBox(width: gap),
            empty(),
          ],
        ),
        SizedBox(height: gap),
        Row(
          children: [
            button(GameControl.left, Icons.keyboard_arrow_left, '左'),
            SizedBox(width: gap),
            empty(),
            SizedBox(width: gap),
            button(GameControl.right, Icons.keyboard_arrow_right, '右'),
          ],
        ),
        SizedBox(height: gap),
        Row(
          children: [
            empty(),
            SizedBox(width: gap),
            button(GameControl.down, Icons.keyboard_arrow_down, '下'),
            SizedBox(width: gap),
            empty(),
          ],
        ),
      ],
    );
  }
}

class _ActionPad extends StatelessWidget {
  const _ActionPad({
    required this.buttonSize,
    required this.gap,
    required this.hapticsEnabled,
    required this.onInput,
  });

  final double buttonSize;
  final double gap;
  final bool hapticsEnabled;
  final ValueChanged<GameControl> onInput;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Row(
          children: [
            _HoldButton(
              size: buttonSize * 0.8,
              label: '上翻页',
              repeatable: true,
              hapticsEnabled: hapticsEnabled,
              onPressed: () => onInput(GameControl.pageUp),
              child: const Icon(Icons.keyboard_double_arrow_up),
            ),
            SizedBox(width: gap),
            _HoldButton(
              size: buttonSize * 0.8,
              label: '下翻页',
              repeatable: true,
              hapticsEnabled: hapticsEnabled,
              onPressed: () => onInput(GameControl.pageDown),
              child: const Icon(Icons.keyboard_double_arrow_down),
            ),
          ],
        ),
        SizedBox(height: gap * 1.5),
        Row(
          children: [
            _HoldButton(
              size: buttonSize,
              label: '返回',
              hapticsEnabled: hapticsEnabled,
              onPressed: () => onInput(GameControl.cancel),
              child: const Text('B'),
            ),
            SizedBox(width: gap),
            _HoldButton(
              size: buttonSize,
              label: '确认',
              hapticsEnabled: hapticsEnabled,
              onPressed: () => onInput(GameControl.confirm),
              child: const Text('A'),
            ),
          ],
        ),
      ],
    );
  }
}

class _HoldButton extends StatefulWidget {
  const _HoldButton({
    required this.size,
    required this.label,
    required this.hapticsEnabled,
    required this.onPressed,
    required this.child,
    this.repeatable = false,
  });

  final double size;
  final String label;
  final bool hapticsEnabled;
  final VoidCallback onPressed;
  final Widget child;
  final bool repeatable;

  @override
  State<_HoldButton> createState() => _HoldButtonState();
}

class _HoldButtonState extends State<_HoldButton> {
  Timer? _delayTimer;
  Timer? _repeatTimer;
  bool _pressed = false;

  @override
  void dispose() {
    _delayTimer?.cancel();
    _repeatTimer?.cancel();
    super.dispose();
  }

  void _start() {
    if (_pressed) return;
    setState(() => _pressed = true);
    if (widget.hapticsEnabled) unawaited(HapticFeedback.selectionClick());
    widget.onPressed();
    if (widget.repeatable) {
      _delayTimer = Timer(const Duration(milliseconds: 320), () {
        _repeatTimer = Timer.periodic(
          const Duration(milliseconds: 105),
          (_) => widget.onPressed(),
        );
      });
    }
  }

  void _stop() {
    _delayTimer?.cancel();
    _repeatTimer?.cancel();
    _delayTimer = null;
    _repeatTimer = null;
    if (_pressed && mounted) {
      setState(() => _pressed = false);
    } else {
      _pressed = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _start(),
        onTapUp: (_) => _stop(),
        onTapCancel: _stop,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 70),
          width: widget.size,
          height: widget.size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _pressed ? const Color(0xCCD94B3D) : const Color(0x8833383C),
            border: Border.all(color: const Color(0x99FFFFFF)),
          ),
          child: DefaultTextStyle.merge(
            style: TextStyle(
              fontSize: widget.size * 0.34,
              fontWeight: FontWeight.w700,
            ),
            child: IconTheme.merge(
              data: IconThemeData(size: widget.size * 0.55),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../domain/models/game_definition.dart';
import '../../../../domain/models/keyboard_bindings.dart';
import '../../../core/game_keyboard.dart';
import '../view_models/game_view_model.dart';

/// 用键盘实际捕获新映射；弹层存在时停止游戏输入，关闭后恢复原页面焦点。
Future<void> showGameKeyboardSheet(
  BuildContext context,
  GameViewModel viewModel,
) => viewModel.withSgbyAutomationPaused(
  () => showDialog<void>(
    context: context,
    builder: (context) => _KeyboardDialog(viewModel: viewModel),
  ),
);

class _KeyboardDialog extends StatefulWidget {
  const _KeyboardDialog({required this.viewModel});
  final GameViewModel viewModel;
  @override
  State<_KeyboardDialog> createState() => _KeyboardDialogState();
}

class _KeyboardDialogState extends State<_KeyboardDialog> {
  final FocusNode _focus = FocusNode(debugLabel: 'keyboard-mapping');
  GameInput? _capturing;
  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(
    autofocus: true,
    focusNode: _focus,
    onKeyEvent: (_, event) {
      if (event is! KeyDownEvent) return KeyEventResult.handled;
      final action = _capturing;
      if (action == null) return KeyEventResult.ignored;
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        setState(() => _capturing = null);
      } else if (![
        LogicalKeyboardKey.shiftLeft,
        LogicalKeyboardKey.shiftRight,
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.controlRight,
        LogicalKeyboardKey.metaLeft,
        LogicalKeyboardKey.metaRight,
        LogicalKeyboardKey.altLeft,
        LogicalKeyboardKey.altRight,
      ].contains(event.logicalKey)) {
        widget.viewModel.bindKeyboard(action, event.logicalKey.keyId);
        setState(() => _capturing = null);
      }
      return KeyEventResult.handled;
    },
    child: AlertDialog(
      title: const Text('键盘映射'),
      content: SizedBox(
        width: 480,
        height: 460,
        child: Column(
          children: [
            Text(
              _capturing == null
                  ? '点击动作后按键，冲突自动解除。F9 / F10 保留为画风 / 界面显隐。'
                  : '请按下新按键，Esc 取消录入',
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                itemCount: KeyboardBindings.supported.length,
                itemBuilder: (_, index) {
                  final action = KeyboardBindings.supported[index];
                  final keys =
                      widget.viewModel.keyboard.keysFor(action) ??
                      [
                        for (final entry in GameKeyboard.defaults.entries)
                          if (entry.value == action &&
                              widget.viewModel.keyboard.resolve(
                                    entry.key,
                                    GameKeyboard.defaults,
                                  ) ==
                                  action)
                            entry.key,
                      ];
                  return ListTile(
                    title: Text(GameKeyboard.labels[action] ?? action.name),
                    subtitle: Text(
                      keys.isEmpty
                          ? '未绑定'
                          : keys.map(GameKeyboard.label).join(' / '),
                    ),
                    selected: _capturing == action,
                    trailing: const Icon(Icons.keyboard_outlined),
                    onTap: () {
                      setState(() => _capturing = action);
                      _focus.requestFocus();
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            widget.viewModel.resetKeyboard();
            setState(() => _capturing = null);
          },
          child: const Text('恢复默认'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('完成'),
        ),
      ],
    ),
  );
}

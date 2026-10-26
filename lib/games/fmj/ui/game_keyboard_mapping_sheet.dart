import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'game_controls.dart';
import 'game_keyboard_bindings.dart';
import 'game_view_model.dart';

Future<void> showGameKeyboardMappingSheet(
  BuildContext context,
  GameViewModel settings,
) => showDialog<void>(
  context: context,
  builder: (_) => _KeyboardMappingDialog(settings: settings),
);

/// 玩家主动选择一个动作后录入物理键，冲突确认后迁移旧绑定；保存立即生效。
class _KeyboardMappingDialog extends StatefulWidget {
  const _KeyboardMappingDialog({required this.settings});
  final GameViewModel settings;
  @override
  State<_KeyboardMappingDialog> createState() => _KeyboardMappingDialogState();
}

class _KeyboardMappingDialogState extends State<_KeyboardMappingDialog> {
  final FocusNode _captureFocus = FocusNode();
  GameControl? _recording;
  bool _saving = false;
  @override
  void dispose() {
    _captureFocus.dispose();
    super.dispose();
  }

  Future<void> _bind(GameControl action, String code) async {
    if (_saving) return;
    _saving = true;
    setState(() => _recording = null);
    final existing = widget.settings.keyboardBindings.actionFor(code);
    var approved = true;
    if (existing != null && existing != action) {
      approved =
          await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('按键已被使用'),
              content: Text(
                '${GameKeyboardBindings.label(code)} 当前绑定“${GameKeyboardBindings.labels[existing]}”，改为“${GameKeyboardBindings.labels[action]}”？',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('修改绑定'),
                ),
              ],
            ),
          ) ??
          false;
    }
    if (!mounted) return;
    if (approved) {
      widget.settings.setKeyboardBindings(
        widget.settings.keyboardBindings.bind(action, code),
      );
    }
    setState(() => _saving = false);
    _captureFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final actions = GameKeyboardBindings.labels.keys;
    return Focus(
      focusNode: _captureFocus,
      autofocus: true,
      onKeyEvent: (_, event) {
        final action = _recording;
        if (action == null || event is! KeyDownEvent || _saving) {
          return KeyEventResult.ignored;
        }
        final code = GameKeyboardBindings.codeFor(event.physicalKey);
        if (code != null) _bind(action, code);
        return KeyEventResult.handled;
      },
      child: AlertDialog(
        title: const Text('键盘映射'),
        content: SizedBox(
          width: 650,
          height: 520,
          child: ListenableBuilder(
            listenable: widget.settings,
            builder: (context, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _recording == null
                      ? '点击“添加按键”，再按键绑定。每个动作可绑定多个键，修改后自动保存。'
                      : '请按键，绑定到“${GameKeyboardBindings.labels[_recording]}”',
                  style: TextStyle(
                    color: _recording == null
                        ? null
                        : Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView(
                    children: [
                      for (final action in actions)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 7),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              SizedBox(
                                width: 200,
                                child: Text(
                                  GameKeyboardBindings.labels[action]!,
                                ),
                              ),
                              for (final code
                                  in widget
                                          .settings
                                          .keyboardBindings
                                          .bindings[action] ??
                                      <String>[])
                                InputChip(
                                  label: Text(GameKeyboardBindings.label(code)),
                                  onDeleted: () =>
                                      widget.settings.setKeyboardBindings(
                                        widget.settings.keyboardBindings.remove(
                                          action,
                                          code,
                                        ),
                                      ),
                                ),
                              ActionChip(
                                label: Text(
                                  _recording == action ? '按键录入中…' : '添加按键',
                                ),
                                avatar: const Icon(Icons.add, size: 18),
                                onPressed: _saving
                                    ? null
                                    : () {
                                        setState(() => _recording = action);
                                        _captureFocus.requestFocus();
                                      },
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                if (widget.settings.failure != null) const Text('保存设置失败，请重试。'),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              widget.settings.setKeyboardBindings(
                GameKeyboardBindings.defaults,
              );
              setState(() => _recording = null);
            },
            child: const Text('恢复默认'),
          ),
          if (_recording != null)
            TextButton(
              onPressed: () => setState(() => _recording = null),
              child: const Text('取消录入'),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('完成'),
          ),
        ],
      ),
    );
  }
}

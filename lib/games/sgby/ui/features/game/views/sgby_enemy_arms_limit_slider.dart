import 'package:flutter/material.dart';

/// 敌将兵力上限编辑器。拖动只更新本地预览，松手后提交整数，避免每个拖动事件都写偏好和修改游戏状态。
class SgbyEnemyArmsLimitSlider extends StatefulWidget {
  const SgbyEnemyArmsLimitSlider({
    super.key,
    required this.value,
    required this.enabled,
    required this.busy,
    required this.onSubmitted,
  });

  static const minimum = 800;
  static const maximum = 200000;
  final int? value;
  final bool enabled;
  final bool busy;
  final ValueChanged<int>? onSubmitted;

  @override
  State<SgbyEnemyArmsLimitSlider> createState() =>
      _SgbyEnemyArmsLimitSliderState();
}

class _SgbyEnemyArmsLimitSliderState extends State<SgbyEnemyArmsLimitSlider> {
  double? _preview;

  @override
  void didUpdateWidget(covariant SgbyEnemyArmsLimitSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value ||
        widget.enabled != oldWidget.enabled ||
        (oldWidget.busy && !widget.busy)) {
      _preview = null;
    }
  }

  /// 沿用战绩数字的四位分组显示，完整保留上限值。
  String _format(int value) => value.toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{4})+$)'),
    (match) => '${match[1]} ',
  );

  @override
  Widget build(BuildContext context) {
    final saved = widget.value;
    if (saved == null ||
        saved < SgbyEnemyArmsLimitSlider.minimum ||
        saved > SgbyEnemyArmsLimitSlider.maximum) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Text('暂未读取到敌军兵力上限，请重新打开作弊面板'),
      );
    }
    final value = (_preview ?? saved.toDouble()).clamp(
      SgbyEnemyArmsLimitSlider.minimum.toDouble(),
      SgbyEnemyArmsLimitSlider.maximum.toDouble(),
    );
    final canEdit =
        widget.enabled && !widget.busy && widget.onSubmitted != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('每名敌将上限：${_format(value.round())}'),
          Slider(
            value: value,
            min: SgbyEnemyArmsLimitSlider.minimum.toDouble(),
            max: SgbyEnemyArmsLimitSlider.maximum.toDouble(),
            divisions:
                SgbyEnemyArmsLimitSlider.maximum -
                SgbyEnemyArmsLimitSlider.minimum,
            label: _format(value.round()),
            semanticFormatterCallback: (value) => '${value.round()}名士兵',
            onChanged: canEdit
                ? (value) => setState(() => _preview = value)
                : null,
            onChangeEnd: canEdit
                ? (value) => widget.onSubmitted?.call(value.round())
                : null,
          ),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [Text('800'), Text('20 0000')],
          ),
        ],
      ),
    );
  }
}

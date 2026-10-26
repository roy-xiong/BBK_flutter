import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../domain/models/sgby_battle_statistics.dart';

/// 独立监听战绩的文字区域；更新四个数字不重建游戏画布或控制按钮。
class SgbyBattleStatisticsText extends StatelessWidget {
  const SgbyBattleStatisticsText({
    super.key,
    required this.isDarkTheme,
    this.statistics,
  });

  final bool isDarkTheme;
  final ValueListenable<SgbyBattleStatistics?>? statistics;

  @override
  Widget build(BuildContext context) {
    final source = statistics;
    if (source == null) return _content(null);
    return ValueListenableBuilder<SgbyBattleStatistics?>(
      valueListenable: source,
      builder: (context, value, _) => _content(value),
    );
  }

  /// 分成两栏展示累计损失与击杀，窄屏和大数值时仅缩放数字行，避免挤压按键。
  Widget _content(SgbyBattleStatistics? value) {
    final color = isDarkTheme
        ? const Color(0xFFDDDDDD)
        : const Color(0xFF303438);
    final style = TextStyle(color: color, fontSize: 12, height: 1.3);
    if (value == null) {
      return Text('选择君主后开始统计战绩', textAlign: TextAlign.center, style: style);
    }
    Widget column(String title, int soldiers, int generals) => Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: style.copyWith(fontWeight: FontWeight.w600)),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              '士兵 ${formatCount(soldiers)}  ·  将领 ${formatCount(generals)}',
              style: style,
            ),
          ),
        ],
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!value.hasFullHistory)
          Text(
            '旧档战绩仅含启用统计后的记录',
            textAlign: TextAlign.center,
            style: style.copyWith(fontSize: 10),
          ),
        Row(
          children: [
            column('我方损失', value.lostSoldiers, value.lostGenerals),
            const SizedBox(width: 12),
            column('击杀敌方', value.killedSoldiers, value.killedGenerals),
          ],
        ),
      ],
    );
  }

  /// 以亿、万和个位分组，省略为零的分组；仅格式化显示，不改变累计计数或精度。
  static String formatCount(int value) {
    if (value <= 0) return '0';
    final yi = value ~/ 100000000;
    final wan = value % 100000000 ~/ 10000;
    final remainder = value % 10000;
    return '${yi > 0 ? '$yi亿' : ''}'
        '${wan > 0 ? '$wan万' : ''}'
        '${remainder > 0 ? remainder : ''}';
  }
}

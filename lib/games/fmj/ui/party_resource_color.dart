import 'package:flutter/painting.dart';

/// 队伍摘要与战斗卡片共用的剩余量配色，避免同一气血/真气出现两套警戒含义。
///
/// 通过整数比较划分20%档位，边界不受浮点误差影响；无有效上限时使用低量颜色，
/// 不执行除法，也不修改角色数值。异常的负数、超上限值只在显示层裁剪。
Color partyResourceColor(int current, int maximum) {
  if (maximum <= 0) return const Color(0xffff7b78);
  final remaining = current.clamp(0, maximum) * 100;
  if (remaining <= maximum * 20) return const Color(0xffff7b78);
  if (remaining <= maximum * 40) return const Color(0xffffb36b);
  if (remaining <= maximum * 60) return const Color(0xfff2d774);
  if (remaining <= maximum * 80) return const Color(0xffbfdc83);
  return const Color(0xff87d5a2);
}

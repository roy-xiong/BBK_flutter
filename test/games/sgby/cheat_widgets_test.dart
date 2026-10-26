import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bbk_flutter/games/sgby/ui/features/game/views/sgby_enemy_arms_limit_slider.dart';

void main() {
  testWidgets('兵力滑块拖动只更新预览，松手一次提交整数，关闭后不可操作', (tester) async {
    final values = <int>[];
    Widget build(bool enabled) => MaterialApp(
      home: Scaffold(
        body: SgbyEnemyArmsLimitSlider(
          value: 800,
          enabled: enabled,
          busy: false,
          onSubmitted: values.add,
        ),
      ),
    );
    await tester.pumpWidget(build(true));
    final slider = find.byType(Slider);
    expect(slider, findsOneWidget);
    final center = tester.getCenter(slider),
        gesture = await tester.startGesture(center);
    await gesture.moveBy(const Offset(80, 0));
    await tester.pump();
    expect(values, isEmpty);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(values.length, 1);
    expect(values.single, inInclusiveRange(800, 200000));
    await tester.pumpWidget(build(false));
    expect(tester.widget<Slider>(slider).onChanged, isNull);
  });
  testWidgets('无效或尚未读取到的兵力配置不会创建越界Slider', (tester) async {
    for (final value in <int?>[null, 799, 200001]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SgbyEnemyArmsLimitSlider(
              value: value,
              enabled: true,
              busy: false,
              onSubmitted: (_) {},
            ),
          ),
        ),
      );
      expect(find.byType(Slider), findsNothing);
      expect(tester.takeException(), isNull);
    }
  });
}

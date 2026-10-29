import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gamepads/gamepads.dart';
import 'package:bbk_flutter/ui/core/gamepad_input.dart';

/// 验证实体手柄的去重、摇杆死区及生命周期，防止重复走格和断连后持续输入。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  NormalizedGamepadEvent event({
    GamepadButton? button,
    GamepadAxis? axis,
    double value = 1,
  }) => NormalizedGamepadEvent(
    gamepadId: 'pad',
    timestamp: 0,
    button: button,
    axis: axis,
    value: value,
    rawEvent: GamepadEvent(
      gamepadId: 'pad',
      timestamp: 0,
      type: button == null ? KeyType.analog : KeyType.button,
      key: 'test',
      value: value,
    ),
  );

  testWidgets('A按住只确认一次，方向短按一格、长按连发，回中和断开立即停止', (tester) async {
    final pulses = <GamepadAction>[];
    final router = GamepadInputRouter(onInput: pulses.add, enabled: () => true);
    router.handle(event(button: GamepadButton.a));
    router.handle(event(button: GamepadButton.a));
    await tester.pump(const Duration(seconds: 1));
    expect(pulses, [GamepadAction.confirm]);
    router.handle(event(axis: GamepadAxis.leftStickX, value: .6));
    router.handle(event(axis: GamepadAxis.leftStickX, value: .7));
    await tester.pump(const Duration(milliseconds: 280));
    expect(pulses.where((e) => e == GamepadAction.right).length, 1);
    await tester.pump(const Duration(milliseconds: 40));
    expect(pulses.where((e) => e == GamepadAction.right).length, 2);
    router.handle(event(axis: GamepadAxis.leftStickX, value: .2));
    await tester.pump(const Duration(seconds: 1));
    expect(pulses.where((e) => e == GamepadAction.right).length, 2);
    router.handle(event(button: GamepadButton.dpadUp));
    router.disconnect('pad');
    final count = pulses.length;
    await tester.pump(const Duration(seconds: 1));
    expect(pulses.length, count);
    router.dispose();
  });

  testWidgets('对话框、失焦和销毁清除连发，十字键优先且斜推只产生一个方向', (tester) async {
    final pulses = <GamepadAction>[];
    var active = true;
    final router = GamepadInputRouter(
      onInput: pulses.add,
      enabled: () => active,
    );
    router.handle(event(axis: GamepadAxis.leftStickY, value: .8));
    router.handle(event(button: GamepadButton.dpadLeft));
    expect(pulses, [GamepadAction.up, GamepadAction.left]);
    active = false;
    await tester.pump(const Duration(milliseconds: 320));
    final count = pulses.length;
    active = true;
    await tester.pump(const Duration(seconds: 1));
    expect(pulses.length, count, reason: '回到游戏不能自动补发旧按住状态');
    router.handle(event(axis: GamepadAxis.leftStickX, value: .2));
    expect(pulses.length, count, reason: '死区噪声不能触发移动');
    router.handle(event(button: GamepadButton.dpadDown));
    router.dispose();
    await tester.pump(const Duration(seconds: 1));
    expect(pulses.length, count + 1);
  });

  testWidgets('北通Xbox360 HID、标准GameController互斥；异常轴值不会发出操作', (tester) async {
    final pulses = <GamepadAction>[];
    final router = GamepadInputRouter(onInput: pulses.add, enabled: () => true);
    router.handleHid({
      'id': 'hid:1',
      'page': 9,
      'usage': 1,
      'value': 1,
      'min': 0,
      'max': 1,
    });
    router.handleHid({
      'id': 'hid:1',
      'page': 9,
      'usage': 1,
      'value': 1,
      'min': 0,
      'max': 1,
    });
    expect(pulses, [GamepadAction.confirm]);
    router.handleHid({
      'id': 'hid:1',
      'page': 9,
      'usage': 12,
      'value': 1,
      'min': 0,
      'max': 1,
    });
    expect(pulses.last, GamepadAction.up);
    router.setNativeControllers({'native'});
    router.handleHid({
      'id': 'hid:1',
      'page': 9,
      'usage': 2,
      'value': 1,
      'min': 0,
      'max': 1,
    });
    expect(pulses.length, 2);
    router.handle(event(axis: GamepadAxis.leftStickY, value: double.nan));
    router.handle(event(axis: GamepadAxis.leftStickY, value: double.infinity));
    expect(pulses.length, 2);
    router.dispose();
  });

  testWidgets('页面离开前清理输入；未提供原生插件时仍能正常打开页面', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('xyz.luan/gamepads'),
          (call) async => call.method == 'listGamepads' ? [] : null,
        );
    await tester.pumpWidget(
      MaterialApp(
        home: GamepadListener(
          onInput: (_) {},
          enabled: () => true,
          child: const Text('game'),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('game'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}

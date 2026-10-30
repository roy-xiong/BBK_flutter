import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bbk_flutter/ui/core/game_screen_awake.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel =
      'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle';
  var calls = 0;
  setUp(() {
    calls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(channel, (_) async {
          calls++;
          return const StandardMessageCodec().encodeMessage(<Object?>[]);
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(channel, null),
  );

  test('游戏路由与策略会话共用租约，旧页面退出不关闭新页面的屏幕常亮', () async {
    final first = GameScreenAwakeController(),
        second = GameScreenAwakeController();
    await first.setEnabled(true);
    expect(calls, 1);
    await second.setEnabled(true);
    expect(calls, 1);
    await first.setEnabled(false);
    expect(calls, 1);
    await second.setEnabled(false);
    expect(calls, 2);
  });
  testWidgets('游戏前台保持常亮，进入后台及退出路由释放，恢复后重新申请', (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(
      const MaterialApp(home: GameScreenAwake(child: Text('game'))),
    );
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(calls, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(calls, 2);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(calls, 3);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(calls, 4);
  });
}

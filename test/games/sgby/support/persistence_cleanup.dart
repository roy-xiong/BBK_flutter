import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:bbk_flutter/games/sgby/ui/features/game/view_models/game_view_model.dart';

/// 同时推进 Widget 测试的虚拟微任务与真实文件 I/O，按完成信号清理存档目录。
Future<void> flushGamePersistence(
  WidgetTester tester,
  GameViewModel model,
) async {
  var completed = false;
  Object? failure;
  unawaited(
    model.flushPersistence().then<void>(
      (_) => completed = true,
      onError: (Object error, StackTrace _) {
        failure = error;
        completed = true;
      },
    ),
  );
  for (var attempt = 0; attempt < 500 && !completed; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(completed, isTrue, reason: '存档队列未能在清理前结束');
  expect(failure, isNull);
}

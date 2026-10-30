import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bbk_flutter/games/fmj/engine/game_actor.dart';
import 'package:bbk_flutter/games/fmj/engine/game_engine.dart';
import 'package:bbk_flutter/games/fmj/ui/game_page.dart';
import 'package:bbk_flutter/games/fmj/ui/game_view_model.dart';
import 'package:bbk_flutter/games/fmj/ui/system_font_layout.dart';
import 'game_engine_test.dart' show loadData;

/// 通过真实游戏页切换场景状态，防止摘要高度改变后再次挤动屏幕按键。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('队伍信息单行完整显示，战斗、菜单和入队不移动操作区', (tester) async {
    final model = (await tester.runAsync(() async {
      final data = await loadData();
      final game = GameEngine(data, textLayout: FlutterSystemFontLayout())
        ..restore(
          jsonDecode(
                File(
                  'test/games/fmj/fixtures/navigation_start.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>,
        )
        ..setPreference('modernUi', true);
      game.players
        ..clear()
        ..addAll([
          for (final id in [1, 2, 3])
            GameActor.load(data, 1, id)!
              ..level = 48
              ..hp = 688
              ..maxHp = 999
              ..mp = 388
              ..maxMp = 999
              ..exp = 123456,
        ]);
      final vm = GameViewModel()
        ..engine = game
        ..loading = false;
      await vm.prepareModernArt();
      final font = FontLoader('BBK CJK')
        ..addFont(rootBundle.load('assets/fonts/NotoSansCJKsc-Regular.otf'));
      await font.load();
      return vm;
    }))!;
    final game = model.engine!;
    const root = Key('stable-controls-capture');
    final keys = [
      'world-information-band',
      'game-surface-layout',
      'fmj-quick-travel-large',
    ];
    Map<String, Rect> geometry() => {
      for (final key in keys) key: tester.getRect(find.byKey(ValueKey(key))),
    };
    void checkMembers(int count) {
      final band = tester.getRect(
        find.byKey(const ValueKey('world-information-band')),
      );
      for (final player in game.players) {
        final row = find.byKey(ValueKey('world-member-${player.index}'));
        final label = tester.widget<Text>(
          find.descendant(of: row, matching: find.byType(Text)),
        );
        expect(label.data, contains('${player.name}  Lv.48'));
        expect(label.data, contains('气血 688/999   魔法 388/999   经验 123456/'));
        expect(label.maxLines, 1);
        final rect = tester.getRect(row);
        expect(band.inflate(.5).contains(rect.topLeft), true);
        expect(band.inflate(.5).contains(rect.bottomRight), true);
      }
      expect(
        find.textContaining('气血 688/999   魔法 388/999   经验 '),
        findsNWidgets(count),
      );
    }

    Future<void> capture(String name) async {
      if (Platform.environment['FMJ_EXPORT_APPROVED_ART'] != '1') return;
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(root),
      );
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        try {
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final dir = Directory('build/validation/current-feedback-v32')
            ..createSync(recursive: true);
          File(
            '${dir.path}/status-$name.png',
          ).writeAsBytesSync(bytes!.buffer.asUint8List());
        } finally {
          image.dispose();
        }
      });
    }

    try {
      for (final size in [
        const Size(320, 568),
        const Size(390, 844),
        const Size(1000, 600),
      ]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        game.battle = null;
        game.menus.clear();
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark().copyWith(
              textTheme: ThemeData.dark().textTheme.apply(
                fontFamily: 'BBK CJK',
              ),
            ),
            home: RepaintBoundary(
              key: root,
              child: GamePage(viewModel: model),
            ),
          ),
        );
        await tester.pump();
        final before = geometry();
        checkMembers(3);
        await capture('${size.width.toInt()}-world');
        model.action(
          (g) => g.battle = GameBattle(
            g,
            monsters: [1, 2],
            background: [2, 2, 2],
            randomFight: true,
          ),
        );
        await tester.pump();
        expect(geometry(), before, reason: '$size 进入战斗时不能上下移动');
        checkMembers(3);
        expect(find.text('战斗 · 第 1 回合'), findsOneWidget);
        await capture('${size.width.toInt()}-battle');
        model.action((g) {
          g.battle = null;
          g.openMainMenu();
        });
        await tester.pump();
        expect(geometry(), before, reason: '$size 打开菜单时不能上下移动');
        checkMembers(3);
        for (final item in ['属性', '魔法', '物品', '系统']) {
          expect(find.text(item).hitTestable(), findsOneWidget);
        }
        await capture('${size.width.toInt()}-menu');
        final others = game.players.skip(1).toList();
        model.action((g) {
          g.menus.clear();
          g.players.removeRange(1, g.players.length);
        });
        await tester.pump();
        expect(geometry(), before, reason: '$size 离队时必须预留空行');
        checkMembers(1);
        model.action((g) => g.players.addAll(others));
        await tester.pump();
        expect(geometry(), before, reason: '$size 入队后操作区必须原位');
        final button = tester.getRect(
          find.byKey(const ValueKey('fmj-wide-view-button')),
        );
        final label = tester.getRect(
          find.text(game.wide ? '远视野 2×' : '原视野 1×'),
        );
        expect(label.left - button.left, greaterThanOrEqualTo(6));
        expect(button.right - label.right, greaterThanOrEqualTo(6));
        expect(tester.takeException(), isNull);
      }
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      model.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
}

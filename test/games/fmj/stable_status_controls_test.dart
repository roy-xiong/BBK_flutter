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
import 'package:bbk_flutter/games/fmj/ui/party_resource_color.dart';
import 'game_engine_test.dart' show loadData;

/// 通过真实游戏页切换场景状态，防止摘要高度改变后再次挤动屏幕按键。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('气血与真气的五档颜色包含边界，异常上限不除零', () {
    for (final sample in <(int, int, Color)>[
      (-1, 100, const Color(0xffff7b78)),
      (0, 0, const Color(0xffff7b78)),
      (20, 100, const Color(0xffff7b78)),
      (201, 1000, const Color(0xffffb36b)),
      (40, 100, const Color(0xffffb36b)),
      (41, 100, const Color(0xfff2d774)),
      (60, 100, const Color(0xfff2d774)),
      (61, 100, const Color(0xffbfdc83)),
      (80, 100, const Color(0xffbfdc83)),
      (81, 100, const Color(0xff87d5a2)),
      (1000, 100, const Color(0xff87d5a2)),
    ]) {
      expect(partyResourceColor(sample.$1, sample.$2), sample.$3);
    }
  });
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
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
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
        final labels = tester.widgetList<Text>(
          find.descendant(of: row, matching: find.byType(Text)),
        );
        expect(
          labels.map((t) => t.data),
          containsAll([
            player.name,
            'Lv.',
            '${player.level}',
            '气血',
            '真气',
            '经验',
            '${player.exp}',
          ]),
        );
        expect(labels.every((t) => t.maxLines == 1), true);
        final rowIndex = game.players.indexOf(player);
        for (final resource in [
          ('hp', player.hp, player.maxHp),
          ('mp', player.mp, player.maxMp),
        ]) {
          final values = tester
              .widgetList<Text>(
                find.descendant(
                  of: find.byKey(
                    ValueKey('world-row-$rowIndex-${resource.$1}'),
                  ),
                  matching: find.byType(Text),
                ),
              )
              .skip(1);
          expect(
            values.every(
              (t) =>
                  t.style?.color ==
                  partyResourceColor(resource.$2, resource.$3),
            ),
            true,
          );
        }
        final rect = tester.getRect(row);
        expect(band.inflate(.5).contains(rect.topLeft), true);
        expect(band.inflate(.5).contains(rect.bottomRight), true);
      }
      expect(find.text('经验'), findsNWidgets(count));
      final money = find.byKey(const ValueKey('world-money'));
      expect(money, findsOneWidget);
      expect(
        find.descendant(of: money, matching: find.text('金钱')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: money, matching: find.text('${game.money}')),
        findsOneWidget,
      );
    }

    /// 比较列边界和数值槽坐标，不能只验证看起来对齐的相同长度字符串。
    Map<String, (double, double)> columns() => {
      for (var row = 0; row < 3; row++)
        for (final field in ['name', 'level', 'hp', 'mp', 'exp'])
          '$row-$field': (
            tester.getRect(find.byKey(ValueKey('world-row-$row-$field'))).left,
            tester.getRect(find.byKey(ValueKey('world-row-$row-$field'))).width,
          ),
      'money': (
        tester.getRect(find.byKey(const ValueKey('world-money'))).left,
        tester.getRect(find.byKey(const ValueKey('world-money'))).width,
      ),
    };

    void checkAlignment() {
      final layout = columns();
      for (final field in ['name', 'level', 'hp', 'mp', 'exp']) {
        for (var row = 1; row < 3; row++) {
          expect(
            layout['$row-$field'],
            layout['0-$field'],
            reason: '$field 上下必须对齐',
          );
        }
      }
      final fonts = <double?>{};
      for (var row = 0; row < game.players.length; row++) {
        for (final field in ['name', 'level', 'hp', 'mp', 'exp']) {
          final texts = tester.widgetList<Text>(
            find.descendant(
              of: find.byKey(ValueKey('world-row-$row-$field')),
              matching: find.byType(Text),
            ),
          );
          fonts.addAll(texts.map((t) => t.style?.fontSize));
        }
      }
      expect(fonts, hasLength(1), reason: '每一行必须共用字号，不能按内容分别缩放');
      final band = find.byKey(const ValueKey('world-information-band'));
      for (final element
          in find
              .descendant(of: band, matching: find.byType(RichText))
              .evaluate()) {
        final paragraph = element.renderObject! as RenderParagraph;
        expect(
          paragraph.didExceedMaxLines,
          false,
          reason: paragraph.text.toPlainText(),
        );
        final content = paragraph.text.toPlainText();
        for (final box in paragraph.getBoxesForSelection(
          TextSelection(baseOffset: 0, extentOffset: content.length),
        )) {
          expect(box.left, greaterThanOrEqualTo(-.1), reason: content);
          expect(
            box.right,
            lessThanOrEqualTo(paragraph.size.width + .1),
            reason: '$content 的末位不能被裁切',
          );
        }
      }
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
        final beforeColumns = columns();
        checkMembers(3);
        checkAlignment();
        await capture('${size.width.toInt()}-world');
        final names = game.players.map((p) => p.name).toList();
        final moneyBefore = game.money;
        model.action((g) {
          for (var i = 0; i < 3; i++) {
            g.players[i]
              ..name = ['清', '慕容小梅', '柳清风'][i]
              ..level = [1, 25, 255][i]
              ..hp = [190, 20, 999][i]
              ..mp = [0, 190, 999][i]
              ..exp = [1, 99999, 2147483647][i];
          }
          g.money = 2147483647;
        });
        await tester.pump();
        expect(columns(), beforeColumns, reason: '一至十位数字、长短名字和满级不能改变列宽');
        expect(geometry(), before);
        checkMembers(3);
        checkAlignment();
        await capture('${size.width.toInt()}-varied-values');
        model.action((g) {
          for (var i = 0; i < 3; i++) {
            g.players[i]
              ..name = names[i]
              ..level = 48
              ..hp = 688
              ..mp = 388
              ..exp = 123456;
          }
          g.money = moneyBefore;
        });
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
        checkAlignment();
        final bars = tester
            .widgetList<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .toList();
        expect(bars, hasLength(6));
        for (var i = 0; i < 3; i++) {
          final p = game.players[i];
          expect(bars[i * 2].color, partyResourceColor(p.hp, p.maxHp));
          expect(bars[i * 2 + 1].color, partyResourceColor(p.mp, p.maxMp));
        }
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
          expect(
            find
                .descendant(
                  of: find.byKey(const ValueKey('fmj-native-menu')),
                  matching: find.text(item),
                )
                .hitTestable(),
            findsOneWidget,
          );
        }
        await capture('${size.width.toInt()}-menu');
        final others = game.players.skip(1).toList();
        model.action((g) {
          g.menus.clear();
          g.players.removeRange(1, g.players.length);
        });
        await tester.pump();
        expect(geometry(), before, reason: '$size 离队时必须预留空行');
        expect(columns(), beforeColumns, reason: '空队员也必须预留同样的列');
        checkMembers(1);
        model.action((g) => g.players.addAll(others));
        await tester.pump();
        expect(geometry(), before, reason: '$size 入队后操作区必须原位');
        expect(columns(), beforeColumns);
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

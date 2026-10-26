import 'dart:ui' as ui;

import '../../domain/models/game_report.dart';
import '../../domain/models/game_world.dart';
import '../resources/baye_database.dart';
import 'cartoon_scene_art.dart';
import 'game_art.dart';

/// 已确认的战争通知样式，只读取报告快照与当前归属，不拥有计时器、输入或回调。
///
/// 保持原报告自动收起时序，不绘制“确认继续”按钮。交战双方与城池均按独立ID
/// 解析，空城、缺失人物和第三方交战不借用默认曹操头像，也不宣称我方获胜。
final class WarReportArt {
  const WarReportArt(this.art, this.resources, this.world, this.report);
  final GameArt art;
  final BayeDatabase resources;
  final GameWorld world;
  final GameReport report;
  static bool supports(GameReportKind kind) => const [
    GameReportKind.attack,
    GameReportKind.fight,
    GameReportKind.victory,
    GameReportKind.defeat,
  ].contains(kind);

  ui.Canvas get canvas => art.canvas;
  int? get cityId =>
      report.city ??
      (report.kind == GameReportKind.attack ? report.target : null);
  bool _valid(int? id) => id != null && world.person(id) != null;
  bool _ours(int? id) => id != null && id == world.playerRulerIndex;
  ui.Color _color(int? id) =>
      _ours(id) ? CartoonSceneArt.red : CartoonSceneArt.blue;
  String _name(int? id) =>
      _valid(id) ? resources.personName(world.period, id!) : '来军';
  String _army(int? id) => _valid(id) ? '${_name(id)}军' : '来军';

  void _text(
    String text,
    ui.Rect rect,
    double size, {
    ui.Color? color,
    bool serif = false,
    ui.TextAlign align = ui.TextAlign.center,
  }) {
    art.text(
      text,
      rect,
      size: size,
      color: color,
      bold: true,
      align: align,
      fontFamily: serif ? 'serif' : null,
    );
  }

  void _portrait(int? id, ui.Rect rect, ui.Color color) {
    art.rounded(rect.inflate(1), color, radius: 2);
    art.rounded(rect, art.paper, radius: 1);
    canvas.save();
    canvas.clipRRect(
      ui.RRect.fromRectAndRadius(rect, const ui.Radius.circular(1)),
    );
    final shown =
        _valid(id) &&
        art.assets?.portrait(canvas, rect, period: world.period, person: id) ==
            true;
    if (!shown) {
      _text('将', rect, 12, color: art.outline);
    }
    canvas.restore();
  }

  void paint() {
    art.geography(const ui.Rect.fromLTWH(0, 0, 240, 144));
    canvas.drawRect(
      const ui.Rect.fromLTWH(0, 0, 240, 144),
      art.paint(const ui.Color(0x77203429)),
    );
    art.panel(const ui.Rect.fromLTWH(7, 6, 224, 131));
    art.rounded(
      const ui.Rect.fromLTWH(10, 9, 218, 125),
      const ui.Color(0xffb99b60),
      radius: 2,
      stroke: .5,
    );
    if (report.kind == GameReportKind.attack ||
        report.kind == GameReportKind.fight) {
      _attack();
    } else {
      _result();
    }
    // 原版等待结束由会话推进；这里仅放静态装饰，不增加需要点击的操作区域。
    canvas.drawLine(
      const ui.Offset(80, 126),
      const ui.Offset(160, 126),
      art.paint(art.gold.withValues(alpha: .55), stroke: .45),
    );
    canvas.drawCircle(const ui.Offset(120, 126), 1.1, art.paint(art.gold));
  }

  void _attack() {
    final attacker = report.actor;
    final city = cityId == null ? null : world.city(cityId!);
    final defender = report.kind == GameReportKind.fight
        ? report.target
        : city != null && city.belong > 0
        ? city.belong - 1
        : null;
    final attackerColor = _color(attacker);
    final defenderColor = defender == null
        ? const ui.Color(0xff77817d)
        : _color(defender);
    final stationing =
        report.kind == GameReportKind.attack &&
        attacker != null &&
        attacker == defender;
    _text(
      stationing ? '部 队 调 动' : '军 情 急 报',
      const ui.Rect.fromLTWH(50, 10, 140, 18),
      12,
      color: const ui.Color(0xff7f332b),
      serif: true,
    );
    _portrait(attacker, const ui.Rect.fromLTWH(28, 33, 33, 40), attackerColor);
    if (defender != null && !stationing) {
      _portrait(
        defender,
        const ui.Rect.fromLTWH(177, 33, 33, 40),
        defenderColor,
      );
    } else if (city == null) {
      _portrait(null, const ui.Rect.fromLTWH(177, 33, 33, 40), defenderColor);
    } else {
      art.rounded(
        const ui.Rect.fromLTWH(176, 32, 35, 42),
        defenderColor,
        radius: 2,
      );
      art.assets?.sprite(
        canvas,
        'city/battle',
        const ui.Rect.fromLTWH(177, 36, 33, 33),
      );
    }
    for (final entry in [
      (28.0, attackerColor, _ours(attacker) ? '我方' : '攻方'),
      (
        177.0,
        defenderColor,
        defender == null
            ? (city == null ? '守方' : '空城')
            : stationing
            ? '己城'
            : _ours(defender)
            ? '我方'
            : '守方',
      ),
    ]) {
      art.rounded(ui.Rect.fromLTWH(entry.$1, 74, 33, 8), entry.$2, radius: .2);
      _text(
        entry.$3,
        ui.Rect.fromLTWH(entry.$1, 74, 33, 8),
        6,
        color: const ui.Color(0xfffffaf0),
      );
    }
    _text(
      _army(attacker),
      const ui.Rect.fromLTWH(12, 84, 66, 16),
      11,
      color: attackerColor,
      serif: true,
    );
    _text(
      stationing
          ? '己方城池'
          : defender == null
          ? (city == null ? '守方未明' : '无主城池')
          : _army(defender),
      const ui.Rect.fromLTWH(162, 84, 66, 16),
      11,
      color: defenderColor,
      serif: true,
    );
    art.assets?.sprite(
      canvas,
      'effect/slash',
      const ui.Rect.fromLTWH(102, 35, 37, 30),
      opacity: .8,
    );
    _text(
      stationing
          ? '进驻'
          : report.kind == GameReportKind.fight
          ? '交战'
          : '进攻',
      const ui.Rect.fromLTWH(94, 67, 50, 16),
      11,
      color: const ui.Color(0xff6c5432),
      serif: true,
    );
    canvas.drawLine(
      const ui.Offset(74, 75),
      const ui.Offset(100, 75),
      art.paint(art.gold, stroke: .7),
    );
    art.path([
      const ui.Offset(151, 72),
      const ui.Offset(165, 75),
      const ui.Offset(151, 78),
    ], art.gold);
    _text(
      city == null ? '两军正在交战' : '目标城池 · ${resources.cityName(cityId!)}',
      const ui.Rect.fromLTWH(35, 101, 170, 17),
      11,
      serif: true,
    );
  }

  void _result() {
    final won = report.kind == GameReportKind.victory;
    final id = won ? report.actor : report.person ?? world.playerRulerIndex;
    final friendly = !won || _ours(id);
    final color = friendly ? CartoonSceneArt.red : CartoonSceneArt.blue;
    final scene =
        'scene/${won ? 'victory' : 'defeat'}${won && !friendly ? '/enemy' : ''}';
    canvas.save();
    canvas.clipRect(const ui.Rect.fromLTWH(11, 10, 216, 56));
    art.assets?.sprite(canvas, scene, const ui.Rect.fromLTWH(11, 10, 216, 56));
    canvas.drawRect(
      const ui.Rect.fromLTWH(11, 10, 216, 56),
      art.paint(const ui.Color(0x55142023)),
    );
    canvas.restore();
    art.rounded(
      const ui.Rect.fromLTWH(18, 20, 26, 29),
      won ? color : const ui.Color(0xff3e5258),
      radius: 2,
    );
    art.rounded(
      const ui.Rect.fromLTWH(18, 20, 26, 29),
      const ui.Color(0xffdfc88f),
      radius: 2,
      stroke: .7,
    );
    _text(
      won ? '胜' : '败',
      const ui.Rect.fromLTWH(18, 20, 26, 29),
      21,
      color: const ui.Color(0xfffff0d0),
      serif: true,
    );
    _text(
      won ? '战斗胜利' : '战斗失败',
      const ui.Rect.fromLTWH(63, 17, 152, 33),
      21,
      color: const ui.Color(0xfffff3d4),
      serif: true,
    );
    _text(
      won ? (friendly ? '捷报传来' : '战局有变') : '此役未捷',
      const ui.Rect.fromLTWH(63, 48, 152, 13),
      7.5,
      color: const ui.Color(0xfff8eacb),
    );
    _portrait(id, const ui.Rect.fromLTWH(20, 76, 29, 34), color);
    _text(
      _army(id),
      const ui.Rect.fromLTWH(62, 71, 96, 17),
      10.5,
      color: color,
      serif: true,
      align: ui.TextAlign.left,
    );
    final city = cityId == null ? null : world.city(cityId!);
    final place = city == null ? '' : resources.cityName(cityId!);
    final headline = place.isEmpty
        ? (won ? '取得战斗胜利' : '部队暂退整备')
        : '$place${won ? '战事告捷' : '战事失利'}';
    _text(
      headline,
      const ui.Rect.fromLTWH(62, 88, 96, 17),
      10.5,
      serif: true,
      align: ui.TextAlign.left,
    );
    final own =
        city != null &&
        world.playerRulerIndex != null &&
        city.belong == world.playerRulerIndex! + 1;
    final chipColor = city == null
        ? color
        : city.belong == 0
        ? const ui.Color(0xff77817d)
        : own
        ? CartoonSceneArt.red
        : CartoonSceneArt.blue;
    final chipText = city == null
        ? (friendly ? '我军' : '敌军')
        : city.belong == 0
        ? '无主城池'
        : own
        ? '我方控制'
        : '敌方控制';
    art.rounded(const ui.Rect.fromLTWH(165, 80, 54, 16), chipColor, radius: 2);
    _text(
      chipText,
      const ui.Rect.fromLTWH(165, 80, 54, 16),
      8,
      color: const ui.Color(0xfffff9e8),
    );
    _text(
      won ? (own ? '城池继续由我方控制' : '${_army(id)}取得胜利') : '请主公重整旗鼓',
      const ui.Rect.fromLTWH(62, 105, 157, 13),
      7,
      color: const ui.Color(0xff66706b),
      align: ui.TextAlign.left,
    );
  }
}

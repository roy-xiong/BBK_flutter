/// 战争通知使用原资源图标，其余消息按是否包含人物显示普通或头像报告。
enum GameReportKind { text, attack, fight, victory, defeat, graphic }

/// 顺序展示的原版报告。人物和通知对象均可空，避免0被误用作缺省人物编号。
final class GameReport {
  const GameReport(
    this.text, {
    this.person,
    this.kind = GameReportKind.text,
    this.actor,
    this.target,
    this.city,
    this.changeFrame,
    this.previousState,
  });
  final String text;
  final int? person;
  final GameReportKind kind;
  final int? actor;
  final int? target;

  /// 战争发生城市；独立于旧版target，避免把交战对手人物ID误当作城市ID。
  final int? city;
  final int? changeFrame;
  final int? previousState;
}

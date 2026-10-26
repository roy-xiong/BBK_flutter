/// 原画布的不可变表现指令。彩色绘制重放同一套坐标与文字，不复制领域状态或输入。
enum BayeDrawKind { fill, line, picture, glyph, bitmap, reverse, base }

final class BayeDrawCommand {
  const BayeDrawCommand(
    this.kind,
    this.x,
    this.y,
    this.right,
    this.bottom, {
    this.color = 255,
    this.resource = 0,
    this.index = 0,
    this.text = '',
  });
  final BayeDrawKind kind;
  final int x, y, right, bottom, color, resource, index;
  final String text;
}

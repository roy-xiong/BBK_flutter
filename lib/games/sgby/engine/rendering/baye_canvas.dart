import 'dart:typed_data';

import '../resources/baye_database.dart';
import '../resources/baye_picture.dart';
import 'pixel_surface.dart';
import 'baye_draw_command.dart';

/// 使用原版逻辑坐标的绘图入口，统一完成4X资源坐标映射。
///
/// 领域层不接触Flutter Canvas或平台字体；每张画面都在同一个帧缓冲内按
/// 原始顺序合成。临时弹窗可以保存/恢复帧缓冲，避免重画底层改变遮挡顺序。
final class BayeCanvas {
  BayeCanvas(this.resources)
    : surface = PixelSurface(
        width: resources.logicalWidth * resources.scale,
        height: resources.logicalHeight * resources.scale,
      );

  final BayeDatabase resources;
  final PixelSurface surface;
  final List<BayeDrawCommand> _commands = [];
  final Expando<List<BayeDrawCommand>> _snapshots = Expando('native-scene');

  /// 每次完整绘制后的只读视图；像素画布和现代画布的层次与热区保持一致。
  List<BayeDrawCommand> get commands => List.unmodifiable(_commands);
  int get scale => resources.scale;
  int get width => resources.logicalWidth;
  int get height => resources.logicalHeight;

  void clear([int color = 0]) {
    _commands.clear();
    surface.clear(color);
  }

  Uint8List snapshot() {
    final bytes = surface.snapshot();
    _snapshots[bytes] = List.of(_commands);
    return bytes;
  }

  void restore(Uint8List bytes) {
    surface.restore(bytes);
    _commands
      ..clear()
      ..addAll(_snapshots[bytes] ?? const []);
  }

  void _record(BayeDrawCommand command) {
    // 开场循环动画只保留有限指令，正常地图/对话每帧均重置；避免长时间停在主菜单
    // 时积累历史动画。快照通过弱键保存，退出菜单后可与像素快照一起回收。
    if (_commands.length >= 12000) _commands.removeRange(0, 6000);
    _commands.add(command);
  }

  /// 标记一张完整原版底图的结束位置，仅供换肤重放弹层；不修改黑白像素。
  void markBase(String scene, {int index = 0}) => _record(
    BayeDrawCommand(BayeDrawKind.base, 0, 0, 0, 0, text: scene, index: index),
  );

  /// 原版矩形的右下端点为包含关系。
  void fill(
    int left,
    int top,
    int right,
    int bottom, [
    int color = 0,
    int animationResource = 0,
  ]) {
    _record(
      BayeDrawCommand(
        BayeDrawKind.fill,
        left,
        top,
        right,
        bottom,
        color: color,
        resource: animationResource,
      ),
    );
    surface.fill(
      left * scale,
      top * scale,
      (right + 1) * scale - 1,
      (bottom + 1) * scale - 1,
      color,
    );
  }

  void reverse(int left, int top, int right, int bottom) {
    _record(BayeDrawCommand(BayeDrawKind.reverse, left, top, right, bottom));
    surface.reverse(
      left * scale,
      top * scale,
      (right + 1) * scale - 1,
      (bottom + 1) * scale - 1,
    );
  }

  void dot(int x, int y, [int color = 255]) => fill(x, y, x, y, color);

  void line(int x0, int y0, int x1, int y1, [int color = 255]) {
    _record(BayeDrawCommand(BayeDrawKind.line, x0, y0, x1, y1, color: color));
    surface.line(
      x0 * scale,
      y0 * scale,
      x1 * scale,
      y1 * scale,
      color: color,
      thickness: scale,
    );
  }

  void rectangle(int left, int top, int right, int bottom, [int color = 255]) {
    line(left, top, right, top, color);
    line(right, top, right, bottom, color);
    line(right, bottom, left, bottom, color);
    line(left, bottom, left, top, color);
  }

  /// 图片编号为0基，图片尺寸已经是4X值，不能重复缩放像素数据。
  void picture(int resource, int index, int x, int y, {int color = 255}) {
    final bitmap = resources.pictures(resource)?.picture(index);
    if (bitmap != null) {
      _record(
        BayeDrawCommand(
          BayeDrawKind.picture,
          x,
          y,
          x + bitmap.width ~/ scale,
          y + bitmap.height ~/ scale,
          resource: resource,
          index: index,
          color: color,
        ),
      );
      surface.blit(bitmap, x * scale, y * scale, color: color);
    }
  }

  void drawBitmap(
    BayeBitmap bitmap,
    int x,
    int y, {
    int color = 255,
    int resource = 0,
    int frame = 0,
  }) {
    _record(
      BayeDrawCommand(
        BayeDrawKind.bitmap,
        x,
        y,
        x + bitmap.width ~/ scale,
        y + bitmap.height ~/ scale,
        color: color,
        resource: resource,
        index: frame,
      ),
    );
    surface.blit(bitmap, x * scale, y * scale, color: color);
  }

  /// 按GamStrShow的6/12逻辑点宽度与换行规则绘制，不使用系统Text布局。
  void text(
    int x,
    int y,
    String value, {
    int left = 0,
    int top = 0,
    int? right,
    int? bottom,
    int color = 255,
  }) {
    textBytes(
      x,
      y,
      resources.codec.encode(value),
      left: left,
      top: top,
      right: right,
      bottom: bottom,
      color: color,
    );
  }

  int textBytes(
    int x,
    int y,
    List<int> bytes, {
    int left = 0,
    int top = 0,
    int? right,
    int? bottom,
    int color = 255,
  }) {
    final lastX = right ?? width - 1;
    final lastY = bottom ?? height - 1;
    if (y < top || y + 12 > lastY) return 0;
    var i = 0;
    for (; i < bytes.length && bytes[i] != 0; i++) {
      var code = bytes[i];
      if (code == 10) {
        x = left;
        y += 12;
        if (y > lastY) break;
        continue;
      }
      final characterWidth = code < 128 ? 6 : 12;
      if (x + characterWidth - 1 > lastX) x += characterWidth - 1;
      if (x > lastX) {
        x = left;
        if (x + characterWidth - 1 > lastX) break;
        y += 12;
        if (y + 12 > lastY) break;
      }
      if (code >= 128) {
        if (i + 1 >= bytes.length) break;
        code = (code << 8) | bytes[++i];
      }
      final encoded = code < 128 ? [code] : [code >> 8, code & 255];
      _record(
        BayeDrawCommand(
          BayeDrawKind.glyph,
          x,
          y,
          x + characterWidth,
          y + 12,
          color: color,
          text: resources.codec.decode(encoded),
        ),
      );
      surface.blit(
        resources.font.glyph(code),
        x * scale,
        y * scale,
        color: color,
      );
      x += characterWidth;
    }
    return i;
  }

  /// 原版通用文字菜单，选中行以帧缓冲反色呈现。
  void graphicMessage(String value, {int? line}) {
    final image = resources.pictures(26);
    if (image == null) return;
    final w = image.width ~/ scale, h = image.height ~/ scale;
    final x = (width - 1 - w) ~/ 2,
        y = line == null ? (height - 1 - h) ~/ 2 : line * 12;
    picture(26, 0, x, y);
    text(x + 10, y + 6, value);
  }

  /// 将文字分四块排到外矩形内、头像矩形外，与PlcStrShowS一致。
  void textAround(
    String value,
    (int, int, int, int) big,
    (int, int, int, int) small,
  ) {
    final regions = [
      (big.$1, big.$2, big.$3, small.$2),
      (big.$1, small.$2, small.$1, small.$4),
      (small.$3, small.$2, big.$3, small.$4),
      (big.$1, small.$4, big.$3, big.$4),
    ];
    final bytes = resources.codec.encode(value);
    var offset = 0;
    for (final r in regions) {
      if (offset >= bytes.length) break;
      offset += textBytes(
        r.$1,
        r.$2,
        bytes.sublist(offset),
        left: r.$1,
        top: r.$2,
        right: r.$3,
        bottom: r.$4,
      );
    }
  }

  /// 原版通用文字菜单，选中行以帧缓冲反色呈现。
  void menu(
    List<String> entries,
    int selected, {
    required int x,
    required int y,
    required int columns,
    required int rows,
    int topIndex = 0,
    bool scrollBlink = false,
    int? pixelWidth,
  }) {
    final right = x + (pixelWidth ?? columns * 6);
    final bottom = y + rows * 12;
    fill(x - 3, y - 3, right + 2, bottom + 2);
    rectangle(x - 3, y - 3, right + 2, bottom + 2);
    for (var row = 0; row < rows && topIndex + row < entries.length; row++) {
      text(
        x,
        y + row * 12,
        entries[topIndex + row],
        left: x,
        top: y,
        right: right,
        bottom: bottom,
      );
    }
    if (selected >= topIndex && selected < topIndex + rows) {
      final lineY = y + (selected - topIndex) * 12;
      reverse(x, lineY, right, lineY + 12);
    }
    if (entries.length > rows) {
      rectangle(right + 2, y - 3, right + 6, bottom + 2);
      rectangle(right + 2, y - 1, right + 6, bottom);
      final position =
          (selected.clamp(topIndex, topIndex + rows) /
                      (entries.length - 1) *
                      (bottom - y - 3) +
                  y)
              .truncate();
      fill(right + 3, position, right + 5, position + 2);
      rectangle(right + 3, position, right + 5, position + 2);
      if (!scrollBlink) reverse(right + 3, position, right + 5, position + 2);
    }
  }
}

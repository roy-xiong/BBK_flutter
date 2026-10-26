import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

/// 可选导出测试实际产生的原生画布，供验证报告展示；不参与参考金图生成。
/// 默认不写文件，只有显式设置SGBY_EXPORT_FRAMES时导出，图片句柄始终释放。
Future<void> exportPixelFrame(Uint8List bytes, String name) async {
  final output = Platform.environment['SGBY_EXPORT_FRAMES'];
  if (output == null || output.isEmpty) return;
  final directory = Directory(output);
  await directory.create(recursive: true);
  final ready = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    bytes,
    960,
    576,
    ui.PixelFormat.rgba8888,
    ready.complete,
  );
  final image = await ready.future;
  try {
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    if (png != null) {
      await File('${directory.path}/$name.png').writeAsBytes(
        png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
      );
    }
  } finally {
    image.dispose();
  }
}

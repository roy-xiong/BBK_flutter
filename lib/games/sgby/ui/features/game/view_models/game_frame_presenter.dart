import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Flutter图片的唯一所有者：上传串行、待处理帧合并、旧图片延迟到绘制结束释放。
///
/// 不为每次逻辑绘制并行创建Codec。页面退出后，尚未返回的解码结果会立即销毁，
/// 不通知监听者；退休图片由集合去重管理，避免dispose与帧回调重复释放。
final class GameFramePresenter extends ChangeNotifier {
  GameFramePresenter({required this.width, required this.height});
  final int width;
  final int height;
  ui.Image? _image;
  Uint8List? _pending;
  bool _busy = false;
  bool _disposed = false;
  Object? error;
  final Set<ui.Image> _retired = <ui.Image>{};
  ui.Image? get image => _image;

  void submit(Uint8List rgba) {
    if (_disposed) return;
    if (rgba.length != width * height * 4) {
      throw const FormatException('显示帧长度无效');
    }
    _pending = rgba;
    if (!_busy) unawaited(_pump());
  }

  Future<void> _pump() async {
    _busy = true;
    try {
      while (!_disposed && _pending != null) {
        final bytes = _pending!;
        _pending = null;
        ui.ImmutableBuffer? buffer;
        ui.ImageDescriptor? descriptor;
        ui.Codec? codec;
        ui.Image? decoded;
        try {
          buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
          if (_disposed) break;
          descriptor = ui.ImageDescriptor.raw(
            buffer,
            width: width,
            height: height,
            rowBytes: width * 4,
            pixelFormat: ui.PixelFormat.rgba8888,
          );
          codec = await descriptor.instantiateCodec();
          decoded = (await codec.getNextFrame()).image;
          if (_disposed) {
            decoded.dispose();
            decoded = null;
            break;
          }
          final previous = _image;
          _image = decoded;
          decoded = null;
          error = null;
          if (previous != null) {
            final retirement = _retired;
            retirement.add(previous);
            SchedulerBinding.instance.addPostFrameCallback((_) {
              if (retirement.remove(previous)) previous.dispose();
            });
          }
          notifyListeners();
        } catch (exception) {
          decoded?.dispose();
          if (!_disposed) {
            error = exception;
            notifyListeners();
          }
        } finally {
          codec?.dispose();
          descriptor?.dispose();
          buffer?.dispose();
        }
      }
    } finally {
      _busy = false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _pending = null;
    _image?.dispose();
    _image = null;
    for (final image in _retired) {
      image.dispose();
    }
    _retired.clear();
    super.dispose();
  }
}

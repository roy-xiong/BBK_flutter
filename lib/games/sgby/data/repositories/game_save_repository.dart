import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../domain/models/game_world.dart';
import '../services/game_save_codec.dart';

/// 独立应用存档仓库，按调用次序串行写入；存取进度不会持有页面或平台Context。
///
/// 每次写入前取得独立JSON快照。主文件和最近一次有效备份均采用同目录临时文件
/// 替换，读取失败时回退有效备份，损坏的主文件不会覆盖已有备份。
final class GameSaveRepository {
  GameSaveRepository({Future<Directory> Function()? directoryProvider})
    : _provider = directoryProvider ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _provider;
  final GameSaveCodec _codec = GameSaveCodec();
  Future<Directory>? _directory;
  Future<void> _writeTail = Future<void>.value();
  static const _gameLimit = 4 * 1024 * 1024;
  static const _settingsLimit = 256 * 1024;

  Future<Directory> _root() => _directory ??= _createRoot();
  Future<Directory> _createRoot() async {
    try {
      final parent = await Future<Directory>.sync(_provider);
      final directory = Directory('${parent.path}/games/sgby');
      if (!await directory.exists()) await directory.create(recursive: true);
      return directory;
    } catch (_) {
      _directory = null;
      rethrow;
    }
  }

  /// 原版允许读取四档、手动存储前三档；第四档保留给已有备份和后续兼容读取。
  void _checkSlot(int slot) {
    if (slot < 0 || slot > 3) throw RangeError.range(slot, 0, 3, 'slot');
  }

  Future<Object?> _read(File file, int maximum) async {
    if (await file.length() > maximum) throw const FormatException('本地文件过大');
    return jsonDecode(await file.readAsString());
  }

  Future<GameWorld?> load(int slot) async {
    _checkSlot(slot);
    await _writeTail;
    final directory = await _root();
    Object? failure;
    StackTrace? trace;
    for (final suffix in ['', '.backup']) {
      final file = File('${directory.path}/slot_$slot.json$suffix');
      if (!await file.exists()) continue;
      try {
        return _codec.decode(await _read(file, _gameLimit));
      } on FormatException catch (error, stack) {
        failure ??= error;
        trace ??= stack;
      } on FileSystemException catch (error, stack) {
        failure ??= error;
        trace ??= stack;
      }
    }
    if (failure != null) Error.throwWithStackTrace(failure, trace!);
    return null;
  }

  Future<void> save(int slot, GameWorld world) {
    _checkSlot(slot);
    final snapshot = jsonEncode(_codec.encode(world));
    return _enqueue(() async {
      final directory = await _root();
      await _atomicWrite(
        File('${directory.path}/slot_$slot.json'),
        snapshot,
        game: true,
      );
    });
  }

  /// 设置损坏时回退备份或默认值，避免偏好文件损坏阻止整个游戏启动。
  Future<Map<String, dynamic>> loadSettings() async {
    await _writeTail;
    final directory = await _root();
    for (final suffix in ['', '.backup']) {
      final file = File('${directory.path}/settings.json$suffix');
      if (!await file.exists()) continue;
      try {
        final value = await _read(file, _settingsLimit);
        if (value is Map<String, dynamic>) return value;
      } on FormatException {
        continue;
      } on FileSystemException {
        continue;
      }
    }
    return <String, dynamic>{};
  }

  Future<void> saveSettings(Map<String, Object?> settings) {
    final snapshot = jsonEncode(settings);
    return _enqueue(() async {
      final directory = await _root();
      await _atomicWrite(
        File('${directory.path}/settings.json'),
        snapshot,
        game: false,
      );
    });
  }

  Future<void> _enqueue(Future<void> Function() action) {
    final operation = _writeTail.then((_) => action());
    _writeTail = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  /// 先验证旧内容再备份。Windows不能覆盖rename目标时，备份覆盖短暂替换窗口。
  Future<void> _replace(File pending, File target) async {
    if (Platform.isWindows && await target.exists()) await target.delete();
    await pending.rename(target.path);
  }

  Future<void> _atomicWrite(
    File target,
    String contents, {
    required bool game,
  }) async {
    final maximum = game ? _gameLimit : _settingsLimit;
    final encoded = utf8.encode(contents);
    if (encoded.length > maximum) throw const FormatException('本地保存内容过大');
    final pending = File('${target.path}.pending');
    final backup = File('${target.path}.backup');
    final backupPending = File('${target.path}.backup.pending');
    try {
      await pending.writeAsBytes(encoded, flush: true);
      var valid = false;
      if (await target.exists()) {
        try {
          final value = await _read(target, maximum);
          if (game) {
            _codec.decode(value);
            valid = true;
          } else {
            valid = value is Map<String, dynamic>;
          }
        } on FormatException {
          valid = false;
        } on FileSystemException {
          valid = false;
        }
      }
      if (valid) {
        await backupPending.writeAsBytes(
          await target.readAsBytes(),
          flush: true,
        );
        await _replace(backupPending, backup);
      }
      await _replace(pending, target);
    } finally {
      if (await pending.exists()) await pending.delete();
      if (await backupPending.exists()) await backupPending.delete();
    }
  }
}

import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// 存档写入按队列串行执行，临时文件与上一份备份位于同一目录。
final class SaveRepository {
  // 公共注入参数不暴露私有缓存字段，便于合集和回归测试指定隔离目录。
  // ignore: prefer_initializing_formals
  SaveRepository({Directory? directory}) : _directory = directory;
  Directory? _directory;
  Future<void> _tail = Future.value();

  /// 等待当前已排队的快照落盘，供宿主备份和测试清理在安全时机读取目录。
  Future<void> flush() => _tail;

  /// 默认写入本应用的伏魔记目录；测试仍可注入独立临时目录。
  Future<Directory> _folder() async {
    final existing = _directory;
    if (existing != null) return existing;
    final support = await getApplicationSupportDirectory();
    final directory = Directory('${support.path}/games/fmj');
    await directory.create(recursive: true);
    return _directory = directory;
  }

  Future<Map<String, dynamic>?> read() async {
    // 重进游戏时先等待上一会话的写入队列，避免读到替换中的文件。
    await _tail;
    final directory = await _folder();
    for (final name in ['fmj-session.json', 'fmj-session.json.bak']) {
      final file = File('${directory.path}/$name');
      if (!await file.exists()) continue;
      try {
        if (await file.length() > 8 * 1024 * 1024) continue;
        final value = jsonDecode(await file.readAsString());
        if (value is Map && value['schema'] == 1) {
          return Map<String, dynamic>.from(value);
        }
      } on FormatException {
        continue;
      } on FileSystemException {
        // 文件被外部占用或读取失败时，仍尝试上一份原子备份。
        continue;
      }
    }
    return null;
  }

  Future<void> write(Map<String, dynamic> value) {
    // 调用时立即冻结快照，排队期间不读取后续变化中的会话对象。
    final contents = jsonEncode(value);
    final operation = _tail.then((_) async {
      final directory = await _folder();
      await directory.create(recursive: true);
      final target = File('${directory.path}/fmj-session.json'),
          temporary = File('${directory.path}/fmj-session.json.tmp'),
          backup = File('${directory.path}/fmj-session.json.bak');
      await temporary.writeAsString(contents, flush: true);
      if (await target.exists()) {
        if (await backup.exists()) await backup.delete();
        await target.rename(backup.path);
      }
      try {
        await temporary.rename(target.path);
      } catch (_) {
        if (!await target.exists() && await backup.exists()) {
          await backup.rename(target.path);
        }
        rethrow;
      }
    });
    _tail = operation.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return operation;
  }
}

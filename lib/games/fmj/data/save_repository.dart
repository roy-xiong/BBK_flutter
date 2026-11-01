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
  bool Function(Map<String, dynamic> value)? _snapshotValidator;

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

  /// 调用方可用真实引擎验证业务快照；主文件外层合法而快照损坏时继续读备份。
  /// 验证过程只读候选文件，不覆盖损坏主档，便于诊断和保留可用的手动档。
  Future<Map<String, dynamic>?> read({
    bool Function(Map<String, dynamic> value)? validate,
  }) async {
    // 重进游戏时先等待上一会话的写入队列，避免读到替换中的文件。
    await _tail;
    // 后续设置读取不能解除已经建立的业务校验；写盘轮转也必须遵守同一标准。
    if (validate != null) _snapshotValidator = validate;
    final directory = await _folder();
    for (final name in ['fmj-session.json', 'fmj-session.json.bak']) {
      final candidate = await _readCandidate(
        File('${directory.path}/$name'),
        validate: validate,
      );
      if (candidate != null) return candidate;
    }
    return null;
  }

  /// 读档与写盘轮转共用校验，不能把仅外层 JSON 合法的坏主档当作可恢复备份。
  Future<Map<String, dynamic>?> _readCandidate(
    File file, {
    bool Function(Map<String, dynamic> value)? validate,
  }) async {
    try {
      if (!await file.exists() || await file.length() > 8 * 1024 * 1024) {
        return null;
      }
      final value = jsonDecode(await file.readAsString());
      if (value is! Map || value['schema'] != 1) return null;
      final candidate = Map<String, dynamic>.from(value);
      return validate == null || validate(candidate) ? candidate : null;
    } on FormatException {
      return null;
    } on FileSystemException {
      // 文件被外部占用或读取失败时，仍尝试上一份原子备份。
      return null;
    }
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
        final previous = await _readCandidate(
          target,
          validate: _snapshotValidator,
        );
        if (previous == null) {
          // 从备份恢复后，原主档仍可能存在但无法恢复。隔离保留诊断材料，
          // 不能让第一次自动保存就删除唯一好备份，并把坏主档换成新的备份。
          await target.rename(
            '${target.path}.corrupt-${DateTime.now().microsecondsSinceEpoch}',
          );
        } else {
          if (await backup.exists()) await backup.delete();
          await target.rename(backup.path);
        }
      }
      try {
        await temporary.rename(target.path);
      } catch (_) {
        if (!await target.exists() &&
            await _readCandidate(backup, validate: _snapshotValidator) !=
                null) {
          // 回滚只复制通过验证的备份，不移动它，失败后仍保留独立恢复入口。
          await backup.copy(target.path);
        }
        rethrow;
      }
    });
    _tail = operation.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return operation;
  }
}

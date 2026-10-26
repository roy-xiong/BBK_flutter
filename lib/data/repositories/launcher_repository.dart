import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../../domain/models/library_game.dart';

/// 仅保存最近选择项。串行写入临时文件后替换，不接触两款游戏的存档。
final class LauncherRepository {
  LauncherRepository({Future<Directory> Function()? directoryProvider})
    : _provider = directoryProvider ?? getApplicationSupportDirectory;
  final Future<Directory> Function() _provider;
  Future<void> _tail = Future<void>.value();

  /// 等待最近选择项落盘；调用者可在此后安全备份或清理本应用目录。
  Future<void> flush() => _tail;

  Future<LibraryGame?> readSelection() async {
    await _tail;
    final root = await _provider();
    final file = File('${root.path}/launcher.json');
    if (!await file.exists() || await file.length() > 4096) return null;
    try {
      final value = jsonDecode(await file.readAsString());
      return value is Map && value['selected'] is String
          ? LibraryGame.fromName(value['selected'] as String)
          : null;
    } on FormatException {
      return null;
    }
  }

  Future<void> saveSelection(LibraryGame game) {
    final snapshot = jsonEncode({'schema': 1, 'selected': game.name});
    final operation = _tail.then((_) async {
      final directory = await _provider();
      await directory.create(recursive: true);
      final target = File('${directory.path}/launcher.json');
      final temporary = File('${target.path}.pending');
      await temporary.writeAsString(snapshot, flush: true);
      if (Platform.isWindows && await target.exists()) await target.delete();
      await temporary.rename(target.path);
    });
    _tail = operation.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return operation;
  }
}

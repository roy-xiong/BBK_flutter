import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

/// 原版资源的 GBK 编解码表；仅解析 ROM 数据，不参与字体绘制。
final class GameEncoding {
  GameEncoding(Map<String, dynamic> table) {
    for (final entry in table.entries) {
      final key = int.tryParse(entry.key);
      final text = entry.value;
      if (key != null && text is String) {
        _decode[key] = text;
        _encode.putIfAbsent(text, () => key);
      }
    }
  }
  final Map<int, String> _decode = {};
  final Map<String, int> _encode = {};

  String decode(Iterable<int> bytes) {
    final data = bytes.toList(growable: false);
    final out = StringBuffer();
    for (var i = 0; i < data.length && data[i] != 0; i++) {
      final a = data[i];
      if (a < 128) {
        out.writeCharCode(a);
      } else if (i + 1 < data.length) {
        out.write(_decode[(a << 8) | data[++i]] ?? '？');
      }
    }
    return out.toString();
  }

  Uint8List encode(String text) {
    final bytes = <int>[];
    for (final rune in text.runes) {
      if (rune < 128) {
        bytes.add(rune);
      } else {
        final code = _encode[String.fromCharCode(rune)] ?? 0xa3bf;
        bytes.addAll([code >> 8, code & 255]);
      }
    }
    return Uint8List.fromList(bytes);
  }
}

/// DAT.LIB 资源的受检视图；格式错误集中转换为可显示的加载错误。
final class GameRecord {
  GameRecord(this.library, this.offset);
  final GameData library;
  final int offset;
  int byte(int at) {
    final index = offset + at;
    if (index < 0 || index >= library.bytes.length) {
      throw const FormatException('游戏资源数据越界');
    }
    return library.bytes[index];
  }

  int word(int at) => byte(at) | (byte(at + 1) << 8);
  int signedByte(int at) => (byte(at) & 127) * (byte(at) & 128 == 0 ? 1 : -1);
  int signedWord(int at) =>
      (word(at) & 32767) * (word(at) & 32768 == 0 ? 1 : -1);
  String text(int at) {
    final end = library.bytes.indexOf(0, offset + at);
    if (end < 0 || end - offset - at > 16384) {
      throw const FormatException('游戏文字缺少结束标记');
    }
    return library.encoding.decode(library.bytes.sublist(offset + at, end));
  }
}

/// 原始图片切片；0 为透明，其他像素按照 RGBA 小端排列。
final class GameBitmap {
  GameBitmap(this.width, this.height, this.pixels)
    : isOpaque = pixels.every((value) => value >> 24 == 255);
  final int width;
  final int height;
  final Uint32List pixels;
  final bool isOpaque;
}

final class GameImage {
  GameImage(this.width, this.height, this.frames, this.byteLength);
  final int width;
  final int height;
  final List<GameBitmap> frames;
  final int byteLength;
  GameBitmap? frame(int index) => frames.isEmpty
      ? null
      : frames[index >= 0 && index < frames.length ? index : 0];
}

/// 地图格同时保留原图块、碰撞位与事件号，不推断额外可行走区域。
final class GameMap {
  GameMap(Map<String, dynamic> json)
    : id = json['id'] as String,
      name = json['name'] as String,
      width = json['width'] as int,
      height = json['height'] as int,
      tiles = json['tiles'] as int,
      cells = (json['cells'] as List).cast<int>();
  final String id;
  final String name;
  final int width;
  final int height;
  final int tiles;
  final List<int> cells;
  int cell(int x, int y) =>
      x < 0 || y < 0 || x >= width || y >= height ? 0 : cells[y * width + x];
  bool canWalk(int x, int y, {bool player = false}) =>
      (!player || (x >= 4 && x < width - 4 && y >= 3 && y < height - 2)) &&
      cell(x, y) & 128 != 0;
  int event(int x, int y) => (cell(x, y) >> 8) & 255;
}

/// ROM 指令的地址使用原事件表坐标，避免选择分支跳到错误指令。
final class GameCommand {
  GameCommand(Map<String, dynamic> json)
    : address = json['at'] as int,
      opcode = json['op'] as int,
      args = (json['a'] as List).cast<int>(),
      text = json['text'];
  final int address;
  final int opcode;
  final List<int> args;
  final dynamic text;
  int arg(int index) => index >= 0 && index < args.length ? args[index] : 0;
  String get string => text is String ? text as String : '';
}

final class GameScript {
  GameScript(Map<String, dynamic> json)
    : id = json['id'] as String,
      name = json['name'] as String,
      events = (json['events'] as List).cast<int>(),
      commands = (json['commands'] as List)
          .map((v) => GameCommand(Map<String, dynamic>.from(v as Map)))
          .toList() {
    for (var i = 0; i < commands.length; i++) {
      addresses[commands[i].address] = i;
    }
  }
  final String id;
  final String name;
  final List<int> events;
  final List<GameCommand> commands;
  final Map<int, int> addresses = {};
}

/// 可复用、带总量限制的资源仓库；退出场景不保留无限数量的大位图。
final class GameData {
  GameData({
    required this.bytes,
    required this.encoding,
    required Map<String, dynamic> guide,
    required this.stages,
  }) {
    if (bytes.length < 0x2003) {
      throw const FormatException('伏魔记资源不完整');
    }
    for (
      var h = 16, p = 8192;
      h + 2 < bytes.length && bytes[h] != 255;
      h += 3, p += 3
    ) {
      if (p + 2 >= bytes.length || h >= 8192) {
        throw const FormatException('资源索引不完整');
      }
      final offset = bytes[p] * 16384 + bytes[p + 1] + bytes[p + 2] * 256;
      if (offset < 0 || offset >= bytes.length) {
        throw const FormatException('资源偏移无效');
      }
      offsets['${bytes[h]}:${bytes[h + 1]}:${bytes[h + 2]}'] = offset;
    }
    for (final value in guide['maps'] as List) {
      final map = GameMap(Map<String, dynamic>.from(value as Map));
      maps[map.id] = map;
    }
    for (final value in guide['scripts'] as List) {
      final script = GameScript(Map<String, dynamic>.from(value as Map));
      scripts[script.id] = script;
    }
  }
  final Uint8List bytes;
  final GameEncoding encoding;
  final List<Map<String, dynamic>> stages;
  final Map<String, int> offsets = {};
  final Map<String, GameMap> maps = {};
  final Map<String, GameScript> scripts = {};
  final LinkedHashMap<int, GameImage> _images = LinkedHashMap();
  int _imageBytes = 0;
  static const int imageBudget = 24 * 1024 * 1024;

  GameRecord? record(int kind, int type, int index) {
    final offset = offsets['$kind:$type:$index'];
    return offset == null ? null : GameRecord(this, offset);
  }

  GameImage? image(int kind, int type, int index) {
    final offset = offsets['$kind:$type:$index'];
    return offset == null ? null : imageAt(offset);
  }

  GameImage imageAt(int offset) {
    final cached = _images.remove(offset);
    if (cached != null) {
      _images[offset] = cached;
      return cached;
    }
    final r = GameRecord(this, offset);
    final width = r.byte(2),
        height = r.byte(3),
        count = r.byte(4),
        bits = r.byte(5);
    if (width == 0 || height == 0 || count == 0 || (bits != 1 && bits != 2)) {
      throw FormatException('图片格式无效：$offset');
    }
    final stride = ((width + 7) ~/ 8) * bits;
    final frameSize = stride * height;
    if (offset + 6 + count * frameSize > bytes.length) {
      throw const FormatException('图片切片越界');
    }
    final frames = <GameBitmap>[];
    for (var f = 0; f < count; f++) {
      final pixels = Uint32List(width * height);
      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
          final bit = x * bits;
          final value = r.byte(6 + f * frameSize + y * stride + bit ~/ 8);
          final color = (value >> (8 - bits - bit % 8)) & ((1 << bits) - 1);
          pixels[y * width + x] = bits == 2 && color & 2 != 0
              ? 0
              : color & 1 == 0
              ? 0xffb4b4b4
              : 0xff000000;
        }
      }
      frames.add(GameBitmap(width, height, pixels));
    }
    final image = GameImage(width, height, frames, 6 + count * frameSize);
    final cost = width * height * count * 4;
    while (_images.isNotEmpty && _imageBytes + cost > imageBudget) {
      final old = _images.remove(_images.keys.first);
      if (old != null) {
        _imageBytes -= old.width * old.height * old.frames.length * 4;
      }
    }
    _images[offset] = image;
    _imageBytes += cost;
    return image;
  }

  static Map<String, dynamic> decodeObject(String value) =>
      Map<String, dynamic>.from(jsonDecode(value) as Map);
}

/// SRS 动画按原帧驻留/下一帧时间推进，保留重叠帧和幕布留下的旧像素。
final class GameMovie {
  GameMovie(GameData data, int type, int index) : id = '$type:$index' {
    final r = data.record(5, type, index);
    if (r == null) throw FormatException('动画不存在：$id');
    final count = r.byte(2), images = r.byte(3);
    for (var i = 0; i < count; i++) {
      headers.add(List<int>.generate(5, (j) => r.byte(6 + i * 5 + j)));
    }
    var offset = r.offset + 6 + count * 5;
    for (var i = 0; i < images; i++) {
      final image = data.imageAt(offset);
      bitmaps.add(image);
      offset += image.byteLength;
    }
    restart();
  }
  final String id;
  final List<List<int>> headers = [];
  final List<GameImage> bitmaps = [];
  final List<List<int>> active = [];
  int iterations = 5;
  void restart() {
    active.clear();
    if (headers.isNotEmpty) active.add([0, headers[0][2], headers[0][3]]);
  }

  bool update() {
    for (var t = 0; t < iterations; t++) {
      final next = <List<int>>[];
      for (final item in active) {
        item[1]--;
        item[2]--;
        final index = item[0] + 1;
        if (item[2] == 0 && index < headers.length) {
          next.add([index, headers[index][2], headers[index][3]]);
        }
      }
      active.removeWhere((v) => v[1] <= 0);
      active.addAll(next);
      if (active.isEmpty) return false;
    }
    return true;
  }
}

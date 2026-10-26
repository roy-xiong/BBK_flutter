import 'dart:math' as math;
import 'dart:typed_data';

import '../../domain/models/game_world.dart';
import '../../domain/use_cases/strategy_commands.dart';
import '../resources/baye_database.dart';
import 'pixel_surface.dart';

/// 原增强脚本的RGBA显示管线：道路→阵营着色→人数点阵。
///
/// 只在战略地图使用，不改动领域数据或随机源。颜色按势力邻接关系缓存，
/// 原画布仍保留8bpp数据，弹出菜单或报告时不会把文字错误染成势力颜色。
final class GameDisplayEnhancements {
  GameDisplayEnhancements(this.resources)
    : commands = StrategyCommands(resources);
  final BayeDatabase resources;
  final StrategyCommands commands;
  String? _signature, _layout;
  Map<int, int> _previous = {};
  Map<int, List<int>> _colors = {};
  static const _red = [211, 47, 47], _road = [126, 132, 138];
  static const _digits = [
    [7, 5, 5, 5, 7],
    [2, 6, 2, 2, 7],
    [7, 1, 7, 4, 7],
    [7, 1, 7, 1, 7],
    [5, 5, 7, 1, 1],
    [7, 4, 7, 1, 7],
    [7, 4, 7, 5, 7],
    [7, 1, 1, 1, 1],
    [7, 5, 7, 5, 7],
    [7, 5, 7, 1, 7],
  ];
  final List<({double hue, double lightness, List<int> rgb})> _palette = [
    for (final hue in [
      60,
      80,
      100,
      120,
      140,
      160,
      180,
      200,
      220,
      240,
      260,
      280,
    ])
      for (final light in [.30, .40, .50, .60])
        (
          hue: hue.toDouble(),
          lightness: light,
          rgb: _hsl(hue.toDouble(), .88, light),
        ),
  ];

  static List<int> _hsl(double hue, double saturation, double lightness) {
    final chroma = (1 - (2 * lightness - 1).abs()) * saturation,
        section = hue / 60;
    final middle = chroma * (1 - (section % 2 - 1).abs()),
        match = lightness - chroma / 2;
    final channels = section < 1
        ? [chroma, middle, 0.0]
        : section < 2
        ? [middle, chroma, 0.0]
        : section < 3
        ? [0.0, chroma, middle]
        : section < 4
        ? [0.0, middle, chroma]
        : section < 5
        ? [middle, 0.0, chroma]
        : [chroma, 0.0, middle];
    return [for (final value in channels) ((value + match) * 255).round()];
  }

  double _separation(
    ({double hue, double lightness, List<int> rgb}) a,
    ({double hue, double lightness, List<int> rgb}) b,
  ) {
    final difference = (a.hue - b.hue).abs();
    return math.min(difference, 360 - difference) +
        (a.lightness - b.lightness).abs() * 90;
  }

  Map<int, List<int>> _factions(GameWorld world) {
    final positions = resources.constant(6),
        ruler = (world.playerRulerIndex ?? -1) + 1;
    final layout = '$ruler:${positions.join(',')}',
        signature =
            '$layout:${world.cities.map((city) => city.belong).join(',')}';
    if (_signature == signature) return _colors;
    final neighbours = <int, Set<int>>{ruler: <int>{}};
    for (final city in world.cities) {
      if (city.belong > 0) neighbours.putIfAbsent(city.belong, () => {});
    }
    void connect(int first, int second) {
      final a = world.city(first)?.belong ?? 0,
          b = world.city(second)?.belong ?? 0;
      if (a == 0 || b == 0 || a == b) return;
      neighbours[a]!.add(b);
      neighbours[b]!.add(a);
    }

    for (var i = 0; i < world.cities.length; i++) {
      for (final next in commands.neighbours(i)) {
        connect(i, next);
      }
      for (var j = i + 1; j < world.cities.length; j++) {
        final dx = positions[i * 2] - positions[j * 2],
            dy = positions[i * 2 + 1] - positions[j * 2 + 1];
        if (dx * dx + dy * dy <= 9) connect(i, j);
      }
    }
    final assigned = <int, ({double hue, double lightness, List<int> rgb})>{
      ruler: (hue: 0, lightness: .506, rgb: _red),
    };
    final colors = <int, List<int>>{0: _road, ruler: _red},
        used = <int>{},
        indexes = <int, int>{};
    final previous = _layout == layout ? _previous : <int, int>{};
    final remaining = neighbours.keys.where((id) => id != ruler).toList();
    while (remaining.isNotEmpty) {
      remaining.sort((a, b) {
        final aa = neighbours[a]!.where(assigned.containsKey).length,
            bb = neighbours[b]!.where(assigned.containsKey).length;
        final score = bb - aa;
        if (score != 0) return score;
        final degree = neighbours[b]!.length - neighbours[a]!.length;
        return degree != 0 ? degree : a - b;
      });
      final id = remaining.removeAt(0);
      // 邻居按编号遍历，和JavaScript整数对象键的稳定顺序一致。
      final near = neighbours[id]!.where(assigned.containsKey).toList()..sort();
      var best = -1, bestScore = double.negativeInfinity;
      for (var i = 0; i < _palette.length; i++) {
        final candidate = _palette[i];
        var distance = 180.0, global = 180.0;
        for (final other in near) {
          distance = math.min(
            distance,
            _separation(candidate, assigned[other]!),
          );
        }
        for (final other in assigned.values) {
          global = math.min(global, _separation(candidate, other));
        }
        final score = distance + global * .1 - (used.contains(i) ? 360 : 0);
        if (previous[id] == i && !used.contains(i) && distance >= 55) {
          best = i;
          break;
        }
        if (score > bestScore) {
          bestScore = score;
          best = i;
        }
      }
      assigned[id] = _palette[best];
      colors[id] = _palette[best].rgb;
      indexes[id] = best;
      used.add(best);
    }
    _signature = signature;
    _layout = layout;
    _previous = indexes;
    _colors = colors;
    return colors;
  }

  Uint8List frame(
    PixelSurface surface,
    GameWorld? world, {
    required bool strategy,
    required bool roads,
    required bool factionColors,
    bool playerBattle = false,
  }) {
    final palette = playerBattle
        ? (List<int>.of(resources.displayPalette)..[128] = 0xff2f2fd3)
        : resources.displayPalette;
    final pixels = surface.rgbaSnapshot(palette: palette);
    if (!strategy || world == null) return pixels;
    final scale = resources.scale,
        width = surface.width,
        height = surface.height;
    final columns = (resources.logicalWidth + 1) ~/ 16 - 2,
        rows = resources.logicalHeight ~/ 16;
    final clipWidth = math.min(width, columns * 16 * scale),
        clipHeight = math.min(height, rows * 16 * scale);
    final positions = resources.constant(6);
    void paint(int x, int y, List<int> color) {
      if (x < 0 || y < 0 || x >= clipWidth || y >= clipHeight) return;
      final p = (y * width + x) * 4;
      pixels[p] = color[0];
      pixels[p + 1] = color[1];
      pixels[p + 2] = color[2];
      pixels[p + 3] = 255;
    }

    if (roads) {
      final seen = <int>{}, radius = scale ~/ 2;
      for (var city = 0; city < world.cities.length; city++) {
        for (final next in commands.neighbours(city)) {
          final edge =
              math.min(city, next) * world.cities.length + math.max(city, next);
          if (!seen.add(edge.toInt())) continue;
          final sx = (positions[city * 2] - world.viewX) * 16 + 8,
              sy = (positions[city * 2 + 1] - world.viewY) * 16 + 8;
          final ex = (positions[next * 2] - world.viewX) * 16 + 8,
              ey = (positions[next * 2 + 1] - world.viewY) * 16 + 8;
          final dx = ex - sx,
              dy = ey - sy,
              length = math.sqrt((ex - sx) * (ex - sx) + (ey - sy) * (ey - sy));
          if (length == 0) continue;
          var x = (sx + dx / length * 6).round() * scale,
              y = (sy + dy / length * 6).round() * scale;
          // 先缩放再四舍五入，保留原脚本的物理像素端点。
          x = ((sx + dx / length * 6) * scale).round();
          y = ((sy + dy / length * 6) * scale).round();
          final tx = ((ex - dx / length * 6) * scale).round(),
              ty = ((ey - dy / length * 6) * scale).round();
          final deltaX = (tx - x).abs(),
              deltaY = (ty - y).abs(),
              stepX = x < tx ? 1 : -1,
              stepY = y < ty ? 1 : -1;
          var error = deltaX - deltaY;
          while (true) {
            for (var oy = -radius; oy <= radius; oy++) {
              for (var ox = -radius; ox <= radius; ox++) {
                paint(x + ox, y + oy, _road);
              }
            }
            if (x == tx && y == ty) break;
            final doubled = error * 2;
            if (doubled > -deltaY) {
              error -= deltaY;
              x += stepX;
            }
            if (doubled < deltaX) {
              error += deltaX;
              y += stepY;
            }
          }
        }
      }
    }
    if (factionColors) {
      final colors = _factions(world);
      for (var i = 0; i < world.cities.length; i++) {
        final x = positions[i * 2] - world.viewX,
            y = positions[i * 2 + 1] - world.viewY;
        if (x < 0 || y < 0 || x >= columns || y >= rows) continue;
        final rgb = colors[world.city(i)!.belong] ?? _road;
        for (var py = (y * 16 + 4) * scale; py < (y * 16 + 12) * scale; py++) {
          for (
            var px = (x * 16 + 4) * scale;
            px < (x * 16 + 12) * scale;
            px++
          ) {
            // 原RGBA色盘224～255满足RGB<32且alpha>160；合成背景前判定。
            final offset = (py * width + px) * 4;
            final road =
                pixels[offset] == 126 &&
                pixels[offset + 1] == 132 &&
                pixels[offset + 2] == 138;
            if (!road && surface.sample(px, py) >= 224) paint(px, py, rgb);
          }
        }
      }
    }
    if (roads) {
      void glyph(String text, int sx, int sy, int offset, List<int> color) {
        for (var digit = 0; digit < text.length; digit++) {
          final rows = _digits[int.parse(text[digit])];
          for (var row = 0; row < 5; row++) {
            for (var col = 0; col < 3; col++) {
              if ((rows[row] & (1 << (2 - col))) == 0) continue;
              final x = (sx + digit * 4 + col + offset) * scale,
                  y = (sy + row + offset) * scale;
              for (var py = 0; py < scale; py++) {
                for (var px = 0; px < scale; px++) {
                  paint(x + px, y + py, color);
                }
              }
            }
          }
        }
      }

      for (var i = 0; i < world.cities.length; i++) {
        final x = positions[i * 2] - world.viewX,
            y = positions[i * 2 + 1] - world.viewY;
        if (x < 0 || y < 0 || x >= columns || y >= rows) continue;
        final city = world.city(i)!,
            count = city.belong == 0
                ? 0
                : world
                      .personsInCity(i, belong: city.belong)
                      .length
                      .clamp(0, 999),
            text = '$count';
        final sx = x * 16 + (16 - (text.length * 4 - 1)) ~/ 2,
            sy = math.max(0, y * 16 - 2);
        glyph(text, sx, sy, 1, [0, 0, 0]);
        glyph(text, sx, sy, 0, [255, 255, 255]);
      }
    }
    return pixels;
  }
}

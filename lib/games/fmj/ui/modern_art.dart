import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'modern_terrain.dart';

/// 高清图片中的一个切片；所有尺寸均为原生图片坐标，不在运行时重新采样生成图片。
final class ModernSprite {
  const ModernSprite(this.texture, this.rect);
  final int texture;
  final ui.Rect rect;
}

/// 从原地图入口事件生成的名牌，与真实出口共用同一地图坐标。
final class SceneLandmark {
  const SceneLandmark(this.x, this.y, this.label, this.target);
  final double x, y;
  final String label, target;
}

/// 房屋完整美术的原地图占地，检测来源为原瓦片连续拼接图案。
final class SceneBuilding {
  const SceneBuilding(
    this.key,
    this.x,
    this.y,
    this.width,
    this.height, {
    this.floor = false,
    this.cells,
    this.visualHeight,
    this.visualWidth,
  });
  final String key;
  final bool floor;
  final int x, y, width, height;

  /// 只有精确匹配的原碎片会被覆盖；地毯矩形中的凳子不能随地毯一起消失。
  final List<int>? cells;

  /// 视觉高度独立于原占地，井等立体物件可向上延伸，碰撞与入口范围不变。
  final double? visualHeight;

  /// 静态掌柜的形象可略宽于原一格占地，中心与脚底仍贴齐原位置，交互格不变。
  final double? visualWidth;
  bool contains(double px, double py) =>
      px >= x && px <= x + width && py >= y && py < y + height;
}

/// 新版共享图集：进入新版时解码一次，退出会话时统一释放 GPU 图片。
///
/// 加载失败会释放已完成的图片；解析过程不暴露半初始化实例。原版资源索引和
/// 高清切片分开保存，使经典渲染、碰撞、动画时序与资源替换相互独立。
final class ModernArt {
  ModernArt(
    this.atlas,
    this.landscape,
    this.frames, {
    this.textures = const [],
    this.sprites = const {},
    this.backgrounds = const {},
    this.groundTextures = const {},
    this.landmarks = const {},
    this.buildings = const {},
    this.decorations = const {},
    this.rooms = const {},
    this.tileOverrides = const {},
  });
  final ui.Image atlas, landscape;
  final Map<String, ui.Rect> frames;
  final List<ui.Image> textures;
  final Map<String, ModernSprite> sprites;
  final Map<String, ui.Image> backgrounds;
  final Map<String, ui.Image> groundTextures;
  final Map<String, List<SceneLandmark>> landmarks;
  final Map<String, List<SceneBuilding>> buildings;
  final Map<String, List<SceneBuilding>> decorations;
  final Map<String, ui.Rect> rooms;

  /// 审核修订限定到明确地图；未审核场景继续使用原图块目录。
  final Map<String, Map<int, (String, String, String?)>> tileOverrides;

  /// 物件只等比缩放并贴齐占地下沿。地图占地是碰撞语义，不能拿来横向、纵向
  /// 分别拉伸原画；地毯是地面图案，单独沿其原有铺设区域绘制。
  static ui.Rect fitObject(ui.Rect source, ui.Rect footprint) {
    if (source.isEmpty || footprint.isEmpty) return ui.Rect.zero;
    final ratio = source.width / source.height;
    final width = (footprint.height * ratio).clamp(0.0, footprint.width);
    final height = width / ratio;
    return ui.Rect.fromLTWH(
      footprint.center.dx - width / 2,
      footprint.bottom - height,
      width,
      height,
    );
  }

  /// 长柜台、书架和纵向隔断由端部与重复的中段组成。保留木作和器物原比例，
  /// 同时覆盖真实占地，不能因整图缩小而留下看似可走的空白阻挡区域。
  bool drawObject(
    ui.Canvas canvas,
    String key,
    ui.Rect footprint,
    ui.Paint paint,
  ) {
    final sprite = sprites[key];
    if (_disposed || sprite == null || footprint.isEmpty) return false;
    final source = sprite.rect;
    final horizontal =
        const {
          'furniture:shop-counter/0',
          'furniture:bookshelf/0',
          'furniture:screen-front/0',
          'furniture:tea-table/0',
          'building:house-north/0',
        }.contains(key) &&
        footprint.width / footprint.height >
            source.width / source.height * 1.35;
    final vertical =
        key == 'furniture:screen-side/0' &&
        footprint.height / footprint.width >
            source.height / source.width * 1.35;
    if (!horizontal && !vertical) {
      canvas.drawImageRect(
        textures[sprite.texture],
        source,
        fitObject(source, footprint),
        paint,
      );
      return true;
    }
    final sourceLength = horizontal ? source.width : source.height;
    final targetLength = horizontal ? footprint.width : footprint.height;
    final scale = horizontal
        ? footprint.height / source.height
        : footprint.width / source.width;
    final cap = sourceLength * .2, capLength = cap * scale;
    void slice(double from, double length, double target, double targetSize) {
      final original = horizontal
          ? ui.Rect.fromLTWH(
              source.left + from,
              source.top,
              length,
              source.height,
            )
          : ui.Rect.fromLTWH(
              source.left,
              source.top + from,
              source.width,
              length,
            );
      final destination = horizontal
          ? ui.Rect.fromLTWH(
              footprint.left + target,
              footprint.top,
              targetSize,
              footprint.height,
            )
          : ui.Rect.fromLTWH(
              footprint.left,
              footprint.top + target,
              footprint.width,
              targetSize,
            );
      canvas.drawImageRect(
        textures[sprite.texture],
        original,
        destination,
        paint,
      );
    }

    slice(0, cap, 0, capLength);
    var cursor = capLength;
    final middle = (sourceLength - cap * 2) * scale;
    while (cursor < targetLength - capLength - .001) {
      final length = (targetLength - capLength - cursor).clamp(0.0, middle);
      if (length <= 0) break;
      slice(cap, length / scale, cursor, length);
      cursor += length;
    }
    slice(sourceLength - cap, cap, targetLength - capLength, capLength);
    return true;
  }

  bool _disposed = false;

  /// 地表采样绑定世界原点，同一镜头内各格共享着色器。缓存按最近使用顺序
  /// 限制为 32 项，移动镜头、切换地图不会无限积累原生 Shader 对象。
  final _groundShaders =
      <
        (String, double, double, double, double, ui.FilterQuality),
        ui.ImageShader
      >{};
  final _groundPaint = ui.Paint()..isAntiAlias = false;

  static Future<ModernArt> load() async {
    final allocated = <ui.Image>[];
    Future<ui.Image> decode(String path) async {
      final data = await rootBundle.load(path);
      final codec = await ui.instantiateImageCodec(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
      try {
        final image = (await codec.getNextFrame()).image;
        allocated.add(image);
        return image;
      } finally {
        codec.dispose();
      }
    }

    ui.Rect rectangle(List<num> values, {int start = 0}) => ui.Rect.fromLTWH(
      values[start].toDouble(),
      values[start + 1].toDouble(),
      values[start + 2].toDouble(),
      values[start + 3].toDouble(),
    );
    try {
      // 保留每项 Future 的具体类型，避免混合 List<Object> 导致 ByteData/String 强转。
      final metadata = rootBundle.loadString(
        'assets/fmj/modern/world-atlas.json',
      );
      final hdMetadata = rootBundle.loadString(
        'assets/fmj/modern/enhanced-art.json',
      );
      final entryMetadata = rootBundle.loadString(
        'assets/fmj/modern/scene-landmarks.json',
      );
      final atlas = await decode('assets/fmj/modern/world-atlas.png');
      final landscape = await decode('assets/fmj/modern/battle-landscape.png');
      final json = jsonDecode(await metadata) as Map<String, dynamic>;
      final frames = json.map(
        (key, value) => MapEntry(key, rectangle((value as List).cast<num>())),
      );
      final hd = jsonDecode(await hdMetadata) as Map<String, dynamic>;
      final textures = <ui.Image>[];
      for (final file in (hd['textures'] as List).cast<String>()) {
        textures.add(await decode('assets/fmj/modern/$file'));
      }
      final sprites = <String, ModernSprite>{};
      for (final entry in (hd['frames'] as Map<String, dynamic>).entries) {
        final values = (entry.value as List).cast<num>();
        if (values.length != 5) {
          throw FormatException('高清切片字段无效：${entry.key}');
        }
        final index = values[0].toInt();
        if (index < 0 || index >= textures.length) {
          throw FormatException('高清切片索引无效：${entry.key}');
        }
        final rect = rectangle(values, start: 1), image = textures[index];
        if (rect.left < 0 ||
            rect.top < 0 ||
            rect.width <= 0 ||
            rect.height <= 0 ||
            rect.right > image.width ||
            rect.bottom > image.height) {
          throw FormatException('高清切片超出图片范围：${entry.key}');
        }
        sprites[entry.key] = ModernSprite(index, rect);
      }
      final backgrounds = <String, ui.Image>{};
      for (final entry in (hd['backgrounds'] as Map<String, dynamic>).entries) {
        backgrounds[entry.key] = await decode(
          'assets/fmj/modern/${entry.value as String}',
        );
      }
      final groundTextures = <String, ui.Image>{};
      for (final entry
          in (hd['groundTextures'] as Map<String, dynamic>? ?? const {})
              .entries) {
        groundTextures[entry.key] = await decode(
          'assets/fmj/modern/${entry.value as String}',
        );
      }
      Map<String, List<SceneBuilding>> objects(String field) =>
          (hd[field] as Map<String, dynamic>? ?? const {}).map(
            (key, value) => MapEntry(
              key,
              List<SceneBuilding>.unmodifiable(
                (value as List).map((v) {
                  final item = v as Map<String, dynamic>;
                  final x = item['x'] as int, y = item['y'] as int;
                  final w = item['width'] as int, h = item['height'] as int;
                  final covered = (item['cells'] as List?)
                      ?.map((v) => (v as num).toInt())
                      .toList(growable: false);
                  final visualHeight = (item['visualHeight'] as num?)
                      ?.toDouble();
                  final visualWidth = (item['visualWidth'] as num?)?.toDouble();
                  if (x < 0 || y < 0 || w <= 0 || h <= 0) {
                    throw FormatException('建筑占地无效：$key');
                  }
                  if (covered?.any((cell) => cell < 0) == true ||
                      visualHeight != null &&
                          (!visualHeight.isFinite || visualHeight <= 0) ||
                      visualWidth != null &&
                          (!visualWidth.isFinite || visualWidth <= 0)) {
                    throw FormatException('物件细节范围无效：$key');
                  }
                  return SceneBuilding(
                    item['key'] as String,
                    x,
                    y,
                    w,
                    h,
                    floor: item['floor'] == true,
                    cells: covered == null ? null : List.unmodifiable(covered),
                    visualHeight: visualHeight,
                    visualWidth: visualWidth,
                  );
                }),
              ),
            ),
          );
      final buildings = objects('buildings'),
          decorations = objects('decorations');
      final landmarkJson =
          jsonDecode(await entryMetadata) as Map<String, dynamic>;
      final landmarks = landmarkJson.map(
        (key, value) => MapEntry(
          key,
          List<SceneLandmark>.unmodifiable(
            (value as List).map((v) {
              final item = v as Map<String, dynamic>;
              return SceneLandmark(
                (item['x'] as num).toDouble(),
                (item['y'] as num).toDouble(),
                item['label'] as String,
                item['target'] as String,
              );
            }),
          ),
        ),
      );
      final tileOverrides = <String, Map<int, (String, String, String?)>>{};
      for (final entry in (hd['tileOverrides'] as Map? ?? const {}).entries) {
        final rules = <int, (String, String, String?)>{};
        for (final row in (entry.value as Map).entries) {
          final tile = int.tryParse('${row.key}'), rule = row.value;
          if (tile == null ||
              tile < 0 ||
              tile > 127 ||
              rule is! List ||
              rule.length != 3 ||
              rule[0] is! String ||
              rule[1] is! String ||
              rule[2] != null && rule[2] is! String) {
            throw FormatException('场景修订图块无效：${entry.key}/${row.key}');
          }
          rules[tile] = (
            rule[0] as String,
            rule[1] as String,
            rule[2] as String?,
          );
        }
        tileOverrides['${entry.key}'] = Map.unmodifiable(rules);
      }
      return ModernArt(
        atlas,
        landscape,
        Map.unmodifiable(frames),
        textures: List.unmodifiable(textures),
        sprites: Map.unmodifiable(sprites),
        tileOverrides: Map.unmodifiable(tileOverrides),
        backgrounds: Map.unmodifiable(backgrounds),
        groundTextures: Map.unmodifiable(groundTextures),
        landmarks: Map.unmodifiable(landmarks),
        buildings: Map.unmodifiable(buildings),
        decorations: Map.unmodifiable(decorations),
        rooms: Map.unmodifiable(
          (hd['rooms'] as Map<String, dynamic>? ?? const {}).map(
            (key, value) =>
                MapEntry(key, rectangle((value as List).cast<num>())),
          ),
        ),
      );
    } catch (_) {
      for (final image in allocated) {
        image.dispose();
      }
      rethrow;
    }
  }

  bool drawSprite(
    ui.Canvas canvas,
    String key,
    ui.Rect target,
    ui.Paint paint,
  ) {
    final sprite = sprites[key];
    if (_disposed || sprite == null) return false;
    canvas.drawImageRect(textures[sprite.texture], sprite.rect, target, paint);
    return true;
  }

  /// 使用独立周期材质连续采样。世界原点一致，不在每格边缘夹取图集像素，
  /// 不镜像草木、碎石和木纹，避免格线及成对的对称纹样。
  bool drawGround(
    ui.Canvas canvas,
    String material,
    ui.Rect target,
    int worldX,
    int worldY,
    ui.Paint paint,
  ) {
    if (_disposed || target.isEmpty) return false;
    final ground = groundTextures[material];
    if (ground != null) {
      // 土路与草地采用更长周期，避免暗色土斑在短距离内重复成网格；铺装保持细节密度。
      final span =
          const {
            'earth',
            'grass',
            'bamboo-forest',
            'mountain-wall',
          }.contains(material)
          ? 8.0
          : 4.0;
      // 审核通过的殿内地板与整面砖墙按每格64px原稿取样，墙梁仅在整面墙的
      // 上下沿出现，不将一整面墙压进四格或给每格重新加木框。
      final spanX = material.startsWith('hall-') ? ground.width / 64.0 : span;
      final spanY = material.startsWith('hall-') ? ground.height / 64.0 : span;
      final tx = target.left - worldX * target.width;
      final ty = target.top - worldY * target.height;
      final key = (
        material,
        target.width,
        target.height,
        tx,
        ty,
        paint.filterQuality,
      );
      var shader = _groundShaders.remove(key);
      if (shader == null) {
        final matrix = Float64List(16)
          ..[0] = target.width * spanX / ground.width
          ..[5] = target.height * spanY / ground.height
          ..[10] = 1
          ..[12] = tx
          ..[13] = ty
          ..[15] = 1;
        shader = ui.ImageShader(
          ground,
          ui.TileMode.repeated,
          ui.TileMode.repeated,
          matrix,
          filterQuality: paint.filterQuality,
        );
      }
      _groundShaders[key] = shader;
      if (_groundShaders.length > 32) {
        _groundShaders.remove(_groundShaders.keys.first)?.dispose();
      }
      canvas.drawRect(
        target,
        _groundPaint
          ..shader = shader
          ..color = paint.color
          ..blendMode = paint.blendMode
          ..filterQuality = paint.filterQuality,
      );
      return true;
    }
    final sprite = sprites['ground:$material/0'];
    if (sprite == null) return false;
    final source = ModernTerrain.source(sprite.rect, worldX, worldY);
    final flipX = ModernTerrain.mirrored(worldX),
        flipY = ModernTerrain.mirrored(worldY);
    if (flipX || flipY) {
      canvas.save();
      canvas.translate(target.center.dx, target.center.dy);
      canvas.scale(flipX ? -1 : 1, flipY ? -1 : 1);
      canvas.drawImageRect(
        textures[sprite.texture],
        source,
        ui.Rect.fromCenter(
          center: ui.Offset.zero,
          width: target.width,
          height: target.height,
        ),
        paint,
      );
      canvas.restore();
    } else {
      canvas.drawImageRect(textures[sprite.texture], source, target, paint);
    }
    return true;
  }

  /// 头像按目标比例裁剪原切片，避免把方形脸像拉成长脸或宽脸。
  bool drawPortrait(
    ui.Canvas canvas,
    String key,
    ui.Rect target,
    ui.Paint paint,
  ) {
    final sprite = sprites[key];
    if (_disposed || sprite == null || target.isEmpty) return false;
    var source = sprite.rect;
    final ratio = target.width / target.height;
    source = source.width / source.height > ratio
        ? ui.Rect.fromCenter(
            center: source.center,
            width: source.height * ratio,
            height: source.height,
          )
        : ui.Rect.fromCenter(
            center: source.center,
            width: source.width,
            height: source.width / ratio,
          );
    canvas.drawImageRect(textures[sprite.texture], source, target, paint);
    return true;
  }

  void draw(
    ui.Canvas canvas,
    String resource,
    int frame,
    ui.Rect target,
    ui.Paint paint,
  ) {
    final source = frames['$resource/$frame'] ?? frames['$resource/0'];
    if (!_disposed && source != null) {
      canvas.drawImageRect(atlas, source, target, paint);
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _groundPaint.shader = null;
    for (final shader in _groundShaders.values) {
      shader.dispose();
    }
    _groundShaders.clear();
    for (final image in [
      atlas,
      landscape,
      ...textures,
      ...backgrounds.values,
      ...groundTextures.values,
    ]) {
      image.dispose();
    }
  }
}

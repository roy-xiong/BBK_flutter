import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:bbk_flutter/games/sgby/domain/models/game_battle.dart';
import 'package:bbk_flutter/games/sgby/domain/use_cases/battle_engine.dart';
import 'package:bbk_flutter/games/sgby/engine/core/native_game_session.dart';
import 'package:bbk_flutter/games/sgby/engine/core/strategy_turn_flow.dart';
import 'package:bbk_flutter/games/sgby/engine/rendering/battle_scene_renderer.dart';
import 'package:bbk_flutter/games/sgby/engine/rendering/cartoon_assets.dart';
import 'package:bbk_flutter/games/sgby/engine/rendering/defeat_art.dart';
import 'package:bbk_flutter/games/sgby/engine/rendering/game_art.dart';
import 'package:bbk_flutter/games/sgby/engine/rendering/realistic_game_painter.dart';

import '../support/game_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late CartoonAssets assets;
  setUpAll(() async {
    assets = await CartoonAssets.load();
    final font = File('/System/Library/Fonts/Hiragino Sans GB.ttc');
    if (font.existsSync()) {
      await (FontLoader('DefeatReview')..addFont(
            Future.value(ByteData.sublistView(font.readAsBytesSync())),
          ))
          .load();
      GameArt.previewFontFamily = 'DefeatReview';
    }
  });
  tearDownAll(() {
    assets.dispose();
    GameArt.previewFontFamily = null;
  });

  Future<Uint8List> render(
    void Function(ui.Canvas) paint, {
    String? output,
    int scale = 3,
  }) async {
    final recorder = ui.PictureRecorder(), canvas = ui.Canvas(recorder);
    paint(canvas);
    final picture = recorder.endRecording();
    final image = await picture.toImage(240 * scale, 144 * scale);
    try {
      final pixels = (await image.toByteData())!.buffer.asUint8List();
      final directory = Platform.environment['SGBY_ART_OUTPUT'];
      if (directory != null && output != null) {
        final file = File('$directory/$output.png');
        file.parent.createSync(recursive: true);
        file.writeAsBytesSync(
          (await image.toByteData(
            format: ui.ImageByteFormat.png,
          ))!.buffer.asUint8List(),
        );
      }
      return pixels;
    } finally {
      image.dispose();
      picture.dispose();
    }
  }

  test('红青六兵种死亡六帧共用锚点，陆地接地与水面沉没独立，结束后无残留', () async {
    for (final friendly in [true, false]) {
      for (var type = 0; type < 6; type++) {
        final side = friendly ? 'friendly' : 'enemy';
        final anchor =
            (assets.manifest['defeatAnchors'] as Map)['$side/$type'] as List;
        expect(anchor, hasLength(3));
        expect((anchor[2] as num).toDouble(), inInclusiveRange(17, 64));
        for (var frame = 0; frame < 6; frame++) {
          expect(assets.spriteRect('defeat/$side/$type/$frame'), isNotNull);
        }
        final samples = <Uint8List>[];
        for (final phase in [0.0, .34, .67, .9, 1.0]) {
          samples.add(
            await render((canvas) {
              canvas.scale(3);
              canvas.drawColor(const ui.Color(0xffadb28a), ui.BlendMode.src);
              DefeatArt(GameArt(canvas, assets: assets)).paint(
                foot: const ui.Offset(120, 75),
                type: type,
                friendly: friendly,
                phase: phase,
                water: type == 3,
              );
            }),
          );
        }
        for (var frame = 1; frame < samples.length; frame++) {
          expect(
            samples[frame],
            isNot(samples[frame - 1]),
            reason: '$side/$type缺少姿态变化',
          );
        }
        final empty = await render(
          (canvas) =>
              canvas.drawColor(const ui.Color(0xffadb28a), ui.BlendMode.src),
        );
        expect(samples.last, empty, reason: '$side/$type结束后仍有漂浮人物、尘土或水纹');
      }
    }
  });

  for (final speed in [1, 8]) {
    test('真实死亡播放器$speed倍完整绘制不改变结算或随机数，回调只发生一次', () async {
      final database = loadGameDatabase(),
          world = loadGameDatabase().loadPeriod(1, seed: 1);
      database.beginGame(world, 5);
      final session = NativeGameSession(database)..replaceWorld(world);
      final battle =
          GameBattle(
              mode: 1,
              city: 8,
              sourceCity: 3,
              way: 0,
              mapId: 1,
              playerFood: 5000,
              enemyFood: 4000,
              people: [
                5,
                ...List<int?>.filled(9, null),
                0,
                ...List<int?>.filled(9, null),
              ],
            )
            ..width = 15
            ..height = 8
            ..focusX = 7
            ..focusY = 4
            ..map = Uint8List.fromList(List.filled(120, 2));
      battle.units[0]
        ..x = 7
        ..y = 4
        ..state = 8;
      session.activeBattle = battle;
      var completed = 0;
      try {
        BattleSceneRenderer(
          session.canvas,
          BattleEngine(database),
        ).draw(world, battle);
        final before = jsonEncode(world.toJson()), random = world.random.state;
        session.playMovie(
          27,
          first: 6,
          last: 11,
          x: 112,
          y: 64,
          sourceType: 1,
          sourceFriendly: true,
          visualEffect: 'defeat',
          completed: () => completed++,
        );
        final frames = <int>{};
        for (var step = 0; step < 300 && completed == 0; step++) {
          final visual = session.movieVisual;
          if (visual != null && frames.add(visual.frame)) {
            await render(
              (canvas) => RealisticGamePainter(
                session,
                assets,
                revision: session.frameVersion,
              ).paint(canvas, const ui.Size(720, 432)),
              output: 'defeat_runtime_${speed}x_${visual.frame}',
            );
          }
          session.advance(const Duration(milliseconds: 10), speed: speed);
        }
        expect(completed, 1);
        expect(frames.length, greaterThan(1));
        session.advance(const Duration(milliseconds: 200), speed: speed);
        expect(completed, 1);
        expect(jsonEncode(world.toJson()), before);
        expect(world.random.state, random);
        expect(battle.units[0].state, 8);
      } finally {
        session.dispose();
      }
    });
  }

  test('导出同一正式绘制器的死亡动作分镜及原版策略提示', () async {
    final output = Platform.environment['SGBY_ART_OUTPUT'];
    if (output == null) return;
    for (final water in [false, true]) {
      await render((canvas) {
        canvas.scale(3);
        canvas.drawColor(
          water ? const ui.Color(0xff568793) : const ui.Color(0xffadb28a),
          ui.BlendMode.src,
        );
        final art = GameArt(canvas, assets: assets);
        for (var i = 0; i < 5; i++) {
          DefeatArt(art).paint(
            foot: ui.Offset(25 + i * 47, 85),
            type: water ? 3 : 1,
            friendly: true,
            phase: [0.0, .25, .5, .75, 1.0][i],
            water: water,
          );
        }
      }, output: water ? 'defeat_water' : 'defeat_land');
    }
    final database = loadGameDatabase(),
        world = loadGameDatabase().loadPeriod(1, seed: 1);
    database.beginGame(world, 5);
    final session = NativeGameSession(database)..replaceWorld(world);
    try {
      StrategyTurnFlow(session).start();
      await render(
        (canvas) => RealisticGamePainter(
          session,
          assets,
          revision: session.frameVersion,
        ).paint(canvas, const ui.Size(720, 432)),
        output: 'strategy_note_color',
      );
      final completer = __image(session.canvas.surface.rgbaSnapshot());
      final image = await completer;
      try {
        File('$output/strategy_note_bw.png').writeAsBytesSync(
          (await image.toByteData(
            format: ui.ImageByteFormat.png,
          ))!.buffer.asUint8List(),
        );
      } finally {
        image.dispose();
      }
    } finally {
      session.dispose();
    }
  });
}

Future<ui.Image> __image(Uint8List bytes) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  final descriptor = ui.ImageDescriptor.raw(
    buffer,
    width: 960,
    height: 576,
    pixelFormat: ui.PixelFormat.rgba8888,
  );
  final codec = await descriptor.instantiateCodec();
  try {
    return (await codec.getNextFrame()).image;
  } finally {
    codec.dispose();
    descriptor.dispose();
    buffer.dispose();
  }
}

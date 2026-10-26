import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'ui/features/game/views/game_page.dart';
import 'ui/core/app_theme.dart';
import 'ui/features/game/view_models/game_view_model.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS) {
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  }
  runApp(const SgbyApp());
}

/// 单游戏独立应用入口，游戏内部画面由原资源帧缓冲提供。
class SgbyApp extends StatefulWidget {
  const SgbyApp({super.key});

  @override
  State<SgbyApp> createState() => _SgbyAppState();
}

class _SgbyAppState extends State<SgbyApp> {
  final GameViewModel viewModel = GameViewModel();
  @override
  void dispose() {
    viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: viewModel,
    builder: (_, _) => MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '三国霸业',
      theme: viewModel.cartoonEnabled
          ? ThemeData(
              colorScheme: ColorScheme.fromSeed(
                seedColor: const Color(0xff3d8b85),
              ),
              useMaterial3: true,
              scaffoldBackgroundColor: const Color(0xffeef6ed),
              appBarTheme: const AppBarTheme(
                backgroundColor: Color(0xfffffcf2),
                foregroundColor: Color(0xff29475b),
              ),
            )
          : AppTheme.dark(),
      home: GamePage(viewModel: viewModel),
    ),
  );
}

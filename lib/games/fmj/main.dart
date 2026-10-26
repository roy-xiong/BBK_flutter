import 'package:flutter/material.dart';
import 'ui/game_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FmjApp());
}

/// 两套游戏界面共用同一入口及会话；系统字体随当前平台自动选择。
final class FmjApp extends StatelessWidget {
  const FmjApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '伏魔记',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xffc6a56b),
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: const Color(0xff11191d),
      useMaterial3: true,
    ),
    home: const GamePage(),
  );
}

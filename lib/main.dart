import 'package:flutter/material.dart';
import 'app.dart';

/// 唯一应用入口。游戏会话仅在用户打开对应游戏后创建。
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BbkApp());
}

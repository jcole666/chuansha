import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/error_log.dart';
import 'core/local_store.dart';
import 'core/supabase_config.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 装全局异常钩子，方便真机排查（设置页可查看/复制日志）
  ErrorLog.install();

  // 本地存储要在路由创建前预热：
  // 路由的 redirect 是同步的，需要同步读到「引导页是否看过」
  await LocalStore.preload();

  // Supabase 初始化
  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.anonKey,
  );

  runApp(const ChuanshaApp());
}

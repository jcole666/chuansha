import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/app_theme.dart';
import 'core/router.dart';

/// 应用顶层组件
///
/// 外层负责包裹 ProviderScope，内层才能拿到 ref 读取路由 Provider
/// （ProviderScope 必须由祖先提供，ChuanshaApp 自身拿不到 ref）
class ChuanshaApp extends StatelessWidget {
  const ChuanshaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const ProviderScope(child: _ChuanshaAppView());
  }
}

/// 真正的 MaterialApp，持有路由
class _ChuanshaAppView extends ConsumerWidget {
  const _ChuanshaAppView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 路由由 Provider 持有：登录态变化时守卫会自动重定向
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: '穿啥',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      routerConfig: router,
    );
  }
}

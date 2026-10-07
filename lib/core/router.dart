import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'constants/routes.dart';
import 'local_store.dart';
import '../app_shell.dart';
import '../features/wardrobe/presentation/pages/wardrobe_page.dart';
import '../features/wardrobe/presentation/pages/add_item_page.dart';
import '../features/wardrobe/presentation/pages/item_detail_page.dart';
import '../features/wardrobe/presentation/pages/edit_item_page.dart';
import '../features/outfit/presentation/pages/outfit_home_page.dart';
import '../features/calendar/presentation/pages/wear_calendar_page.dart';
import '../features/profile/presentation/pages/profile_page.dart';
import '../features/profile/presentation/pages/stats_page.dart';
import '../features/profile/presentation/pages/settings_page.dart';
import '../features/profile/presentation/pages/about_page.dart';
import '../features/profile/presentation/pages/privacy_policy_page.dart';
import '../features/profile/presentation/pages/log_page.dart';
import '../features/auth/presentation/pages/onboarding_page.dart';
import '../features/auth/presentation/pages/auth_page.dart';
import '../features/auth/presentation/providers/auth_provider.dart';

/// 根导航 Key（全屏页面用）
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

/// GoRouter 实例
///
/// 用 Provider 持有而不是全局 final，是为了在 redirect 里能 `ref.read(authProvider)`：
/// 登录态一变就 refresh，守卫自动把用户送到该去的页面。
/// 此前没有任何 redirect，未登录用户可以直接进衣橱，退出登录后也只是原地不动。
final routerProvider = Provider<GoRouter>((ref) {
  // 看过引导页就不再从引导页起步（LocalStore 已在 main() 里 preload）
  final seenOnboarding = LocalStore.seenOnboardingSync;

  final router = GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: seenOnboarding ? AppRoutes.login : AppRoutes.onboarding,
    redirect: (context, state) {
      final authState = ref.read(authProvider);
      final location = state.matchedLocation;

      // 引导页是否算「可停留」取决于用户看没看过：
      // 看过之后就不该再回到引导页了。
      // 这里必须**实时读取** LocalStore，不能用 router 创建时闭包捕获的旧值——
      // 否则「看完引导 → 注册 → 退出登录」会因闭包里的旧值仍是 false
      // 而被塞回引导页（冷启动后才正常）。
      final isOnboarding = location == AppRoutes.onboarding;
      final onboardingAllowed = !LocalStore.seenOnboardingSync;
      final isLogin = location == AppRoutes.login;

      // Supabase 还没给出初始会话（含未初始化的场景）：先不动，
      // 否则首帧会闪一下登录页再跳走。
      if (authState.status == AuthStatus.unknown) return null;

      // 未登录：只能停在引导页（没看过时）/ 登录页
      if (!authState.isLoggedIn) {
        if (isLogin) return null;
        if (isOnboarding && onboardingAllowed) return null;
        // 没看过引导 → 先看引导；看过 → 直接登录
        return onboardingAllowed ? AppRoutes.onboarding : AppRoutes.login;
      }

      // 已登录：引导页 / 登录页都没意义，直接进衣橱
      if (isLogin || isOnboarding) return AppRoutes.wardrobe;

      return null;
    },
    routes: [
      // 新手引导
      GoRoute(
        path: AppRoutes.onboarding,
        pageBuilder: (context, state) =>
            const MaterialPage(child: OnboardingPage()),
      ),

      // 登录/注册
      GoRoute(
        path: AppRoutes.login,
        pageBuilder: (context, state) =>
            const MaterialPage(fullscreenDialog: true, child: AuthPage()),
      ),

      // 底部导航壳（4 Tab）
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return AppShell(navigationShell: navigationShell);
        },
        branches: [
          // Tab 1: 衣橱
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.wardrobe,
                pageBuilder: (context, state) =>
                    const NoTransitionPage(child: WardrobePage()),
              ),
            ],
          ),
          // Tab 2: 搭配（今日推荐 + 我的搭配）
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.outfits,
                pageBuilder: (context, state) =>
                    const NoTransitionPage(child: OutfitHomePage()),
              ),
            ],
          ),
          // Tab 3: 穿搭日历
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.calendar,
                pageBuilder: (context, state) =>
                    const NoTransitionPage(child: WearCalendarPage()),
              ),
            ],
          ),
          // Tab 4: 我的
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.profile,
                pageBuilder: (context, state) =>
                    const NoTransitionPage(child: ProfilePage()),
              ),
            ],
          ),
        ],
      ),

      // 全屏覆盖页面
      GoRoute(
        path: AppRoutes.addItem,
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) =>
            const MaterialPage(fullscreenDialog: true, child: AddItemPage()),
      ),
      GoRoute(
        path: '${AppRoutes.itemDetail}/:itemId',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) {
          final itemId = state.pathParameters['itemId']!;
          return MaterialPage(child: ItemDetailPage(itemId: itemId));
        },
      ),
      GoRoute(
        path: '${AppRoutes.editItem}/:itemId',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) {
          final itemId = state.pathParameters['itemId']!;
          return MaterialPage(
            fullscreenDialog: true,
            child: EditItemPage(itemId: itemId),
          );
        },
      ),
      GoRoute(
        path: AppRoutes.stats,
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) => const MaterialPage(child: StatsPage()),
      ),
      GoRoute(
        path: AppRoutes.settings,
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) =>
            const MaterialPage(child: SettingsPage()),
      ),
      GoRoute(
        path: AppRoutes.about,
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) => const MaterialPage(child: AboutPage()),
      ),
      GoRoute(
        path: AppRoutes.privacy,
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) =>
            const MaterialPage(child: PrivacyPolicyPage()),
      ),
      GoRoute(
        path: AppRoutes.log,
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) => const MaterialPage(child: LogPage()),
      ),
    ],
  );

  var disposed = false;

  // 登录态变化 → 重新跑一次 redirect（等价于 refreshListenable）
  ref.listen<AuthState>(authProvider, (_, __) {
    // 放到微任务里，避免在 build 期间直接触发 Router 重建
    Future.microtask(() {
      if (!disposed) router.refresh();
    });
  });

  ref.onDispose(() {
    disposed = true;
    router.dispose();
  });
  return router;
});

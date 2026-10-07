import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/error_log.dart';
import '../../../../core/local_store.dart';

/// 认证状态
enum AuthStatus { unknown, authenticated, unauthenticated }

/// 认证状态数据
class AuthState {
  final AuthStatus status;
  final User? user;
  final String? errorMessage;
  final bool isLoading;

  const AuthState({
    this.status = AuthStatus.unknown,
    this.user,
    this.errorMessage,
    this.isLoading = false,
  });

  bool get isLoggedIn => status == AuthStatus.authenticated;

  AuthState copyWith({
    AuthStatus? status,
    User? user,
    String? errorMessage,
    bool? isLoading,
  }) {
    return AuthState(
      status: status ?? this.status,
      user: user ?? this.user,
      errorMessage: errorMessage,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

/// 认证 Notifier（Supabase Auth）
class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier() : super(const AuthState()) {
    // 监听认证状态变化。
    // 用 clientOrNull 而不是直接访问 Supabase.instance：
    // 后者在未初始化时会抛异常，而路由在启动阶段就要读 authProvider，
    // 那时可能还没走到 main() 里的 Supabase.initialize。
    final client = clientOrNull;
    if (client == null) return;

    // 同步读一次已缓存的会话：已登录时首帧就能判定，
    // 否则要等 onAuthStateChange 的初始事件，路由守卫会先停在 unknown。
    final cached = client.auth.currentSession;
    if (cached != null) {
      state = AuthState(status: AuthStatus.authenticated, user: cached.user);
    }

    client.auth.onAuthStateChange.listen((data) {
      final session = data.session;
      state = AuthState(
        status: session != null
            ? AuthStatus.authenticated
            : AuthStatus.unauthenticated,
        user: session?.user,
      );
    });
  }

  /// Supabase 客户端；未初始化时返回 null（不抛异常）
  SupabaseClient? get clientOrNull {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  /// 已初始化的客户端；未初始化时抛出明确错误（仅在登录链路中调用）
  SupabaseClient get _requireClient {
    final client = clientOrNull;
    if (client == null) {
      throw StateError('Supabase 尚未初始化，请先完成初始化再调用认证接口');
    }
    return client;
  }

  /// 注册
  Future<void> signUp(String email, String password) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final res = await _requireClient.auth
          .signUp(email: email.trim(), password: password)
          .timeout(const Duration(seconds: 20));

      // 无论 user 是否为 null，都必须复位 isLoading
      state = state.copyWith(
        isLoading: false,
        errorMessage: res.user != null ? null : '注册成功，请前往邮箱验证后登录',
      );
    } on AuthException catch (e) {
      ErrorLog.record('注册', e);
      state = state.copyWith(
        errorMessage: _getErrorMessage(e.message),
        isLoading: false,
      );
    } on TimeoutException {
      state = state.copyWith(errorMessage: '连接超时，请检查网络后重试', isLoading: false);
    } catch (e, s) {
      ErrorLog.record('注册', e, s);
      state = state.copyWith(errorMessage: '注册失败，请检查网络后重试', isLoading: false);
    }
  }

  /// 登录
  Future<void> signIn(String email, String password) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      await _requireClient.auth
          .signInWithPassword(email: email.trim(), password: password)
          .timeout(const Duration(seconds: 20));
      // 成功后 onAuthStateChange 会更新状态，这里确保复位
      state = state.copyWith(isLoading: false);
    } on AuthException catch (e) {
      ErrorLog.record('登录', e);
      state = state.copyWith(
        errorMessage: _getErrorMessage(e.message),
        isLoading: false,
      );
    } catch (e, s) {
      ErrorLog.record('登录', e, s);
      state = state.copyWith(errorMessage: '登录失败，请检查网络后重试', isLoading: false);
    }
  }

  /// 发送重置密码邮件
  ///
  /// 返回**直接展示给用户**的提示文案：失败时是错误原因，
  /// 成功时是一段「下一步该干什么」的说明（调用方 auth_page.dart 直接
  /// `error ?? 兜底文案` 弹 SnackBar，所以这里返回非空文案即可生效）。
  /// 之前没有这个入口，用户忘记密码就直接卡死了。
  ///
  /// ⚠️ redirectTo（深链）暂未配置，这里**故意不传**：
  /// 项目当前没有 app_links / uni_links 依赖，AndroidManifest 里没有自定义
  /// scheme 的 intent-filter，iOS Info.plist 里也没有 CFBundleURLSchemes。
  /// 此时编一个 scheme 会让邮件链接指向一个没人接的地址，比不传更糟
  /// （不传时至少会落到 Supabase 的 Site URL，用户在网页里能改完密码）。
  ///
  /// 待配置深链后再改：
  ///   1. pubspec 加 app_links，AndroidManifest 加 <intent-filter>（scheme）
  ///      且 iOS Info.plist 加 CFBundleURLSchemes；
  ///   2. 下面改成
  ///      `resetPasswordForEmail(trimmed, redirectTo: '<scheme>://reset-callback')`；
  ///   3. 把该 URL 登记到 Supabase 控制台 → Authentication →
  ///      URL Configuration → Redirect URLs，否则 Supabase 会拒绝跳转；
  ///   4. 路由里接住该深链并落到「设置新密码」页（现在没有这个页面）。
  Future<String?> sendPasswordReset(String email) async {
    final trimmed = email.trim();
    if (trimmed.isEmpty) return '请输入邮箱';
    if (!trimmed.contains('@')) return '邮箱格式不正确';

    final client = clientOrNull;
    if (client == null) return '服务未初始化，请重启应用';

    try {
      await client.auth
          .resetPasswordForEmail(trimmed)
          .timeout(const Duration(seconds: 20));
      // 没有深链，邮件里的链接会在浏览器打开，改完密码不会自动回到 App，
      // 所以必须把「回 App 用新密码登录」这一步写清楚，否则用户会卡在网页里。
      return '重置邮件已发送至 $trimmed，请在邮件中打开链接设置新密码，'
          '完成后返回穿啥用新密码登录';
    } on AuthException catch (e) {
      ErrorLog.record('重置密码', e);
      return _getErrorMessage(e.message);
    } on TimeoutException {
      return '连接超时，请检查网络后重试';
    } catch (e, s) {
      ErrorLog.record('重置密码', e, s);
      return '发送失败，请检查网络后重试';
    }
  }

  /// 退出登录
  ///
  /// 退出后 onAuthStateChange 会把状态置为 unauthenticated，
  /// 路由守卫（core/router.dart）会自动把用户送回登录页，无需页面手动跳转。
  Future<void> signOut() async {
    final client = clientOrNull;
    if (client != null) {
      try {
        await client.auth.signOut();
      } catch (_) {
        // 退出失败时兜底：本地也要回到未登录态，避免 UI 与实际会话不一致
        state = const AuthState(status: AuthStatus.unauthenticated);
      }
    }
    // 退出后清空离线缓存：否则下一个账号在断网时会读到上一个账号的缓存数据。
    // 清缓存失败不应阻塞登出，故单独 try/catch。
    try {
      await LocalStore.clearCache();
    } catch (_) {
      // 忽略：清缓存失败不影响登出主流程
    }
  }

  /// 错误消息 → 中文提示
  String _getErrorMessage(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('already registered') ||
        lower.contains('already exists')) {
      return '该邮箱已被注册';
    }
    if (lower.contains('invalid login') ||
        lower.contains('invalid credentials')) {
      return '邮箱或密码错误';
    }
    if (lower.contains('email not confirmed')) {
      return '请先前往邮箱验证';
    }
    if (lower.contains('too many')) {
      return '操作太频繁，请稍后再试';
    }
    if (lower.contains('password should be at least')) {
      return '密码至少 6 位';
    }
    return '认证失败，请稍后重试';
  }
}

/// 认证 Provider
final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier();
});

/// 当前用户 ID 快捷 Provider
final currentUserIdProvider = Provider<String?>((ref) {
  return ref.watch(authProvider).user?.id;
});

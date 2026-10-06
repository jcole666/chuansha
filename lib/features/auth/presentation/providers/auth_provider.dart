import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
      state = state.copyWith(
        errorMessage: _getErrorMessage(e.message),
        isLoading: false,
      );
    } on TimeoutException {
      state = state.copyWith(errorMessage: '连接超时，请检查网络后重试', isLoading: false);
    } catch (e) {
      state = state.copyWith(errorMessage: '注册失败：$e', isLoading: false);
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
      state = state.copyWith(
        errorMessage: _getErrorMessage(e.message),
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(errorMessage: '登录失败：$e', isLoading: false);
    }
  }

  /// 发送重置密码邮件
  ///
  /// 返回错误文案（成功时返回 null）。
  /// 之前没有这个入口，用户忘记密码就直接卡死了。
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
      return null;
    } on AuthException catch (e) {
      return _getErrorMessage(e.message);
    } on TimeoutException {
      return '连接超时，请检查网络后重试';
    } catch (e) {
      return '发送失败：$e';
    }
  }

  /// 退出登录
  ///
  /// 退出后 onAuthStateChange 会把状态置为 unauthenticated，
  /// 路由守卫（core/router.dart）会自动把用户送回登录页，无需页面手动跳转。
  Future<void> signOut() async {
    final client = clientOrNull;
    if (client == null) return;
    try {
      await client.auth.signOut();
    } catch (_) {
      // 退出失败时兜底：本地也要回到未登录态，避免 UI 与实际会话不一致
      state = const AuthState(status: AuthStatus.unauthenticated);
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
    return '认证失败：$raw';
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

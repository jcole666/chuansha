import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/error_log.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_provider.dart';

/// 用户性别
enum UserGender { male, female, unknown }

/// 用户性别 Provider
///
/// 从 Supabase `users` 表读取性别，供分类过滤用。
///
/// 关键点：这里 **订阅了 authProvider**，登录用户一变就自动去拉性别，
/// 不需要任何页面手动调用 loadFromSupabase（此前没人调用，导致性别恒为
/// unknown，录入页判定成男装、编辑页判定成女装，两页分类列表不一致）。
class UserGenderNotifier extends StateNotifier<UserGender> {
  UserGenderNotifier(this._ref) : super(UserGender.unknown) {
    // 监听当前登录用户；响应的只是「用户 id」，isLoading 翻转不会触发。
    _ref.listen<String?>(
      currentUserIdProvider,
      (_, userId) => _sync(userId),
      fireImmediately: true,
    );
  }

  final Ref _ref;

  /// Supabase 客户端；未初始化时返回 null（不抛异常）
  SupabaseClient? get _supabase {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  /// 保证同一用户只在首次登录时拉取一次
  String? _loadedFor;

  Future<void> _sync(String? userId) async {
    if (userId == null || userId.isEmpty) {
      _loadedFor = null;
      state = UserGender.unknown;
      return;
    }
    if (_loadedFor == userId) return;
    await loadFromSupabase(userId);
  }

  /// 从 Supabase 加载用户性别
  Future<void> loadFromSupabase(String userId) async {
    if (userId.isEmpty) return;
    final client = _supabase;
    if (client == null) return;
    try {
      final res = await client
          .from('users')
          .select('gender')
          .eq('id', userId)
          .maybeSingle();

      // 有记录但 gender 为空 / 列不存在时保持 unknown，
      // 由调用方按「未知 = 显示全部」兜底，避免凭空判定成某一性别。
      final gender = res?['gender'] as String?;
      switch (gender) {
        case 'female':
          state = UserGender.female;
        case 'male':
          state = UserGender.male;
        default:
          state = UserGender.unknown;
      }
      _loadedFor = userId;
    } catch (e, s) {
      // 保持 unknown，界面走「显示全部」兜底；但记日志便于排查
      ErrorLog.record('读取性别', e, s);
      state = UserGender.unknown;
    }
  }

  /// 本地立即生效（注册选完性别时用，不必等云端回读）
  void setLocal(UserGender gender) {
    state = gender;
  }

  /// 修改性别并落库（设置页用）
  ///
  /// 返回是否成功。本地状态立即更新，落库失败时回滚并返回 false，
  /// 避免界面显示改了、实际没存上。
  Future<bool> save(UserGender gender) async {
    final userId = _ref.read(currentUserIdProvider);
    if (userId == null || userId.isEmpty) return false;

    final client = _supabase;
    if (client == null) return false;

    final previous = state;
    state = gender; // 先本地生效，界面即时反馈
    try {
      await client.from('users').upsert({
        'id': userId,
        'gender': gender == UserGender.male ? 'male' : 'female',
      });
      _loadedFor = userId; // 标记已同步，避免被回读覆盖
      return true;
    } catch (_) {
      state = previous; // 失败回滚
      return false;
    }
  }
}

/// 用户性别 Provider（全局）
final userGenderProvider =
    StateNotifierProvider<UserGenderNotifier, UserGender>((ref) {
      return UserGenderNotifier(ref);
    });

/// 是否男性 —— 统一判定口径
///
/// 此前 add_item_page 用 `!= UserGender.female`（unknown → 男），
/// edit_item_page 用 `== UserGender.male`（unknown → 女），两页分类不一致。
final isMaleProvider = Provider<bool>((ref) {
  return ref.watch(userGenderProvider) == UserGender.male;
});

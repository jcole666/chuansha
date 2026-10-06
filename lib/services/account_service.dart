import 'package:supabase_flutter/supabase_flutter.dart';

/// 账号服务：注销账号（删除全部数据 + 账号本身）
///
/// 应用市场（尤其 App Store）审核要求提供账号删除入口。
///
/// 删除顺序很重要：
/// 1. Storage 图片
/// 2. 业务数据行（wear_records / outfits / clothing_items / users）
/// 3. auth.users —— 需要 service_role，走 Edge Function
/// 4. 本地登出
class AccountService {
  static const String _bucket = 'clothing';

  SupabaseClient get _client => Supabase.instance.client;

  /// 注销当前账号
  ///
  /// 抛异常表示失败（页面据此提示，不会假装成功）。
  Future<void> deleteAccount() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw Exception('未登录，无法注销');
    }

    // 1. 删除 Storage 里的图片（失败不阻塞：图删不掉也该让账号能注销）
    try {
      final files = await _client.storage
          .from(_bucket)
          .list(path: 'users/$userId');
      if (files.isNotEmpty) {
        final paths = files
            .map((f) => 'users/$userId/${f.name}')
            .toList(growable: false);
        await _client.storage.from(_bucket).remove(paths);
      }
    } catch (_) {
      // 忽略：残留的图片不会导致账号删不掉
    }

    // 2. 删除业务数据。
    //    表若有 ON DELETE CASCADE 其实可省，但显式删更稳妥
    //    （也兼容没配级联的库）。
    await _client.from('wear_records').delete().eq('user_id', userId);
    await _client.from('outfits').delete().eq('user_id', userId);
    await _client.from('clothing_items').delete().eq('user_id', userId);
    await _client.from('users').delete().eq('id', userId);

    // 3. 删除账号本体（必须走 Edge Function，见 supabase/functions/delete-account）
    final res = await _client.functions.invoke('delete-account');
    if (res.status != 200) {
      throw Exception(
        '账号删除失败（HTTP ${res.status}）。'
        '请确认 delete-account 函数已部署，且已配置 SERVICE_ROLE 密钥。',
      );
    }

    // 4. 本地登出（清除本地会话）
    await _client.auth.signOut();
  }
}

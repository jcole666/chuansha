import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/error_log.dart';

/// 账号服务：注销账号（删除账号本身 + 全部数据）
///
/// 应用市场（尤其 App Store）审核要求提供账号删除入口。
///
/// 删除顺序很重要，必须是：
/// 1. auth.users —— 走 Edge Function（需要 service_role），**最先删**
/// 2. Storage 图片
/// 3. 业务数据行（wear_records / outfits / clothing_items / users）
/// 4. 本地登出
///
/// 为什么必须先删账号再删数据：
///   如果反过来（先删业务数据、最后删账号），一旦 Edge Function 未部署
///   或删除失败，衣物/搭配/穿搭记录已经被**永久删除**，账号却还在，
///   用户只看到一句失败提示，数据却不可逆地没了。
///   先删账号则失败发生在第一步，此时什么都没动，用户可直接重试。
///   （JWT 是无状态的，删除 auth 用户后当前会话 token 在过期前仍然有效，
///    所以后续按 auth.uid() 的 RLS 删除依旧能通过。）
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

    // 1. 先删除账号本体（必须走 Edge Function，见 supabase/functions/delete-account）。
    //    这一步失败就立即抛异常中止，绝不触碰任何业务数据。
    final res = await _client.functions.invoke('delete-account');
    if (res.status != 200) {
      throw Exception(
        '账号删除失败（HTTP ${res.status}）。'
        '请确认 delete-account 函数已部署，且已配置 SERVICE_ROLE 密钥。',
      );
    }
    // 函数可能返回 200 但内部失败（body 是 {error: ...} 而非 {ok: true}），
    // 所以必须解析响应体，只有 ok == true 才算成功。
    final data = res.data;
    final ok = data is Map && data['ok'] == true;
    if (!ok) {
      final message = (data is Map ? data['error'] : null) ?? '未知错误';
      throw Exception('账号删除失败：$message');
    }

    // 2. 删除 Storage 里的图片（失败不阻塞：账号已删，图删不掉也不影响注销）
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
    } catch (e, s) {
      // 容忍：残留图片不会导致注销失败，但记日志便于事后清理
      ErrorLog.record('注销-删除图片', e, s);
    }

    // 3. 删除业务数据行。
    //    表若有 ON DELETE CASCADE 其实可省，但显式删更稳妥
    //    （也兼容没配级联的库）。
    //    这里失败必须抛异常：账号已删但业务数据残留属于异常状态，需要上报。
    await _client.from('wear_records').delete().eq('user_id', userId);
    await _client.from('outfits').delete().eq('user_id', userId);
    await _client.from('clothing_items').delete().eq('user_id', userId);
    await _client.from('users').delete().eq('id', userId);

    // 4. 本地登出（清除本地会话）
    await _client.auth.signOut();
  }
}

import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../core/error_log.dart';

/// 图片上传服务
///
/// 把衣物图片上传到 Supabase Storage `clothing` 桶
/// 返回公开访问 URL
class ImageUploadService {
  static const String _bucket = 'clothing';

  static const _uuid = Uuid();

  SupabaseClient get _client => Supabase.instance.client;

  /// 上传图片，返回公开 URL
  ///
  /// [userId] 上传者（用于文件路径隔离）
  /// [file] 本地图片文件
  Future<String> uploadItemImage({
    required String userId,
    required File file,
  }) async {
    final ext = file.path.split('.').last.toLowerCase();
    final safeExt = ext.length > 1 && ext.length <= 4 ? ext : 'jpg';

    // 文件名用随机 UUID 而不是时间戳：
    // bucket 目前是 public（URL 无需鉴权即可访问），时间戳可被预测、
    // 配合 userId 就能推出他人图片地址。随机名让路径不可枚举/不可猜，
    // 与 rls_policies.sql 里收紧后的读策略形成双重防护。
    final path = 'users/$userId/${_uuid.v4()}.$safeExt';

    await _client.storage.from(_bucket).upload(path, file);

    // 获取公开 URL
    return _client.storage.from(_bucket).getPublicUrl(path);
  }

  /// 从公开 URL 反推 storage 内的对象路径
  ///
  /// 形如 `https://xxx.supabase.co/storage/v1/object/public/clothing/users/uid/1.png`
  /// → `users/uid/1.png`；不是本 bucket 的 URL 返回 null。
  String? _pathFromPublicUrl(String url) {
    final marker = '/object/public/$_bucket/';
    final idx = url.indexOf(marker);
    if (idx < 0) return null;
    final path = url.substring(idx + marker.length);
    // 去掉可能的 query string
    final q = path.indexOf('?');
    return q < 0 ? path : path.substring(0, q);
  }

  /// 删除图片（换图后清理旧文件，避免存储里堆孤儿图）
  ///
  /// 失败不抛异常：删不掉旧图不该阻塞用户保存新图。
  /// 返回是否真的删掉了。
  Future<bool> deleteItemImage(String imageUrl) async {
    final path = _pathFromPublicUrl(imageUrl);
    if (path == null || path.isEmpty) return false;
    try {
      await _client.storage.from(_bucket).remove([path]);
      return true;
    } catch (e, s) {
      // 删不掉会留孤儿文件，记日志便于排查
      ErrorLog.record('删除旧图', e, s);
      return false;
    }
  }
}

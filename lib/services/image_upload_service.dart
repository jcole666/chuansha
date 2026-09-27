import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 图片上传服务
///
/// 把衣物图片上传到 Supabase Storage `clothing` 桶
/// 返回公开访问 URL
class ImageUploadService {
  static const String _bucket = 'clothing';

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
    final path = 'users/$userId/${DateTime.now().millisecondsSinceEpoch}.$safeExt';

    await _client.storage.from(_bucket).upload(path, file);

    // 获取公开 URL
    return _client.storage.from(_bucket).getPublicUrl(path);
  }
}

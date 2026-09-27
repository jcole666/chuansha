import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../domain/enums/clothing_status.dart';
import '../models/clothing_item.dart';
import 'wardrobe_repository.dart';

/// Supabase 版衣橱仓库
///
/// 对接 Supabase `clothing_items` 表
class SupabaseWardrobeRepository implements WardrobeRepository {
  final _uuid = const Uuid();

  SupabaseClient get _client => Supabase.instance.client;

  @override
  Future<List<ClothingItem>> getItems(String userId) async {
    final res = await _client
        .from('clothing_items')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false);

    final items = (res as List)
        .map((row) => ClothingItem.fromJson(row as Map<String, dynamic>))
        .toList();
    return items;
  }

  @override
  Future<ClothingItem> addItem(ClothingItem item) async {
    // 先确保 users 表里有这个用户，否则插入会因外键约束失败
    await _ensureUserExists(item.userId);

    final id = item.id.isNotEmpty ? item.id : _uuid.v4();
    final saved = item.copyWith(
      id: id,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    await _client.from('clothing_items').insert(saved.toJson());
    return saved;
  }

  /// 确保 users 表里有该用户记录。
  ///
  /// clothing_items.user_id 外键指向 users.id，如果注册后没往 users 表插记录，
  /// 保存衣物会报 23503 外键错误。这里幂等地补一条。
  ///
  /// 注意：只插 id 这一列（不碰 updated_at 等可能不存在的列），
  /// 避免 PGRST204（schema cache 里找不到列）。
  Future<void> _ensureUserExists(String userId) async {
    final existing = await _client
        .from('users')
        .select('id')
        .eq('id', userId)
        .maybeSingle();

    if (existing != null) return;

    await _client.from('users').insert({'id': userId});
  }

  @override
  Future<ClothingItem> updateItem(ClothingItem item) async {
    final updated = item.copyWith(updatedAt: DateTime.now());
    final data = updated.toJson()..remove('id');
    await _client
        .from('clothing_items')
        .update(data)
        .eq('id', item.id);
    return updated;
  }

  @override
  Future<void> deleteItem(String itemId) async {
    await _client.from('clothing_items').delete().eq('id', itemId);
  }

  @override
  Future<ClothingItem?> getItem(String itemId) async {
    final res = await _client
        .from('clothing_items')
        .select()
        .eq('id', itemId)
        .maybeSingle();
    if (res == null) return null;
    return ClothingItem.fromJson(res);
  }

  @override
  Future<void> updateStatusBatch(
      List<String> itemIds, ClothingStatus status) async {
    if (itemIds.isEmpty) return;
    await _client
        .from('clothing_items')
        .update({
          'status': status.name,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .inFilter('id', itemIds);
  }
}

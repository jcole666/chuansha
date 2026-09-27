import 'package:uuid/uuid.dart';
import '../../domain/enums/clothing_status.dart';
import '../models/clothing_item.dart';
import 'wardrobe_repository.dart';

/// 内存版衣橱仓库（开发用）
///
/// 数据只在内存中，重启丢失。后续替换为 FirestoreWardrobeRepository
class InMemoryWardrobeRepository implements WardrobeRepository {
  final _items = <String, ClothingItem>{};
  final _uuid = const Uuid();

  /// 模拟当前用户 ID（后续接入 Auth 后替换）
  static const String mockUserId = 'dev_user_001';

  @override
  Future<List<ClothingItem>> getItems(String userId) async {
    // 模拟网络延迟
    await Future.delayed(const Duration(milliseconds: 300));
    return _items.values
        .where((item) => item.userId == userId)
        .toList()
      // 最新添加的排前面
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  @override
  Future<ClothingItem> addItem(ClothingItem item) async {
    await Future.delayed(const Duration(milliseconds: 500));
    final id = item.id.isNotEmpty ? item.id : _uuid.v4();
    final saved = item.copyWith(
      id: id,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    _items[id] = saved;
    return saved;
  }

  @override
  Future<ClothingItem> updateItem(ClothingItem item) async {
    await Future.delayed(const Duration(milliseconds: 300));
    final updated = item.copyWith(updatedAt: DateTime.now());
    _items[item.id] = updated;
    return updated;
  }

  @override
  Future<void> deleteItem(String itemId) async {
    await Future.delayed(const Duration(milliseconds: 300));
    _items.remove(itemId);
  }

  @override
  Future<ClothingItem?> getItem(String itemId) async {
    await Future.delayed(const Duration(milliseconds: 200));
    return _items[itemId];
  }

  @override
  Future<void> updateStatusBatch(
      List<String> itemIds, ClothingStatus status) async {
    if (itemIds.isEmpty) return;
    await Future.delayed(const Duration(milliseconds: 300));
    for (final id in itemIds) {
      final item = _items[id];
      if (item != null) {
        _items[id] = item.copyWith(status: status, updatedAt: DateTime.now());
      }
    }
  }
}

import '../models/clothing_item.dart';
import '../../domain/enums/clothing_status.dart';

/// 衣橱数据仓库接口
///
/// 先用内存实现开发，后期换 Firestore 实现
abstract class WardrobeRepository {
  /// 获取用户的所有衣物
  Future<List<ClothingItem>> getItems(String userId);

  /// 添加一件衣物
  Future<ClothingItem> addItem(ClothingItem item);

  /// 更新衣物信息
  Future<ClothingItem> updateItem(ClothingItem item);

  /// 删除衣物
  Future<void> deleteItem(String itemId);

  /// 根据 ID 获取单件衣物
  Future<ClothingItem?> getItem(String itemId);

  /// 批量更新衣物状态（如多选后一键标记已洗/待洗）
  Future<void> updateStatusBatch(List<String> itemIds, ClothingStatus status);
}

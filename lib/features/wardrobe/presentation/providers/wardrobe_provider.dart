import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../data/models/clothing_item.dart';
import '../../../../../data/repositories/supabase_wardrobe_repository.dart';
import '../../../../../data/repositories/wardrobe_repository.dart';
import '../../../../../domain/enums/clothing_status.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

/// 仓库实例（Provider）
///
/// 使用 Supabase 实现，数据持久化到云端（无需 Google 服务）
final wardrobeRepositoryProvider = Provider<WardrobeRepository>((ref) {
  return SupabaseWardrobeRepository();
});

/// 排序方式
enum WardrobeSortBy {
  newest, // 最近添加
  mostWorn, // 穿着最多
  priceHigh, // 价格最高
  priceLow, // 价格最低
}

/// 排序方式显示名
extension WardrobeSortByLabel on WardrobeSortBy {
  String get label {
    switch (this) {
      case WardrobeSortBy.newest:
        return '最近添加';
      case WardrobeSortBy.mostWorn:
        return '穿着最多';
      case WardrobeSortBy.priceHigh:
        return '价格最高';
      case WardrobeSortBy.priceLow:
        return '价格最低';
    }
  }
}

/// 衣橱列表状态
class WardrobeListState {
  /// 全部衣物
  final List<ClothingItem> allItems;
  final bool isLoading;
  final String? errorMessage;

  /// 筛选条件
  final String? selectedCategory;
  final String? selectedColor;
  final String? selectedStyle;

  /// 搜索关键词
  final String searchQuery;

  /// 排序
  final WardrobeSortBy sortBy;

  /// 视图模式
  final bool isGridView;

  const WardrobeListState({
    this.allItems = const [],
    this.isLoading = false,
    this.errorMessage,
    this.selectedCategory,
    this.selectedColor,
    this.selectedStyle,
    this.searchQuery = '',
    this.sortBy = WardrobeSortBy.newest,
    this.isGridView = true,
  });

  /// 经过筛选、搜索、排序后的列表
  List<ClothingItem> get filteredItems {
    var result = List<ClothingItem>.from(allItems);

    // 按分类筛选
    if (selectedCategory != null && selectedCategory!.isNotEmpty) {
      result = result
          .where((item) => item.category == selectedCategory)
          .toList();
    }

    // 按颜色筛选（模糊匹配颜色名称）
    if (selectedColor != null && selectedColor!.isNotEmpty) {
      result = result.where((item) {
        return item.colors.any((c) => c.name == selectedColor);
      }).toList();
    }

    // 按风格筛选
    if (selectedStyle != null && selectedStyle!.isNotEmpty) {
      result = result.where((item) {
        return item.styleTags.contains(selectedStyle);
      }).toList();
    }

    // 关键词搜索（匹配名称/品牌/分类）
    if (searchQuery.isNotEmpty) {
      final query = searchQuery.toLowerCase();
      result = result.where((item) {
        return item.name.toLowerCase().contains(query) ||
            (item.brand?.toLowerCase().contains(query) ?? false) ||
            item.category.contains(query);
      }).toList();
    }

    // 排序
    switch (sortBy) {
      case WardrobeSortBy.newest:
        result.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        break;
      case WardrobeSortBy.mostWorn:
        result.sort((a, b) => b.wearCount.compareTo(a.wearCount));
        break;
      case WardrobeSortBy.priceHigh:
        result.sort((a, b) => (b.price ?? 0).compareTo(a.price ?? 0));
        break;
      case WardrobeSortBy.priceLow:
        result.sort((a, b) => (a.price ?? 0).compareTo(b.price ?? 0));
        break;
    }

    return result;
  }

  WardrobeListState copyWith({
    List<ClothingItem>? allItems,
    bool? isLoading,
    String? errorMessage,
    String? selectedCategory,
    String? selectedColor,
    String? selectedStyle,
    String? searchQuery,
    WardrobeSortBy? sortBy,
    bool? isGridView,
  }) {
    return WardrobeListState(
      allItems: allItems ?? this.allItems,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
      selectedCategory: selectedCategory ?? this.selectedCategory,
      selectedColor: selectedColor ?? this.selectedColor,
      selectedStyle: selectedStyle ?? this.selectedStyle,
      searchQuery: searchQuery ?? this.searchQuery,
      sortBy: sortBy ?? this.sortBy,
      isGridView: isGridView ?? this.isGridView,
    );
  }
}

/// 衣橱列表 Notifier
class WardrobeListNotifier extends StateNotifier<WardrobeListState> {
  final WardrobeRepository _repository;
  final Ref _ref;

  WardrobeListNotifier(this._repository, this._ref)
    : super(const WardrobeListState());

  /// 当前用户 ID（未登录时为 null）
  String? get _userId => _ref.read(currentUserIdProvider);

  /// 加载衣物列表
  Future<void> loadItems() async {
    final userId = _userId;
    if (userId == null) return;

    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final items = await _repository.getItems(userId);
      state = state.copyWith(allItems: items, isLoading: false);
    } catch (e) {
      state = state.copyWith(errorMessage: '加载失败：$e', isLoading: false);
    }
  }

  /// 添加一件衣物
  ///
  /// 返回是否成功。失败时同时写入 errorMessage 并把异常重新抛出，
  /// 让调用方能拿到真实失败（原来只塞 errorMessage 不抛，
  /// 页面无条件弹「保存成功」—— 用户以为存上了，刷新却没了）。
  Future<bool> addItem(ClothingItem item) async {
    try {
      await _repository.addItem(item);
      await loadItems();
      return true;
    } catch (e) {
      state = state.copyWith(errorMessage: '添加失败：$e');
      rethrow;
    }
  }

  /// 更新衣物
  Future<bool> updateItem(ClothingItem item) async {
    try {
      await _repository.updateItem(item);
      await loadItems();
      return true;
    } catch (e) {
      state = state.copyWith(errorMessage: '更新失败：$e');
      rethrow;
    }
  }

  /// 删除衣物
  Future<bool> deleteItem(String itemId) async {
    try {
      await _repository.deleteItem(itemId);
      await loadItems();
      return true;
    } catch (e) {
      state = state.copyWith(errorMessage: '删除失败：$e');
      rethrow;
    }
  }

  /// 批量更新衣物状态（多选后一键标记已洗/待洗等）
  ///
  /// 注意：本地状态**在落库成功之后**才更新，
  /// 否则失败时界面已经变了、刷新又变回去。
  Future<bool> updateStatusBatch(
    List<String> ids,
    ClothingStatus status,
  ) async {
    if (ids.isEmpty) return true;
    try {
      await _repository.updateStatusBatch(ids, status);
      // 直接更新本地状态，避免全量 loadItems 导致网格闪烁
      final updated = state.allItems
          .map(
            (item) =>
                ids.contains(item.id) ? item.copyWith(status: status) : item,
          )
          .toList();
      state = state.copyWith(allItems: updated);
      return true;
    } catch (e) {
      state = state.copyWith(errorMessage: '批量更新失败：$e');
      rethrow;
    }
  }

  /// 设置分类筛选（点"全部"或再点一次取消）
  ///
  /// 注意：这里不能依赖 copyWith 传 null 来清空（copyWith 里
  /// `selectedCategory ?? this.selectedCategory` 会把 null 吞掉），
  /// 所以清空时直接手动构造 state。
  void setCategoryFilter(String? category) {
    final clear = category == null || state.selectedCategory == category;
    state = WardrobeListState(
      allItems: state.allItems,
      isLoading: state.isLoading,
      errorMessage: state.errorMessage,
      selectedCategory: clear ? null : category,
      selectedColor: state.selectedColor,
      selectedStyle: state.selectedStyle,
      searchQuery: state.searchQuery,
      sortBy: state.sortBy,
      isGridView: state.isGridView,
    );
  }

  /// 设置颜色筛选（点"全部"或再点一次取消）
  void setColorFilter(String? color) {
    final clear = color == null || state.selectedColor == color;
    state = WardrobeListState(
      allItems: state.allItems,
      isLoading: state.isLoading,
      errorMessage: state.errorMessage,
      selectedCategory: state.selectedCategory,
      selectedColor: clear ? null : color,
      selectedStyle: state.selectedStyle,
      searchQuery: state.searchQuery,
      sortBy: state.sortBy,
      isGridView: state.isGridView,
    );
  }

  /// 设置风格筛选（点"全部"或再点一次取消）
  void setStyleFilter(String? style) {
    final clear = style == null || state.selectedStyle == style;
    state = WardrobeListState(
      allItems: state.allItems,
      isLoading: state.isLoading,
      errorMessage: state.errorMessage,
      selectedCategory: state.selectedCategory,
      selectedColor: state.selectedColor,
      selectedStyle: clear ? null : style,
      searchQuery: state.searchQuery,
      sortBy: state.sortBy,
      isGridView: state.isGridView,
    );
  }

  /// 设置搜索关键词
  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
  }

  /// 设置排序方式
  void setSortBy(WardrobeSortBy sortBy) {
    state = state.copyWith(sortBy: sortBy);
  }

  /// 切换视图模式
  void toggleViewMode() {
    state = state.copyWith(isGridView: !state.isGridView);
  }

  /// 指定视图模式（设置页用，需与本地存储保持一致）
  void setGridView(bool value) {
    if (state.isGridView == value) return;
    state = state.copyWith(isGridView: value);
  }

  /// 根据 ID 获取单件衣物
  ClothingItem? getItemById(String id) {
    try {
      return state.allItems.firstWhere((item) => item.id == id);
    } catch (_) {
      return null;
    }
  }
}

/// 衣橱列表 Provider
final wardrobeListProvider =
    StateNotifierProvider<WardrobeListNotifier, WardrobeListState>((ref) {
      final repository = ref.watch(wardrobeRepositoryProvider);
      return WardrobeListNotifier(repository, ref);
    });

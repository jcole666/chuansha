import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../../core/constants/routes.dart';
import '../../../../../core/constants/category_data.dart';
import '../../../../../core/constants/color_data.dart';
import '../../../../../core/error_log.dart';
import '../../../../../shared/widgets/empty_state.dart';
import '../../../../../shared/widgets/error_view.dart';
import '../../../../../shared/widgets/shimmer_card.dart';
import '../../../../../shared/widgets/item_image.dart';
import '../../../../../shared/widgets/offline_banner.dart';
import '../../../../../shared/widgets/clothing_status_badge.dart';
import '../../../../../data/models/clothing_item.dart';
import '../../../../../domain/enums/clothing_status.dart';
import '../../../auth/presentation/providers/gender_provider.dart'
    show isMaleProvider;
import '../providers/wardrobe_provider.dart';

/// 衣橱页面
///
/// V1 功能：网格/列表浏览 + 筛选 + 搜索 + 排序 + 空状态 + FAB
/// V2 功能：长按多选，批量标记衣物状态（已洗/待洗/干洗中/在洗衣房）
class WardrobePage extends ConsumerStatefulWidget {
  const WardrobePage({super.key});

  @override
  ConsumerState<WardrobePage> createState() => _WardrobePageState();
}

class _WardrobePageState extends ConsumerState<WardrobePage> {
  late TextEditingController _searchController;
  bool _showSearch = false;

  /// 多选模式下已选中的衣物 ID
  final Set<String> _selectedIds = {};

  /// 是否处于多选模式
  bool get _isSelectionMode => _selectedIds.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    Future.microtask(() {
      ref.read(wardrobeListProvider.notifier).loadItems();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(wardrobeListProvider);
    final notifier = ref.read(wardrobeListProvider.notifier);

    return PopScope(
      // 多选模式下按返回键先退出多选，再退出页面
      canPop: !_isSelectionMode,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _exitSelectionMode();
      },
      child: Scaffold(
        appBar: _buildAppBar(state, notifier),
        body: Column(
          children: [
            // 离线提示：数据来自本地缓存时明确告知
            if (state.isOffline && state.allItems.isNotEmpty)
              OfflineBanner(onRetry: () => notifier.loadItems()),
            // 多选模式下隐藏：搜索栏、筛选栏、排序栏
            if (!_isSelectionMode) ...[
              if (_showSearch) _buildSearchBar(notifier),
              _buildFilterBar(state, notifier),
              _buildSortBar(state, notifier),
            ],
            // 内容区
            Expanded(child: _buildBody(state, notifier)),
          ],
        ),
        // 多选模式下隐藏 FAB，底部显示批量操作栏
        floatingActionButton: _isSelectionMode
            ? null
            : FloatingActionButton(
                onPressed: () => context.push(AppRoutes.addItem),
                tooltip: '添加衣服',
                child: const Icon(Icons.add),
              ),
        bottomNavigationBar: _isSelectionMode
            ? _buildBatchActionBar(state, notifier)
            : null,
      ),
    );
  }

  /// 退出多选模式
  void _exitSelectionMode() {
    setState(() => _selectedIds.clear());
  }

  /// 全选 / 取消全选（只针对当前筛选结果）
  void _toggleSelectAll(List<ClothingItem> items) {
    setState(() {
      if (_selectedIds.length == items.length && items.isNotEmpty) {
        _selectedIds.clear();
      } else {
        _selectedIds
          ..clear()
          ..addAll(items.map((e) => e.id));
      }
    });
  }

  /// AppBar
  PreferredSizeWidget _buildAppBar(
    WardrobeListState state,
    WardrobeListNotifier notifier,
  ) {
    // 多选模式：标题"已选 N 件"，leading 关闭，隐藏原 actions
    if (_isSelectionMode) {
      return AppBar(
        title: Text('已选 ${_selectedIds.length} 件'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: '退出多选',
          onPressed: _exitSelectionMode,
        ),
      );
    }

    return AppBar(
      title: _showSearch ? null : const Text('我的衣橱'),
      actions: [
        // 搜索
        IconButton(
          icon: Icon(_showSearch ? Icons.close : Icons.search),
          onPressed: () {
            setState(() {
              _showSearch = !_showSearch;
              if (!_showSearch) {
                _searchController.clear();
                notifier.setSearchQuery('');
              }
            });
          },
        ),
        // 视图切换
        IconButton(
          icon: Icon(
            state.isGridView
                ? Icons.view_list_rounded
                : Icons.grid_view_rounded,
          ),
          onPressed: () => notifier.toggleViewMode(),
        ),
      ],
    );
  }

  /// 底部批量操作栏（多选模式）
  Widget _buildBatchActionBar(
    WardrobeListState state,
    WardrobeListNotifier notifier,
  ) {
    final items = state.filteredItems;
    final allSelected = items.isNotEmpty && _selectedIds.length == items.length;

    return Container(
      // 跟随主题：深色模式下不能是白条
      color: Theme.of(context).colorScheme.surface,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 全选/取消全选
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _toggleSelectAll(items),
              icon: Icon(
                allSelected ? Icons.deselect : Icons.select_all,
                size: 18,
              ),
              label: Text(allSelected ? '取消全选' : '全选'),
            ),
          ),
          const SizedBox(height: 4),
          // 4 个状态按钮
          Row(
            children: ClothingStatus.values.map((status) {
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: OutlinedButton(
                    onPressed: _selectedIds.isEmpty
                        ? null
                        : () => _applyBatchStatus(notifier, status),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: ClothingStatusBadge.colorFor(status),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      side: BorderSide(
                        color: ClothingStatusBadge.colorFor(
                          status,
                        ).withValues(alpha: 0.5),
                      ),
                    ),
                    child: Text(
                      status.label,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  /// 应用批量状态
  Future<void> _applyBatchStatus(
    WardrobeListNotifier notifier,
    ClothingStatus status,
  ) async {
    final ids = _selectedIds.toList();
    if (ids.isEmpty) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      final ok = await notifier.updateStatusBatch(ids, status);
      _exitSelectionMode();
      if (ok) {
        messenger.showSnackBar(
          SnackBar(content: Text('已将 ${ids.length} 件衣物标记为「${status.label}」')),
        );
      } else {
        final msg = ref.read(wardrobeListProvider).errorMessage ?? '标记失败';
        messenger.showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (e, s) {
      // 失败时不退出选择模式，方便用户重试。
      // 技术细节（如 PostgrestException）记入 ErrorLog，对用户只暴露人话，
      // 避免把原始异常直接甩到界面上。
      ErrorLog.record('批量标记', e, s);
      messenger.showSnackBar(const SnackBar(content: Text('批量标记失败，请检查网络后重试')));
    }
  }

  /// 搜索栏
  Widget _buildSearchBar(WardrobeListNotifier notifier) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: TextField(
        controller: _searchController,
        autofocus: true,
        onChanged: notifier.setSearchQuery,
        decoration: InputDecoration(
          hintText: '搜索名称、品牌、分类...',
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: () {
                    _searchController.clear();
                    notifier.setSearchQuery('');
                  },
                )
              : null,
          filled: true,
          fillColor: context.subtleFillColor,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
        ),
      ),
    );
  }

  /// 筛选栏（分类一行、颜色一行）
  Widget _buildFilterBar(
    WardrobeListState state,
    WardrobeListNotifier notifier,
  ) {
    // 统一口径：只有明确是女性才走女装分类，unknown 时显示全部
    final isMale = ref.watch(isMaleProvider);
    final categories = CategoryData.getMainCategoriesForGender(isMale: isMale);

    return Column(
      children: [
        // 第一行：分类（衣服类型）——"全部"固定左侧，其余可滚动
        SizedBox(
          height: 36,
          child: Row(
            children: [
              // 固定的"全部"
              Padding(
                padding: const EdgeInsets.only(left: 12),
                child: _buildFilterChip(
                  label: '全部',
                  isSelected: state.selectedCategory == null,
                  onTap: () => notifier.setCategoryFilter(null),
                ),
              ),
              // 其余分类可横向滚动
              Expanded(
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  children: [
                    ...categories.map((cat) {
                      return _buildFilterChip(
                        label: cat,
                        isSelected: state.selectedCategory == cat,
                        onTap: () => notifier.setCategoryFilter(cat),
                      );
                    }),
                  ],
                ),
              ),
            ],
          ),
        ),
        // 第二行：颜色——"全部"固定左侧，其余可滚动
        SizedBox(
          height: 36,
          child: Row(
            children: [
              // 固定的"全部"
              Padding(
                padding: const EdgeInsets.only(left: 12),
                child: _buildColorFilterChip(
                  hex: 'FF6C63FF',
                  label: '全部',
                  isSelected: state.selectedColor == null,
                  onTap: () => notifier.setColorFilter(null),
                ),
              ),
              // 其余颜色可横向滚动
              Expanded(
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  children: [
                    ...ColorData.presetColors.keys.map((color) {
                      return _buildColorFilterChip(
                        hex: ColorData.presetColors[color]!,
                        label: color,
                        isSelected: state.selectedColor == color,
                        onTap: () => notifier.setColorFilter(color),
                      );
                    }),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 排序栏
  Widget _buildSortBar(WardrobeListState state, WardrobeListNotifier notifier) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Text(
            '共 ${state.filteredItems.length} 件',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const Spacer(),
          // 排序下拉
          PopupMenuButton<WardrobeSortBy>(
            onSelected: notifier.setSortBy,
            itemBuilder: (_) => WardrobeSortBy.values.map((s) {
              return PopupMenuItem(
                value: s,
                child: Row(
                  children: [
                    if (state.sortBy == s)
                      const Icon(Icons.check, size: 18, color: Colors.blue)
                    else
                      const SizedBox(width: 18),
                    const SizedBox(width: 8),
                    Text(s.label),
                  ],
                ),
              );
            }).toList(),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  state.sortBy.label,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const Icon(Icons.arrow_drop_down, size: 18),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 内容主体
  Widget _buildBody(WardrobeListState state, WardrobeListNotifier notifier) {
    // 加载中
    if (state.isLoading && state.allItems.isEmpty) {
      return Padding(padding: const EdgeInsets.all(12), child: ShimmerGrid());
    }

    // 错误
    if (state.errorMessage != null && state.allItems.isEmpty) {
      return ErrorView(
        message: state.errorMessage!,
        onRetry: () => notifier.loadItems(),
      );
    }

    // 空衣橱
    if (state.allItems.isEmpty) {
      return EmptyState(
        icon: Icons.checkroom_outlined,
        title: '你的衣橱还空空的，添加第一件衣服吧',
        subtitle: '拍照录入衣服，系统会自动分类整理',
        actionLabel: '拍照添加',
        onAction: () => context.push(AppRoutes.addItem),
      );
    }

    // 筛选结果为空
    if (state.filteredItems.isEmpty) {
      return EmptyState(
        icon: Icons.filter_list_off,
        title: '没有找到匹配的衣服',
        subtitle: '换个筛选条件或关键词试试',
      );
    }

    // 内容
    if (state.isGridView) {
      return _buildGridView(state.filteredItems);
    } else {
      return _buildListView(state.filteredItems);
    }
  }

  /// 网格视图
  Widget _buildGridView(List<ClothingItem> items) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 80),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 0.75,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return _ClothingGridCard(
          item: item,
          isSelectionMode: _isSelectionMode,
          isSelected: _selectedIds.contains(item.id),
          onTap: () => _onItemTap(item.id),
          onLongPress: () => _enterSelectionWith(item.id),
        );
      },
    );
  }

  /// 列表视图
  Widget _buildListView(List<ClothingItem> items) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 80),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return _ClothingListCard(
          item: item,
          isSelectionMode: _isSelectionMode,
          isSelected: _selectedIds.contains(item.id),
          onTap: () => _onItemTap(item.id),
          onLongPress: () => _enterSelectionWith(item.id),
        );
      },
    );
  }

  /// 点击衣物：多选模式下切换选中，否则进详情
  void _onItemTap(String itemId) {
    if (_isSelectionMode) {
      setState(() {
        if (!_selectedIds.remove(itemId)) {
          _selectedIds.add(itemId);
        }
      });
    } else {
      _goToDetail(itemId);
    }
  }

  /// 长按进入多选并选中该件
  void _enterSelectionWith(String itemId) {
    setState(() => _selectedIds.add(itemId));
  }

  /// 跳转详情页
  void _goToDetail(String itemId) {
    context.push('${AppRoutes.itemDetail}/$itemId');
  }

  // ---- 筛选 Chip 组件 ----

  Widget _buildFilterChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: GestureDetector(
        onTap: onTap,
        child: Chip(
          label: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: isSelected ? Colors.white : null,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
          backgroundColor: isSelected
              ? Theme.of(context).colorScheme.primary
              : context.subtleFillColor,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
        ),
      ),
    );
  }

  Widget _buildColorFilterChip({
    required String hex,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: GestureDetector(
        onTap: onTap,
        child: Chip(
          avatar: CircleAvatar(radius: 8, backgroundColor: _hexToColor(hex)),
          label: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
          backgroundColor: isSelected
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.15)
              : context.subtleFillColor,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
        ),
      ),
    );
  }

  Color _hexToColor(String hex) {
    hex = hex.replaceAll('#', '');
    if (hex.length == 6) hex = 'FF$hex';
    return Color(int.parse(hex, radix: 16));
  }
}

// ============================================================
//  网格卡片
// ============================================================
class _ClothingGridCard extends StatelessWidget {
  final ClothingItem item;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final bool isSelectionMode;
  final bool isSelected;

  const _ClothingGridCard({
    required this.item,
    required this.onTap,
    required this.onLongPress,
    this.isSelectionMode = false,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Card(
        clipBehavior: Clip.antiAlias,
        margin: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 图片（含状态角标 / 多选勾选 / 未选中遮罩）
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(6),
                    ),
                    child: ItemImage(
                      imageUrl: item.imageUrl,
                      fit: BoxFit.cover,
                      thumbnailWidth: 300,
                    ),
                  ),
                  // 非 clean 状态角标（左上角）
                  Positioned(
                    top: 4,
                    left: 4,
                    child: item.status != ClothingStatus.clean
                        ? ClothingStatusBadge(
                            status: item.status,
                            compact: true,
                          )
                        : const SizedBox.shrink(),
                  ),
                  // 多选遮罩 + 勾选
                  if (isSelectionMode)
                    Container(
                      color: isSelected
                          ? Colors.black.withValues(alpha: 0.35)
                          : Colors.black.withValues(alpha: 0.15),
                      child: Align(
                        alignment: Alignment.topRight,
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Icon(
                            isSelected
                                ? Icons.check_circle
                                : Icons.radio_button_unchecked,
                            color: isSelected ? Colors.white : Colors.white70,
                            size: 22,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // 信息条
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              color: isSelected
                  ? AppTheme.primaryColor.withValues(alpha: 0.12)
                  : Theme.of(context).colorScheme.surface,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.subCategory ?? item.category,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
//  列表卡片
// ============================================================
class _ClothingListCard extends StatelessWidget {
  final ClothingItem item;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final bool isSelectionMode;
  final bool isSelected;

  const _ClothingListCard({
    required this.item,
    required this.onTap,
    required this.onLongPress,
    this.isSelectionMode = false,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          color: isSelected ? Colors.blue.shade50 : null,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                // 多选勾选（多选模式左侧）
                if (isSelectionMode) ...[
                  Icon(
                    isSelected
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    color: isSelected ? Colors.blue : Colors.grey.shade400,
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                ],
                // 缩略图
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        width: 72,
                        height: 72,
                        child: ItemImage(
                          imageUrl: item.imageUrl,
                          fit: BoxFit.cover,
                          thumbnailWidth: 300,
                        ),
                      ),
                    ),
                    // 非 clean 状态角标（左下角）
                    if (item.status != ClothingStatus.clean)
                      Positioned(
                        left: 2,
                        bottom: 2,
                        child: ClothingStatusBadge(
                          status: item.status,
                          compact: true,
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 12),

                // 信息
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        style: theme.textTheme.titleMedium,
                        maxLines: 1,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        [
                          item.subCategory ?? item.category,
                          item.brand,
                        ].where((e) => e != null && e.isNotEmpty).join(' · '),
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 6),
                      // 颜色 + 风格标签
                      Row(
                        children: [
                          ...item.colors.take(3).map((c) {
                            return Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: Container(
                                width: 14,
                                height: 14,
                                decoration: BoxDecoration(
                                  color: _hexToColor(c.hex),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.grey.shade300,
                                  ),
                                ),
                              ),
                            );
                          }),
                          const SizedBox(width: 4),
                          if (item.styleTags.isNotEmpty)
                            Expanded(
                              child: Text(
                                item.styleTags.take(2).join(' · '),
                                style: theme.textTheme.labelSmall,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),

                // 价格 + 穿着次数
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (item.price != null)
                      Text(
                        '¥${item.price!.toStringAsFixed(0)}',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    const SizedBox(height: 4),
                    Text(
                      '穿${item.wearCount}次',
                      style: theme.textTheme.labelSmall,
                    ),
                  ],
                ),

                const SizedBox(width: 4),
                const Icon(Icons.chevron_right, size: 20, color: Colors.grey),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _hexToColor(String hex) {
    hex = hex.replaceAll('#', '');
    if (hex.length == 6) hex = 'FF$hex';
    return Color(int.parse(hex, radix: 16));
  }
}

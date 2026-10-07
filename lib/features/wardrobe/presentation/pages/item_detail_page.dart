import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../../core/error_log.dart';
import '../../../../../core/constants/routes.dart';
import '../../../../../core/theme/app_theme.dart';
import '../../../../../core/utils/date_utils.dart' as date_util;
import '../../../../../shared/widgets/empty_state.dart';
import '../../../../../shared/widgets/item_image.dart';
import '../../../../../shared/widgets/clothing_status_badge.dart';
import '../../../../../data/models/clothing_item.dart';
import '../../../../../data/models/wear_record.dart';
import '../../../calendar/presentation/providers/wear_calendar_provider.dart';
import '../providers/wardrobe_provider.dart';

/// 衣物详情页
///
/// 展示完整信息：大图、名称、分类、颜色、风格、品牌、价格等
/// 支持编辑和删除操作
/// 含穿着历史（从穿搭日历反查该衣物被穿过的日期）
class ItemDetailPage extends ConsumerStatefulWidget {
  final String itemId;

  const ItemDetailPage({super.key, required this.itemId});

  @override
  ConsumerState<ItemDetailPage> createState() => _ItemDetailPageState();
}

class _ItemDetailPageState extends ConsumerState<ItemDetailPage> {
  /// 防止「今天穿了」连点重复写入
  bool _recording = false;

  @override
  void initState() {
    super.initState();
    // 首次进入加载穿搭记录（穿着历史/统计用）
    Future.microtask(() {
      ref.read(wearCalendarProvider.notifier).load();
    });
  }

  /// 今天是否已经记录过这件衣服
  bool _isWornToday(WearCalendarState calendar, String itemId) {
    return calendar
        .recordsFor(DateTime.now())
        .any((r) => r.itemIds.contains(itemId));
  }

  /// 记录「今天穿了这件」
  ///
  /// 今天已有穿搭记录时**并进去**，避免一天堆出一堆单件记录。
  Future<void> _recordToday(ClothingItem item) async {
    if (_recording) return;

    final calendar = ref.read(wearCalendarProvider);
    final notifier = ref.read(wearCalendarProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);
    final today = DateTime.now();

    final todays = calendar.recordsFor(today);
    if (todays.any((r) => r.itemIds.contains(item.id))) {
      messenger.showSnackBar(SnackBar(content: Text('今天已经记录过「${item.name}」了')));
      return;
    }

    setState(() => _recording = true);
    try {
      final bool ok;
      if (todays.isNotEmpty) {
        // 并进今天已有的第一条记录
        final target = todays.first;
        ok = await notifier.updateRecord(
          target.copyWith(itemIds: [...target.itemIds, item.id]),
        );
      } else {
        ok = await notifier.addRecord(
          date: today,
          name: '日常穿搭',
          itemIds: [item.id],
        );
      }
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(ok ? '已记录：今天穿了「${item.name}」' : '记录失败，请检查网络后重试'),
        ),
      );
    } catch (e, s) {
      ErrorLog.record('记录穿搭', e, s);
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('记录失败，请检查网络后重试')));
    } finally {
      if (mounted) setState(() => _recording = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final itemId = widget.itemId;
    final wardrobeState = ref.watch(wardrobeListProvider);
    final calendarState = ref.watch(wearCalendarProvider);
    final item = wardrobeState.allItems
        .where((e) => e.id == itemId)
        .firstOrNull;

    // 找不到时（如被删除了）
    if (item == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(
          icon: Icons.checkroom_outlined,
          title: '衣物不存在或已被删除',
          subtitle: '它可能已被你移除',
        ),
      );
    }

    // 该衣物的穿着历史（按日期倒序）
    final history = calendarState.recordsForItem(item.id);

    return Scaffold(
      appBar: AppBar(
        title: Text(item.name),
        actions: [
          // 编辑按钮
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: '编辑',
            onPressed: () {
              context.push('${AppRoutes.editItem}/$itemId');
            },
          ),
          // 删除按钮
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: '删除',
            onPressed: () =>
                _confirmDelete(context, item, wardrobeState.allItems),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 大图
            SizedBox(
              height: 320,
              child: ItemImage(imageUrl: item.imageUrl, fit: BoxFit.contain),
            ),

            // 今日穿着快捷记录（此前只能绕到日历页手动勾选）
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: SizedBox(
                width: double.infinity,
                child: _isWornToday(calendarState, item.id)
                    ? OutlinedButton.icon(
                        onPressed: null,
                        icon: const Icon(Icons.check_circle_outline, size: 18),
                        label: const Text('今天已穿过'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      )
                    : FilledButton.icon(
                        onPressed: _recording ? null : () => _recordToday(item),
                        icon: const Icon(Icons.event_available, size: 18),
                        label: const Text('今天穿了这件'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
              ),
            ),

            // 信息区
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 标题行
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.name,
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                      ),
                      // 状态标签
                      ClothingStatusBadge(status: item.status),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // 分类
                  _buildInfoRow(
                    context,
                    icon: Icons.category_outlined,
                    label: '分类',
                    value: [
                      item.category,
                      item.subCategory,
                    ].where((e) => e != null && e.isNotEmpty).join(' / '),
                  ),
                  const SizedBox(height: 12),

                  // 颜色
                  if (item.colors.isNotEmpty) _buildColorRow(context, item),
                  const SizedBox(height: 12),

                  // 风格
                  if (item.styleTags.isNotEmpty)
                    _buildTagsRow(
                      context,
                      icon: Icons.style_outlined,
                      label: '风格',
                      tags: item.styleTags,
                    ),
                  const SizedBox(height: 12),

                  // 季节
                  if (item.seasonTags.isNotEmpty)
                    _buildTagsRow(
                      context,
                      icon: Icons.wb_sunny_outlined,
                      label: '适合季节',
                      tags: item.seasonTags,
                    ),
                  const SizedBox(height: 12),

                  // 品牌
                  if (item.brand != null && item.brand!.isNotEmpty)
                    _buildInfoRow(
                      context,
                      icon: Icons.store_outlined,
                      label: '品牌',
                      value: item.brand!,
                    ),
                  const SizedBox(height: 12),

                  // 价格
                  if (item.price != null)
                    _buildInfoRow(
                      context,
                      icon: Icons.monetization_on_outlined,
                      label: '价格',
                      value: '¥${item.price!.toStringAsFixed(2)}',
                    ),
                  const SizedBox(height: 20),

                  const Divider(),
                  const SizedBox(height: 16),

                  // 穿着统计
                  Row(
                    children: [
                      _buildStatCard(
                        context,
                        icon: Icons.repeat,
                        label: '穿着次数',
                        value: '${item.wearCount}',
                      ),
                      const SizedBox(width: 12),
                      _buildStatCard(
                        context,
                        icon: Icons.calculate_outlined,
                        label: '性价比',
                        value: item.costPerWear != null
                            ? '¥${item.costPerWear!.toStringAsFixed(1)}/次'
                            : '暂无',
                      ),
                      const SizedBox(width: 12),
                      _buildStatCard(
                        context,
                        icon: Icons.calendar_today,
                        label: '上次穿着',
                        value: item.lastWornDate != null
                            ? date_util.DateUtils.formatDateChinese(
                                item.lastWornDate!,
                              )
                            : '从未',
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // 穿着历史
                  _buildWearHistory(context, history, wardrobeState.allItems),
                  const SizedBox(height: 16),

                  // 添加日期
                  Text(
                    '添加于 ${date_util.DateUtils.formatDate(item.createdAt)}',
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

  /// 穿着历史时间线
  Widget _buildWearHistory(
    BuildContext context,
    List<WearRecord> history,
    List<ClothingItem> allItems,
  ) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '穿着历史',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '共 ${history.length} 次',
              style: theme.textTheme.labelSmall?.copyWith(color: Colors.grey),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (history.isEmpty)
          Text(
            '还没有穿过这件衣服的记录',
            style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
          )
        else
          ...history.map((r) => _buildHistoryRow(context, r, allItems)),
      ],
    );
  }

  /// 单条穿着历史行
  Widget _buildHistoryRow(
    BuildContext context,
    WearRecord record,
    List<ClothingItem> allItems,
  ) {
    final theme = Theme.of(context);
    // 当天其他单品缩略图（排除当前这件）
    final others = record.itemIds
        .where((id) => id != widget.itemId)
        .map((id) => allItems.where((e) => e.id == id).firstOrNull)
        .whereType<ClothingItem>()
        .toList();

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          // 日期
          SizedBox(
            width: 84,
            child: Text(
              date_util.DateUtils.formatDateChinese(record.wearDate),
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          // 穿搭名
          if (record.name != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                record.name!,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppTheme.primaryColor,
                ),
              ),
            ),
          const Spacer(),
          // 其他单品缩略图
          SizedBox(
            height: 32,
            child: Row(
              children: others.take(3).map((item) {
                return Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: SizedBox(
                      width: 32,
                      height: 32,
                      child: ItemImage(
                        imageUrl: item.imageUrl,
                        fit: BoxFit.cover,
                        thumbnailWidth: 300,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  /// 确认删除弹窗
  void _confirmDelete(
    BuildContext context,
    ClothingItem item,
    List<ClothingItem> allItems,
  ) {
    final notifier = ref.read(wardrobeListProvider.notifier);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除「${item.name}」吗？\n删除后无法恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              try {
                final ok = await notifier.deleteItem(item.id);
                if (!context.mounted) return;
                if (ok) {
                  Navigator.of(context).pop(); // 返回衣橱页
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('已删除「${item.name}」')));
                }
              } catch (e, s) {
                // 删除失败：停留在详情页，给出可重试的提示；细节记日志
                ErrorLog.record('删除衣物', e, s);
                if (!context.mounted) return;
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('删除失败，请检查网络后重试')));
              }
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.grey),
        const SizedBox(width: 8),
        Text(
          '$label：',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: Colors.grey),
        ),
        Text(value, style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }

  Widget _buildTagsRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required List<String> tags,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: Colors.grey),
        const SizedBox(width: 8),
        Text(
          '$label：',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: Colors.grey),
        ),
        Expanded(
          child: Wrap(
            spacing: 6,
            runSpacing: 4,
            children: tags.map((tag) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  tag,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildColorRow(BuildContext context, ClothingItem item) {
    return Row(
      children: [
        const Icon(Icons.palette_outlined, size: 20, color: Colors.grey),
        const SizedBox(width: 8),
        Text(
          '颜色：',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: Colors.grey),
        ),
        ...item.colors.map((c) {
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: _hexToColor(c.hex),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                ),
                const SizedBox(width: 4),
                Text(c.name, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildStatCard(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: context.subtleFillColor,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Icon(icon, size: 20, color: AppTheme.primaryColor),
            const SizedBox(height: 6),
            Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 2),
            Text(label, style: Theme.of(context).textTheme.labelSmall),
          ],
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

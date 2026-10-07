import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/theme/app_theme.dart';
import '../../../../../shared/widgets/item_image.dart';
import '../../../../../shared/widgets/offline_banner.dart';
import '../../../../../data/models/clothing_item.dart';
import '../../../../../data/models/wear_record.dart';
import '../../../wardrobe/presentation/providers/wardrobe_provider.dart';
import '../providers/wear_calendar_provider.dart';

/// 穿搭日历页面
///
/// 月历视图，点击某天可以查看/新增当天穿搭。
/// 一天可以记录多套穿搭（如"白天"、"晚上"）。
class WearCalendarPage extends ConsumerStatefulWidget {
  const WearCalendarPage({super.key});

  @override
  ConsumerState<WearCalendarPage> createState() => _WearCalendarPageState();
}

class _WearCalendarPageState extends ConsumerState<WearCalendarPage> {
  late DateTime _currentMonth;
  DateTime? _selectedDay;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _currentMonth = DateTime(now.year, now.month);
    _selectedDay = now;
    Future.microtask(() {
      ref.read(wearCalendarProvider.notifier).load();
      ref.read(wardrobeListProvider.notifier).loadItems();
    });
  }

  @override
  Widget build(BuildContext context) {
    final calendarState = ref.watch(wearCalendarProvider);
    final wardrobeState = ref.watch(wardrobeListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('穿搭日历'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
            onPressed: () {
              ref.read(wearCalendarProvider.notifier).load();
              ref.read(wardrobeListProvider.notifier).loadItems();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // 离线提示：日历数据来自本地缓存时明确告知，
          // 否则用户看到断网后的日历会以为记录丢了
          if (calendarState.isOffline && calendarState.records.isNotEmpty)
            OfflineBanner(
              onRetry: () => ref.read(wearCalendarProvider.notifier).load(),
            ),
          // 月份切换栏
          _buildMonthBar(),
          // 星期表头
          _buildWeekdayHeader(),
          // 月历网格
          _buildCalendarGrid(calendarState),
          // 分隔线
          const Divider(height: 1),
          // 选中日期的穿搭详情
          Expanded(child: _buildDayDetail(calendarState, wardrobeState)),
        ],
      ),
    );
  }

  /// 月份切换栏
  Widget _buildMonthBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: () {
              setState(() {
                _currentMonth = DateTime(
                  _currentMonth.year,
                  _currentMonth.month - 1,
                );
              });
            },
          ),
          Expanded(
            child: Text(
              '${_currentMonth.year}年 ${_currentMonth.month}月',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: () {
              setState(() {
                _currentMonth = DateTime(
                  _currentMonth.year,
                  _currentMonth.month + 1,
                );
              });
            },
          ),
        ],
      ),
    );
  }

  /// 星期表头
  Widget _buildWeekdayHeader() {
    const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: weekdays.map((d) {
          return Expanded(
            child: Center(
              child: Text(
                d,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  /// 月历网格
  Widget _buildCalendarGrid(WearCalendarState state) {
    final firstDay = DateTime(_currentMonth.year, _currentMonth.month, 1);
    // 周一为一周开始
    final leadingBlanks = firstDay.weekday - 1;
    final daysInMonth = DateTime(
      _currentMonth.year,
      _currentMonth.month + 1,
      0,
    ).day;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: GridView.count(
        crossAxisCount: 7,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        childAspectRatio: 1.1,
        children: [
          for (var i = 0; i < leadingBlanks; i++) const SizedBox.shrink(),
          for (var day = 1; day <= daysInMonth; day++) ...[
            _buildDayCell(day, state),
          ],
        ],
      ),
    );
  }

  /// 单个日期格
  Widget _buildDayCell(int day, WearCalendarState state) {
    final date = DateTime(_currentMonth.year, _currentMonth.month, day);
    final isToday = _isSameDay(date, DateTime.now());
    final isSelected = _selectedDay != null && _isSameDay(date, _selectedDay!);
    final hasRecord = state.hasRecord(date);

    return GestureDetector(
      onTap: () => setState(() => _selectedDay = date),
      child: Container(
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryColor : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 日期数字
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isToday && !isSelected
                    ? AppTheme.primaryColor.withValues(alpha: 0.15)
                    : Colors.transparent,
              ),
              alignment: Alignment.center,
              child: Text(
                '$day',
                style: TextStyle(
                  fontSize: 13,
                  color: isSelected
                      ? Colors.white
                      : isToday
                      ? AppTheme.primaryColor
                      : Colors.grey.shade800,
                  fontWeight: isToday ? FontWeight.w700 : FontWeight.normal,
                ),
              ),
            ),
            // 记录标记点（有记录就显示，多条也显示一个点）
            SizedBox(
              height: 6,
              child: hasRecord
                  ? Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isSelected
                            ? Colors.white
                            : AppTheme.primaryColor,
                      ),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  /// 选中日期详情区
  Widget _buildDayDetail(
    WearCalendarState calendarState,
    WardrobeListState wardrobeState,
  ) {
    if (_selectedDay == null) return const SizedBox.shrink();

    final selected = _selectedDay!;
    final isToday = _isSameDay(selected, DateTime.now());
    final dateLabel = '${selected.month}月${selected.day}日';
    final dayRecords = calendarState.recordsFor(selected);
    // 离线且完全没有缓存时，"这一天是空的"是网络原因，不是真的没记录
    final noDataOffline =
        calendarState.isOffline && calendarState.records.isEmpty;

    return Column(
      children: [
        // 日期标题行
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Text(
                dateLabel,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 8),
              if (isToday)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '今天',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppTheme.primaryColor,
                    ),
                  ),
                ),
              const Spacer(),
              Text(
                '${dayRecords.length} 套穿搭',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),

        // 穿搭列表
        Expanded(
          child: dayRecords.isEmpty
              ? _buildEmptyDay(noDataOffline)
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: dayRecords.length,
                  itemBuilder: (_, i) => _WearRecordCard(
                    record: dayRecords[i],
                    items: dayRecords[i].itemIds
                        .map(
                          (id) => wardrobeState.allItems
                              .where((it) => it.id == id)
                              .firstOrNull,
                        )
                        .whereType<ClothingItem>()
                        .toList(),
                    onEdit: () => _showPickItemsDialog(selected, dayRecords[i]),
                    onDelete: () => _confirmDelete(dayRecords[i]),
                  ),
                ),
        ),

        // 底部新增按钮
        Padding(
          padding: const EdgeInsets.all(12),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => _showPickItemsDialog(selected, null),
              icon: const Icon(Icons.add),
              label: Text(dayRecords.isEmpty ? '记录今天的穿搭' : '再加一套穿搭'),
            ),
          ),
        ),
      ],
    );
  }

  /// 空日期提示
  ///
  /// [offlineNoCache] 为 true 时是断网且没有本地缓存，不能显示
  /// 「这一天还没有穿搭记录」——那会让用户以为记录丢了。
  Widget _buildEmptyDay(bool offlineNoCache) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            offlineNoCache
                ? Icons.cloud_off_outlined
                : Icons.calendar_today_outlined,
            size: 40,
            color: Colors.grey.shade300,
          ),
          const SizedBox(height: 8),
          Text(
            offlineNoCache ? '当前无网络，暂时看不到穿搭记录' : '这一天还没有穿搭记录',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: context.textSecondaryColor),
          ),
        ],
      ),
    );
  }

  /// 弹出选衣对话框（新增或编辑一条穿搭）
  void _showPickItemsDialog(DateTime date, WearRecord? existing) {
    final allItems = ref.read(wardrobeListProvider).allItems;

    // 预选状态
    final selectedIds = <String>{...?existing?.itemIds};
    final nameController = TextEditingController(text: existing?.name ?? '');

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setState) {
            return AlertDialog(
              title: Text(existing == null ? '记录穿搭' : '修改穿搭'),
              content: SizedBox(
                width: double.maxFinite,
                height: 420,
                child: Column(
                  children: [
                    // 穿搭名称
                    TextField(
                      controller: nameController,
                      decoration: InputDecoration(
                        hintText: '穿搭名称（如：白天、晚上、约会，可空）',
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '选择当天穿的衣服（可多选）',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: GridView.builder(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              crossAxisSpacing: 8,
                              mainAxisSpacing: 8,
                              childAspectRatio: 0.8,
                            ),
                        itemCount: allItems.length,
                        itemBuilder: (_, i) {
                          final item = allItems[i];
                          final selected = selectedIds.contains(item.id);
                          return GestureDetector(
                            onTap: () => setState(() {
                              selected
                                  ? selectedIds.remove(item.id)
                                  : selectedIds.add(item.id);
                            }),
                            child: Column(
                              children: [
                                Expanded(
                                  child: Container(
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: selected
                                            ? AppTheme.primaryColor
                                            : Colors.grey.shade300,
                                        width: selected ? 2 : 1,
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(7),
                                      child: ItemImage(
                                        imageUrl: item.imageUrl,
                                        fit: BoxFit.cover,
                                        thumbnailWidth: 300,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  item.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.labelSmall,
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('取消'),
                ),
                ElevatedButton(
                  onPressed: selectedIds.isEmpty
                      ? null
                      : () async {
                          final name = nameController.text.trim().isEmpty
                              ? null
                              : nameController.text.trim();
                          // await 前先取出 messenger，await 之后 context 可能已失效
                          final messenger = ScaffoldMessenger.of(context);
                          final notifier = ref.read(
                            wearCalendarProvider.notifier,
                          );

                          // 必须 await 并检查返回值：断网时若直接 pop，
                          // 用户会以为记上了，其实日历里什么都没有（数据丢失错觉）。
                          final bool ok;
                          if (existing == null) {
                            ok = await notifier.addRecord(
                              date: date,
                              name: name,
                              itemIds: selectedIds.toList(),
                            );
                          } else {
                            ok = await notifier.updateRecord(
                              existing.copyWith(
                                name: name,
                                itemIds: selectedIds.toList(),
                              ),
                            );
                          }

                          if (!mounted) return;

                          if (ok) {
                            Navigator.of(ctx).pop();
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(
                                  existing == null ? '已记录今天的穿搭' : '已保存',
                                ),
                              ),
                            );
                          } else {
                            // 失败不关闭弹窗，让用户能直接重试
                            messenger.showSnackBar(
                              const SnackBar(content: Text('保存失败，请检查网络后重试')),
                            );
                          }
                        },
                  child: const Text('保存'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// 确认删除
  Future<void> _confirmDelete(WearRecord record) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除这套穿搭？'),
        content: Text(
          '将删除 ${record.name ?? record.wearDate.month}月${record.wearDate.day}日 的穿搭记录',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final messenger = ScaffoldMessenger.of(context);
    final ok = await ref
        .read(wearCalendarProvider.notifier)
        .deleteRecord(record.id);
    if (!mounted) return;

    messenger.showSnackBar(
      SnackBar(content: Text(ok ? '已删除' : '删除失败，请检查网络后重试')),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}

/// 单条穿搭记录卡片
class _WearRecordCard extends StatelessWidget {
  final WearRecord record;
  final List<ClothingItem> items;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _WearRecordCard({
    required this.record,
    required this.items,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (record.name != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      record.name!,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.primaryColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Text(
                  '${items.length} 件',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  onPressed: onEdit,
                  tooltip: '修改',
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  onPressed: onDelete,
                  tooltip: '删除',
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 8),
            // 衣服缩略图
            SizedBox(
              height: 70,
              child: items.isEmpty
                  ? Center(
                      child: Text(
                        '穿搭里的衣服已删除',
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: Colors.grey),
                      ),
                    )
                  : Row(
                      children: items.take(5).map((item) {
                        return Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(6),
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
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/theme/app_theme.dart';
import '../../../../../data/models/clothing_item.dart';
import '../../../../../shared/widgets/item_image.dart';
import '../../../calendar/presentation/providers/wear_calendar_provider.dart';
import '../../../wardrobe/presentation/providers/wardrobe_provider.dart';

/// 统计分析页面
///
/// - 本月报告（穿搭天数 / 记录套数 / 最常穿单品 Top3）
/// - 穿着频次排行
/// - 性价比分析
/// - 最常穿 / 久未穿
/// - 分类分布
class StatsPage extends ConsumerStatefulWidget {
  const StatsPage({super.key});

  @override
  ConsumerState<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends ConsumerState<StatsPage> {
  @override
  void initState() {
    super.initState();
    // 本月报告依赖穿搭记录，进入页面主动加载
    Future.microtask(() {
      ref.read(wearCalendarProvider.notifier).load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(wardrobeListProvider).allItems;
    final calendar = ref.watch(wearCalendarProvider);
    final records = calendar.records;

    // 早退条件：衣服和穿搭记录都为空才显示空态
    // （衣服可能删光但穿搭记录还在，此时仍应显示本月报告）
    if (items.isEmpty && records.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('穿着统计')),
        body: Center(
          child: Text(
            '还没有数据，先录入衣服或记录穿搭吧',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('穿着统计')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 本月报告
          _buildMonthlyReport(context, calendar, items),
          const SizedBox(height: 20),

          _buildSectionTitle(context, '👑 穿着最多'),
          ..._topWorn(items).map((i) => _rankRow(context, i, 'worn')),

          const SizedBox(height: 20),
          _buildSectionTitle(context, '💸 性价比最低'),
          ..._worstCpw(items).map((i) => _rankRow(context, i, 'cpw')),

          const SizedBox(height: 20),
          _buildSectionTitle(context, '⏰ 久未穿着'),
          ..._longNotWorn(items).map((i) => _rankRow(context, i, 'notworn')),

          const SizedBox(height: 20),
          _buildSectionTitle(context, '📊 分类分布'),
          _buildCategoryChart(context, items),
        ],
      ),
    );
  }

  /// 本月报告卡片
  Widget _buildMonthlyReport(
    BuildContext context,
    WearCalendarState calendar,
    List<ClothingItem> items,
  ) {
    final theme = Theme.of(context);
    final days = calendar.wearDaysThisMonth;
    final outfits = calendar.outfitsThisMonth;
    final top = calendar.mostWornItemsThisMonth(limit: 3);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题
            Row(
              children: [
                Icon(Icons.assessment, color: AppTheme.primaryColor, size: 20),
                const SizedBox(width: 8),
                Text(
                  '本月报告',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Text(
                  '${DateTime.now().year} 年 ${DateTime.now().month} 月',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // 三列统计
            Row(
              children: [
                _buildMonthlyStat(
                  context,
                  icon: Icons.calendar_today,
                  value: '$days',
                  label: '穿搭天数',
                ),
                const SizedBox(width: 12),
                _buildMonthlyStat(
                  context,
                  icon: Icons.style,
                  value: '$outfits',
                  label: '记录套数',
                ),
                const SizedBox(width: 12),
                _buildMonthlyStat(
                  context,
                  icon: Icons.checkroom,
                  value: top.isEmpty ? '—' : '${top.first.value}',
                  label: '最常穿次数',
                ),
              ],
            ),
            const SizedBox(height: 14),

            // 最常穿 Top3
            if (top.isNotEmpty) ...[
              Text(
                '这个月最常穿',
                style: theme.textTheme.labelSmall?.copyWith(color: Colors.grey),
              ),
              const SizedBox(height: 8),
              ...top.asMap().entries.map((e) {
                final idx = e.key;
                final id = e.value.key;
                final count = e.value.value;
                final item = items.where((i) => i.id == id).firstOrNull;
                return _buildTopItemRow(context, idx, item, count);
              }),
            ] else
              Text(
                '这个月还没有穿过衣服',
                style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
              ),
          ],
        ),
      ),
    );
  }

  /// 单列统计
  Widget _buildMonthlyStat(
    BuildContext context, {
    required IconData icon,
    required String value,
    required String label,
  }) {
    final theme = Theme.of(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Icon(icon, size: 20, color: AppTheme.primaryColor),
            const SizedBox(height: 6),
            Text(
              value,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 2),
            Text(label, style: theme.textTheme.labelSmall),
          ],
        ),
      ),
    );
  }

  /// 最常穿单品行（衣物被删时兜底显示"已删除衣物"）
  Widget _buildTopItemRow(
    BuildContext context,
    int index,
    ClothingItem? item,
    int count,
  ) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          // 排名
          SizedBox(
            width: 24,
            child: Text(
              '${index + 1}',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall?.copyWith(
                color: index == 0 ? const Color(0xFFFFB300) : Colors.grey,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          // 缩略图
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              width: 36,
              height: 36,
              child: item != null
                  ? ItemImage(imageUrl: item.imageUrl, fit: BoxFit.cover)
                  : Container(
                      color: Colors.grey.shade200,
                      child: const Icon(
                        Icons.close,
                        size: 18,
                        color: Colors.grey,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 10),
          // 名称
          Expanded(
            child: Text(
              item?.name ?? '已删除衣物',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: item != null ? null : Colors.grey,
              ),
            ),
          ),
          Text(
            '穿 $count 次',
            style: theme.textTheme.labelMedium?.copyWith(
              color: AppTheme.primaryColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
      ),
    );
  }

  /// Top 5 穿着最多
  List<ClothingItem> _topWorn(List<ClothingItem> items) {
    final sorted = List<ClothingItem>.from(items)
      ..sort((a, b) => b.wearCount.compareTo(a.wearCount));
    return sorted.take(5).where((i) => i.wearCount > 0).toList();
  }

  /// Top 5 最贵但穿得少
  List<ClothingItem> _worstCpw(List<ClothingItem> items) {
    final withPrice = items.where((i) => i.price != null && i.price! > 0);
    final sorted = List<ClothingItem>.from(withPrice)
      ..sort((a, b) {
        final cpwA = a.wearCount > 0 ? a.price! / a.wearCount : a.price! * 100;
        final cpwB = b.wearCount > 0 ? b.price! / b.wearCount : b.price! * 100;
        return cpwB.compareTo(cpwA);
      });
    return sorted.take(5).toList();
  }

  /// 最近 60 天没穿过的
  List<ClothingItem> _longNotWorn(List<ClothingItem> items) {
    final sorted = List<ClothingItem>.from(items)
      ..sort((a, b) {
        final da = a.lastWornDate ?? DateTime(2000);
        final db = b.lastWornDate ?? DateTime(2000);
        return da.compareTo(db);
      });
    return sorted.take(5).toList();
  }

  Widget _rankRow(BuildContext context, ClothingItem item, String type) {
    String stat;
    Color statColor;
    switch (type) {
      case 'worn':
        stat = '穿 ${item.wearCount} 次';
        statColor = AppTheme.primaryColor;
        break;
      case 'cpw':
        final cpw = item.costPerWear;
        stat = cpw != null ? '¥${cpw.toStringAsFixed(0)}/次' : '未穿';
        statColor = Colors.red;
        break;
      case 'notworn':
        final days = item.lastWornDate != null
            ? DateTime.now().difference(item.lastWornDate!).inDays
            : 999;
        stat = item.lastWornDate != null ? '$days天未穿' : '从未穿';
        statColor = Colors.orange;
        break;
      default:
        stat = '';
        statColor = Colors.grey;
    }

    return ListTile(
      dense: true,
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: statColor.withValues(alpha: 0.1),
        child: Text(
          '${item.wearCount}',
          style: TextStyle(fontSize: 11, color: statColor),
        ),
      ),
      title: Text(item.name, style: Theme.of(context).textTheme.bodyMedium),
      subtitle: Text(
        item.subCategory ?? item.category,
        style: Theme.of(context).textTheme.labelSmall,
      ),
      trailing: Text(
        stat,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 13,
          color: statColor,
        ),
      ),
    );
  }

  Widget _buildCategoryChart(BuildContext context, List<ClothingItem> items) {
    final counts = <String, int>{};
    for (final item in items) {
      counts[item.category] = (counts[item.category] ?? 0) + 1;
    }
    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // 简单柱状图（V2 手工画，后续可换 fl_chart）
    final maxCount = entries.isNotEmpty ? entries.first.value : 1;

    return Column(
      children: entries.map((e) {
        final ratio = e.value / maxCount;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              SizedBox(
                width: 48,
                child: Text(
                  e.key,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              Expanded(
                child: Stack(
                  children: [
                    Container(
                      height: 20,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    FractionallySizedBox(
                      widthFactor: ratio,
                      child: Container(
                        height: 20,
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 24,
                child: Text(
                  '${e.value}',
                  textAlign: TextAlign.right,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

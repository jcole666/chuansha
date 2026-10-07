import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../../core/constants/routes.dart';
import '../../../../../core/constants/app_constants.dart';
import '../../../../../core/theme/app_theme.dart';
import '../../../../../core/utils/date_utils.dart' as date_util;
import '../../../../../data/models/clothing_item.dart';
import '../../../../../data/models/weather_data.dart';
import '../../../../../domain/enums/clothing_status.dart';
import '../../../../../shared/widgets/empty_state.dart';
import '../../../../../shared/widgets/shimmer_card.dart';
import '../../../../../shared/widgets/error_view.dart';
import '../../../../../shared/widgets/item_image.dart';
import '../../../../../services/recommendation_service.dart';
import '../../../../features/wardrobe/presentation/providers/wardrobe_provider.dart';
import '../../../calendar/presentation/providers/wear_calendar_provider.dart';
import '../providers/recommend_provider.dart';

/// 推荐页面
///
/// 功能：天气卡片 + 推荐搭配列表 Top3 + 换一批 + 👍/👎 + "今天穿这套"
/// 现在作为搭配页的一个 Tab 使用（showAppBar=false 时不显示自己的标题栏）
class RecommendPage extends ConsumerStatefulWidget {
  /// 是否显示自己的 AppBar（作为 Tab 嵌入时传 false）
  final bool showAppBar;

  const RecommendPage({super.key, this.showAppBar = true});

  @override
  ConsumerState<RecommendPage> createState() => _RecommendPageState();
}

class _RecommendPageState extends ConsumerState<RecommendPage> {
  /// 防止"今天穿这套"半秒内连点重复写入
  final Set<String> _recordingKeys = {};

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(recommendProvider.notifier).load();
      // 提前加载穿搭记录，用于判断"今天已穿"按钮状态
      ref.read(wearCalendarProvider.notifier).load();
      // 加载衣橱：冷启动判断依赖 wardrobeState.allItems，
      // 若只依赖其它 Tab 触发，直接从「搭配」Tab 进入时会把有衣服的用户
      // 误判成「还没录入」。
      ref.read(wardrobeListProvider.notifier).loadItems();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(recommendProvider);
    final notifier = ref.read(recommendProvider.notifier);
    final wardrobeState = ref.watch(wardrobeListProvider);
    final calendarState = ref.watch(wearCalendarProvider);

    return Scaffold(
      appBar: widget.showAppBar ? AppBar(title: const Text('今日推荐')) : null,
      body: RefreshIndicator(
        onRefresh: () => notifier.load(),
        child: _buildBody(state, notifier, wardrobeState, calendarState),
      ),
    );
  }

  Widget _buildBody(
    RecommendState state,
    RecommendNotifier notifier,
    WardrobeListState wardrobeState,
    WearCalendarState calendarState,
  ) {
    // 衣物不足（冷启动）—— 必须排在天气判断之前。
    // 否则一旦天气服务不可用（如打包漏了 OWM_API_KEY），ErrorView 会盖掉
    // 「录入 5 件解锁推荐」的新手引导，新用户完全不知道该干嘛。
    // 加 isLoading 守卫：衣橱还没加载完时不要误判成「没衣服」。
    if (!wardrobeState.isLoading &&
        wardrobeState.allItems.length <
            AppConstants.minItemsForRecommendation) {
      return _buildColdStart(wardrobeState.allItems.length);
    }

    // 加载中
    if (state.isLoadingWeather && state.weather == null) {
      return _buildLoadingState();
    }

    // 天气不可用（面向用户的文案；缺 OWM_API_KEY 等技术细节记在 ErrorLog）
    if (state.weatherError != null && state.weather == null) {
      return ErrorView(
        message: state.weatherError!,
        onRetry: () => notifier.load(),
      );
    }

    // 主内容
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
      children: [
        // 天气卡片
        if (state.weather != null) _buildWeatherCard(state.weather!),

        const SizedBox(height: 16),

        // 推荐标题
        Row(
          children: [
            Text('今日推荐', style: Theme.of(context).textTheme.titleLarge),
            const Spacer(),
            // 换一批
            TextButton.icon(
              onPressed: state.isLoadingRecommendations
                  ? null
                  : () => notifier.refresh(),
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('换一批'),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // 推荐列表
        if (state.isLoadingRecommendations)
          ...List.generate(
            3,
            (_) => const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: ShimmerCard(height: 180),
            ),
          )
        else if (state.recommendError != null)
          // 生成推荐失败（弱网 / 服务端报错）：给出明确错误 + 重试入口，
          // 而不是让骨架屏无限转下去。
          SizedBox(
            height: 320,
            child: ErrorView(
              message: state.recommendError!,
              onRetry: () => notifier.load(),
            ),
          )
        else if (state.recommendations.isEmpty)
          // 衣物数量够了却生成不出推荐：明确告诉用户缺哪一类，
          // 而不是一句「无法生成推荐」把人晾在那儿。
          _buildNoRecommendation(state.weather, wardrobeState.allItems)
        else
          ...state.recommendations.asMap().entries.map((entry) {
            final idx = entry.key;
            final rec = entry.value;
            final alreadyFeedback = notifier.hasFeedback(rec);

            return _buildRecommendationCard(
              rec,
              idx,
              alreadyFeedback,
              notifier,
              calendarState,
            );
          }),
      ],
    );
  }

  /// 加载骨架
  Widget _buildLoadingState() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const ShimmerCard(height: 120),
        const SizedBox(height: 20),
        Text('今日推荐', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        ...List.generate(
          3,
          (_) => const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: ShimmerCard(height: 180),
          ),
        ),
      ],
    );
  }

  /// 冷启动状态：衣服不够，显示进度
  Widget _buildColdStart(int currentCount) {
    final target = AppConstants.minItemsForRecommendation;
    final progress = currentCount / target;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.auto_awesome_outlined,
              size: 72,
              color: AppTheme.primaryColor.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 20),
            Text(
              '录入至少 $target 件衣服就能看到推荐了！',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              '系统会根据天气和你的衣橱智能搭配',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 24),

            // 进度条
            SizedBox(
              width: 220,
              child: Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 8,
                      backgroundColor: context.subtleFillColor,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        progress >= 1.0 ? Colors.green : AppTheme.primaryColor,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '已录入 $currentCount / $target',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.primaryColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            ElevatedButton.icon(
              onPressed: () {
                // 切换到衣橱 Tab，触发录入
                context.push(AppRoutes.addItem);
              },
              icon: const Icon(Icons.add_a_photo),
              label: const Text('去录入'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 衣物够了但生成不出推荐时的空态
  ///
  /// 之前只有一句「暂时无法生成推荐」——用户录了 5 件全是上衣也不知道下一步干嘛。
  /// 这里按 recommendation_service 的组合规则反推缺什么，给出具体引导 + 入口。
  Widget _buildNoRecommendation(
    WeatherData? weather,
    List<ClothingItem> items,
  ) {
    // 天气还没到（首帧）：不要瞎猜缺什么，给通用但不空洞的引导
    if (weather == null) {
      return EmptyState(
        icon: Icons.inventory_outlined,
        title: '暂时无法生成推荐',
        subtitle: '天气数据还没到，或衣橱里能搭配的品类还不够\n去衣橱再添几件不同品类的衣服试试',
        actionLabel: '去衣橱添加',
        onAction: () => context.push(AppRoutes.addItem),
      );
    }

    return EmptyState(
      icon: Icons.checkroom_outlined,
      title: '暂时还凑不出一套',
      subtitle: _diagnoseMissing(weather, items),
      actionLabel: '去衣橱添加',
      onAction: () => context.push(AppRoutes.addItem),
    );
  }

  /// 诊断「到底缺哪一类」
  ///
  /// 镜像 recommendation_service 的规则：
  /// - 阶段一会剔除「非已洗好」的衣物，以及套装 / 内衣 / 配饰类；
  /// - 组合模式 A：连衣裙 + 鞋；组合模式 B：上衣 + 下装 + 鞋（外套可选）。
  /// 所以真正会卡住的是「上身（上衣或连衣裙）」「下装」「鞋」三类。
  String _diagnoseMissing(WeatherData weather, List<ClothingItem> items) {
    final temp = weather.temperature;
    final tempText = '${temp.toInt()}℃';

    final clean = items.where((i) => i.status == ClothingStatus.clean).toList();
    if (items.isNotEmpty && clean.isEmpty) {
      return '衣橱里的衣服都不在「已洗好」状态，把常用的几件标记回已洗好就会出推荐了';
    }

    final usable = clean.where((i) => !_excludedCategories.contains(i.category));
    if (usable.isEmpty) {
      return '衣橱里还没有能参与搭配的上衣 / 下装 / 鞋'
          '（套装、内衣、配饰不参与推荐），先录几件基础款试试';
    }

    final tops = usable.where(
      (i) => i.category == '上衣' && _isTopSuitable(i.subCategory ?? '', temp),
    );
    final bottoms = usable.where(
      (i) => i.category == '下装' && _isBottomSuitable(i.subCategory ?? '', temp),
    );
    final shoes = usable.where(
      (i) =>
          i.category == '鞋' && _isShoesSuitable(i.subCategory ?? '', temp, weather),
    );
    final dresses = usable.where(
      (i) => i.category == '连衣裙' && _isDressSuitable(temp),
    );
    final outerwear = usable.where(
      (i) =>
          i.category == '外套' && _isOuterwearSuitable(i.subCategory ?? '', temp),
    );

    // 不区分温度时的件数，用来区分「压根没有」和「有但不适合这个温度」
    int rawCount(String category) =>
        usable.where((i) => i.category == category).length;

    // 鞋：两种组合模式都必须要
    if (shoes.isEmpty) {
      final raw = rawCount('鞋');
      if (raw == 0) return '还缺一双鞋，再录入 1 双就能生成推荐了';
      if (weather.isRainy || weather.isSnowy) {
        return '今天有雨雪，衣橱里的 $raw 双鞋都不合适，需要一双靴子或运动鞋';
      }
      return '衣橱里的 $raw 双鞋在 $tempText 下都不太合适，换季款再录入 1 双就能生成推荐了';
    }

    // 上身：上衣或连衣裙二选一
    if (tops.isEmpty && dresses.isEmpty) {
      final rawTops = rawCount('上衣');
      final rawDresses = rawCount('连衣裙');
      if (rawTops == 0 && rawDresses == 0) {
        return '还缺一件上衣，再录入 1 件就能生成推荐了';
      }
      if (rawTops == 0 && temp < 20) {
        return '连衣裙要 20℃ 以上才推荐，当前 $tempText，'
            '再加一件长袖 / 卫衣 / 针织衫就能出推荐了';
      }
      return '衣橱里的上衣在 $tempText 下都不太合适，'
          '换季款再录入 1 件就能生成推荐了';
    }

    // 下装：有连衣裙时可以免，否则必须要
    if (bottoms.isEmpty && dresses.isEmpty) {
      final raw = rawCount('下装');
      if (raw == 0) return '还缺一件下装，再录入 1 件就能生成推荐了';
      return '衣橱里的 $raw 件下装在 $tempText 下都不太合适，'
          '换季款再录入 1 件就能生成推荐了';
    }

    // 上面都齐了还是空的：多半是组合被 👎 全部剔除或数据异常。
    // 外套不影响能否出推荐，但天冷时值得提一句。
    if (temp <= 15 && outerwear.isEmpty) {
      return '$tempText 有点冷，衣橱里也没有适合这个温度的外套，加一件会更暖和';
    }

    return '当前天气下这些衣服暂时搭不出一套，去衣橱再添几件不同品类的试试';
  }

  /// 天气卡片
  Widget _buildWeatherCard(dynamic weather) {
    final theme = Theme.of(context);
    final isStale = weather.isStale;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // 天气图标
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                _getWeatherIcon(weather.conditionCode),
                color: AppTheme.primaryColor,
                size: 30,
              ),
            ),
            const SizedBox(width: 16),

            // 天气信息
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        '${weather.temperature.toInt()}℃',
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        weather.description,
                        style: theme.textTheme.titleMedium,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '体感 ${weather.feelsLike.toInt()}℃ · ${weather.cityName}',
                    style: theme.textTheme.bodySmall,
                  ),
                  if (isStale)
                    Text(
                      '数据来自 ${date_util.DateUtils.formatRelative(weather.timestamp)}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: Colors.orange,
                      ),
                    ),
                ],
              ),
            ),

            // 穿搭建议
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _getWeatherTip(weather),
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 推荐卡片
  Widget _buildRecommendationCard(
    RecommendationResult rec,
    int index,
    bool alreadyFeedback,
    RecommendNotifier notifier,
    WearCalendarState calendarState,
  ) {
    final theme = Theme.of(context);

    // 今天是否已穿过这套（排序后比较 itemIds 集合）
    final today = DateTime.now();
    final alreadyWornToday = calendarState
        .recordsFor(today)
        .any((r) => _sameItemSet(r.itemIds, rec.itemIds));

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题行：排名 + 得分
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: _getRankColor(index),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '推荐 ${index + 1}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  '匹配度 ${rec.score.toInt()}%',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppTheme.primaryColor,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // 单品展示行
            SizedBox(
              height: 80,
              child: Row(
                children: rec.items.map((item) {
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Column(
                        children: [
                          // 缩略图
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: ItemImage(
                                imageUrl: item.imageUrl,
                                fit: BoxFit.cover,
                                width: double.infinity,
                                thumbnailWidth: 300,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            item.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall,
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),

            const SizedBox(height: 12),

            // 描述 + 操作
            Row(
              children: [
                // 搭配风格标签
                Expanded(child: _buildOutfitTags(rec)),
                // 👍 / 👎
                if (!alreadyFeedback) ...[
                  IconButton(
                    onPressed: () => _sendFeedback(notifier, rec, liked: true),
                    icon: const Icon(Icons.thumb_up_outlined, size: 20),
                    tooltip: '喜欢',
                    color: Colors.grey,
                    visualDensity: VisualDensity.compact,
                  ),
                  IconButton(
                    onPressed: () => _sendFeedback(notifier, rec, liked: false),
                    icon: const Icon(Icons.thumb_down_outlined, size: 20),
                    tooltip: '不喜欢',
                    color: Colors.grey,
                    visualDensity: VisualDensity.compact,
                  ),
                ] else
                  Text(
                    '已反馈',
                    style: Theme.of(
                      context,
                    ).textTheme.labelSmall?.copyWith(color: Colors.grey),
                  ),
              ],
            ),

            const SizedBox(height: 10),

            // 今天穿这套
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: alreadyWornToday ? null : () => _recordToday(rec),
                icon: Icon(
                  alreadyWornToday
                      ? Icons.check_circle_outline
                      : Icons.event_available,
                  size: 18,
                ),
                label: Text(alreadyWornToday ? '今天已穿这套' : '今天穿这套'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),

            // 推荐理由（scoreDetails 一直算着，只是从来没展示过）
            if (rec.scoreDetails.isNotEmpty) _buildReasonPanel(context, rec),
          ],
        ),
      ),
    );
  }

  /// 发送 👍/👎 反馈
  ///
  /// 落库成功才算数 —— 失败时如实提示，不再"点了赞其实没存上"。
  Future<void> _sendFeedback(
    RecommendNotifier notifier,
    RecommendationResult rec, {
    required bool liked,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await (liked ? notifier.like(rec) : notifier.dislike(rec));
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? (liked ? '已记下，之后会多推荐这类搭配' : '已记下，之后会少推荐这类搭配')
              : '反馈保存失败，请检查网络后重试',
        ),
      ),
    );
  }

  /// 推荐理由面板：把各维度得分翻译成人能看懂的形式
  Widget _buildReasonPanel(BuildContext context, RecommendationResult rec) {
    // 各维度满分（与 recommendation_service 的打分口径一致）
    const maxScores = <String, double>{
      '风格协调': 30,
      '颜色搭配': 25,
      '新鲜度': 20,
      '天气匹配': 15,
      '偏好': 10,
    };

    final theme = Theme.of(context);

    return Theme(
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 8),
        dense: true,
        title: Text(
          '为什么推荐这套',
          style: theme.textTheme.labelMedium?.copyWith(
            color: context.textSecondaryColor,
          ),
        ),
        children: rec.scoreDetails.entries.map((e) {
          final max = maxScores[e.key] ?? 10;
          final ratio = (e.value / max).clamp(0.0, 1.0);
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                SizedBox(
                  width: 60,
                  child: Text(e.key, style: theme.textTheme.labelSmall),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: ratio,
                      minHeight: 6,
                      backgroundColor: context.subtleFillColor,
                      valueColor: AlwaysStoppedAnimation(
                        AppTheme.primaryColor.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 44,
                  child: Text(
                    '${e.value.toStringAsFixed(0)}/${max.toStringAsFixed(0)}',
                    textAlign: TextAlign.right,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: context.textSecondaryColor,
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  /// 记录"今天穿这套"到穿搭日历
  Future<void> _recordToday(RecommendationResult rec) async {
    final key = rec.itemIds.join(',');
    // 防连点：写入进行中不重复触发
    if (_recordingKeys.contains(key)) return;
    _recordingKeys.add(key);

    final messenger = ScaffoldMessenger.of(context);
    final ok = await ref
        .read(wearCalendarProvider.notifier)
        .addRecord(date: DateTime.now(), name: '推荐穿搭', itemIds: rec.itemIds);

    _recordingKeys.remove(key);
    if (!mounted) return;

    messenger.showSnackBar(
      ok
          ? const SnackBar(content: Text('已记录到今日穿搭'))
          : const SnackBar(content: Text('记录失败，请重试')),
    );
  }

  /// 比较两套穿搭是否由相同衣物组成（顺序无关）
  bool _sameItemSet(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    final sa = a.toSet();
    final sb = b.toSet();
    return sa.containsAll(sb);
  }

  /// 搭配风格标签（取单品中频率最高的标签）
  Widget _buildOutfitTags(RecommendationResult rec) {
    final allTags = <String, int>{};
    for (final item in rec.items) {
      for (final tag in item.styleTags) {
        allTags[tag] = (allTags[tag] ?? 0) + 1;
      }
    }
    final sorted = allTags.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topTags = sorted.take(3);

    if (topTags.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: topTags.map((e) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: context.subtleFillColor,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            e.key,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
          ),
        );
      }).toList(),
    );
  }

  Color _getRankColor(int index) {
    switch (index) {
      case 0:
        return const Color(0xFFFFB300); // 金色
      case 1:
        return const Color(0xFF78909C); // 银色
      case 2:
        return const Color(0xFFA1887F); // 铜色
      default:
        return Colors.grey;
    }
  }

  IconData _getWeatherIcon(int code) {
    if (code >= 200 && code < 300) return Icons.thunderstorm;
    if (code >= 300 && code < 400) return Icons.water_drop;
    if (code >= 500 && code < 600) return Icons.water_drop;
    if (code >= 600 && code < 700) return Icons.ac_unit;
    if (code == 800) return Icons.wb_sunny;
    if (code == 801) return Icons.wb_cloudy;
    return Icons.cloud;
  }

  String _getWeatherTip(dynamic weather) {
    final temp = weather.temperature as double;
    final isRainy = weather.isRainy;
    final isSnowy = weather.isSnowy;

    if (isSnowy) return '保暖防滑';
    if (isRainy) return '记得带伞';
    if (temp > 30) return '轻薄透气';
    if (temp > 25) return '清凉舒适';
    if (temp > 20) return '舒适宜人';
    if (temp > 15) return '薄外套';
    if (temp > 10) return '注意保暖';
    if (temp > 5) return '穿厚点';
    if (temp > 0) return '羽绒服';
    return '全副武装';
  }

  // ===== 以下为 recommendation_service 阶段一过滤规则的镜像 =====
  // 推荐页只读得到结果，拿不到中间态；为了告诉用户「缺什么」，
  // 这里把同样的温度规则抄一份。改动 service 时记得同步这里。

  /// 不参与推荐的品类
  static const Set<String> _excludedCategories = {
    '睡衣套装',
    '内衣',
    '西服套装',
    '运动套装',
    '配饰',
  };

  bool _isTopSuitable(String sub, double temp) {
    if (temp > 30) return const ['短袖', '背心'].any((s) => sub.contains(s));
    if (temp >= 25) return const ['短袖', '衬衫'].any((s) => sub.contains(s));
    if (temp >= 20) {
      return const ['短袖', '长袖', '衬衫'].any((s) => sub.contains(s));
    }
    if (temp >= 15) {
      return const ['长袖', '卫衣', '衬衫', '针织衫'].any((s) => sub.contains(s));
    }
    if (temp >= 10) {
      return const ['卫衣', '针织衫', '衬衫'].any((s) => sub.contains(s));
    }
    if (temp >= 5) return const ['针织衫'].any((s) => sub.contains(s));
    return const ['针织衫', '长袖'].any((s) => sub.contains(s));
  }

  bool _isBottomSuitable(String sub, double temp) {
    if (temp > 30) return const ['短裤'].any((s) => sub.contains(s));
    if (temp >= 20) {
      return const ['短裤', '牛仔长裤', '休闲长裤', '半裙'].any(
        (s) => sub.contains(s),
      );
    }
    if (temp >= 10) {
      return const ['牛仔长裤', '休闲长裤', '西装长裤', '半裙'].any(
        (s) => sub.contains(s),
      );
    }
    return const ['牛仔长裤', '休闲长裤', '西装长裤'].any((s) => sub.contains(s));
  }

  bool _isOuterwearSuitable(String sub, double temp) {
    if (temp > 25) return false;
    if (temp >= 20) return const ['夹克', '牛仔外套'].any((s) => sub.contains(s));
    if (temp >= 15) {
      return const ['夹克', '风衣', '牛仔外套'].any((s) => sub.contains(s));
    }
    if (temp >= 10) {
      return const ['西装', '夹克', '风衣'].any((s) => sub.contains(s));
    }
    if (temp >= 5) return const ['大衣', '风衣'].any((s) => sub.contains(s));
    if (temp >= 0) return const ['大衣'].any((s) => sub.contains(s));
    return true; // 低于 0℃ 啥外套都行
  }

  bool _isShoesSuitable(String sub, double temp, WeatherData weather) {
    if (weather.isRainy || weather.isSnowy) {
      return const ['靴子', '运动鞋'].any((s) => sub.contains(s));
    }
    if (temp > 30) {
      return const ['凉鞋', '拖鞋', '平底鞋'].any((s) => sub.contains(s));
    }
    if (temp >= 20) {
      return const ['凉鞋', '运动鞋', '平底鞋'].any((s) => sub.contains(s));
    }
    if (temp >= 15) return const ['运动鞋', '平底鞋'].any((s) => sub.contains(s));
    if (temp >= 10) return const ['运动鞋', '靴子'].any((s) => sub.contains(s));
    if (temp >= 0) return const ['靴子', '运动鞋'].any((s) => sub.contains(s));
    return const ['靴子'].any((s) => sub.contains(s));
  }

  bool _isDressSuitable(double temp) => temp >= 20;
}

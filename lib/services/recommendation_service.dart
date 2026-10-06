import 'dart:math';
import '../core/constants/app_constants.dart';
import '../core/utils/color_utils.dart';
import '../data/models/clothing_item.dart';
import '../data/models/preference_feedback.dart';
import '../data/models/weather_data.dart';

/// 推荐结果
class RecommendationResult {
  /// 上衣
  final ClothingItem? top;

  /// 下装
  final ClothingItem? bottom;

  /// 外套（可为 null）
  final ClothingItem? outerwear;

  /// 鞋类
  final ClothingItem? shoes;

  /// 连衣裙（可为 null，连衣裙自己就是一套）
  final ClothingItem? dress;

  /// 综合得分（0-100）
  final double score;

  /// 各维度得分明细
  final Map<String, double> scoreDetails;

  const RecommendationResult({
    this.top,
    this.bottom,
    this.outerwear,
    this.shoes,
    this.dress,
    required this.score,
    this.scoreDetails = const {},
  });

  /// 获取该搭配涉及的所有单品
  List<ClothingItem> get items {
    return [
      top,
      bottom,
      outerwear,
      shoes,
      dress,
    ].whereType<ClothingItem>().toList();
  }

  /// 单品 ID 列表
  List<String> get itemIds => items.map((e) => e.id).toList();
}

/// 推荐引擎
///
/// V1 纯规则引擎（三阶段）：温度过滤 → 候选池截断 → 评分排序
/// 参见 PRD 第 7 章
class RecommendationService {
  final Random _random = Random();

  /// 生成 Top N 推荐
  ///
  /// [items] 用户所有可用衣物
  /// [weather] 当前天气
  /// [recentItemIds] 最近 7 天穿过的单品 ID（避免重复）
  /// [preference] 用户偏好画像（来自 👍/👎 反馈；为空时退化为通用规则）
  /// [count] 返回数量
  List<RecommendationResult> recommend({
    required List<ClothingItem> items,
    required WeatherData weather,
    List<String> recentItemIds = const [],
    PreferenceProfile preference = PreferenceProfile.empty,
    int count = 3,
  }) {
    if (items.length < AppConstants.minItemsForRecommendation) {
      return [];
    }

    // ============ 阶段一：按温度过滤单品 ============
    final filtered = _filterByWeather(items, weather);

    // 过滤掉最近穿过的单品
    if (recentItemIds.isNotEmpty) {
      for (final key in filtered.keys) {
        filtered[key] = filtered[key]!
            .where((item) => !recentItemIds.contains(item.id))
            .toList();
      }
    }

    // 如果过滤后某类太少，回退（不剔除最近穿过）
    if (_anyCategoryInsufficient(filtered)) {
      final fallback = _filterByWeather(items, weather);
      return _generateRecommendations(fallback, weather, preference, count);
    }

    return _generateRecommendations(filtered, weather, preference, count);
  }

  /// 阶段一：按温度范围筛选类别
  Map<String, List<ClothingItem>> _filterByWeather(
    List<ClothingItem> items,
    WeatherData weather,
  ) {
    final temp = weather.temperature;

    // 温度 → 适合的分类
    // 使用分类常量来过滤
    final tops = <ClothingItem>[];
    final bottoms = <ClothingItem>[];
    final outerwear = <ClothingItem>[];
    final shoes = <ClothingItem>[];
    final dresses = <ClothingItem>[];

    for (final item in items) {
      // 跳过非干净状态
      if (item.status.name != 'clean') continue;

      // 跳过套装类和不可推荐品类（睡衣/内衣不参与推荐）
      final cat = item.category;
      if (cat == '睡衣套装' ||
          cat == '内衣' ||
          cat == '西服套装' ||
          cat == '运动套装' ||
          cat == '配饰') {
        continue;
      }

      final sub = item.subCategory ?? '';

      switch (cat) {
        case '上衣':
          if (_isTopSuitable(sub, temp)) tops.add(item);
          break;
        case '下装':
          if (_isBottomSuitable(sub, temp)) bottoms.add(item);
          break;
        case '外套':
          if (_isOuterwearSuitable(sub, temp)) outerwear.add(item);
          break;
        case '鞋':
          if (_isShoesSuitable(sub, temp, weather)) shoes.add(item);
          break;
        case '连衣裙':
          if (_isDressSuitable(temp)) dresses.add(item);
          break;
      }
    }

    return {
      'tops': tops,
      'bottoms': bottoms,
      'outerwear': outerwear,
      'shoes': shoes,
      'dresses': dresses,
    };
  }

  // ---- 温度适配判断（参见 PRD 7.3 表格）----

  bool _isTopSuitable(String sub, double temp) {
    if (temp > 30) return ['短袖', '背心'].any((s) => sub.contains(s));
    if (temp >= 25) return ['短袖', '衬衫'].any((s) => sub.contains(s));
    if (temp >= 20) return ['短袖', '长袖', '衬衫'].any((s) => sub.contains(s));
    if (temp >= 15)
      return ['长袖', '卫衣', '衬衫', '针织衫'].any((s) => sub.contains(s));
    if (temp >= 10) return ['卫衣', '针织衫', '衬衫'].any((s) => sub.contains(s));
    if (temp >= 5) return ['针织衫'].any((s) => sub.contains(s));
    if (temp >= 0) return ['针织衫', '长袖'].any((s) => sub.contains(s));
    return ['针织衫', '长袖'].any((s) => sub.contains(s));
  }

  bool _isBottomSuitable(String sub, double temp) {
    if (temp > 30) return ['短裤'].any((s) => sub.contains(s));
    if (temp >= 20)
      return ['短裤', '牛仔长裤', '休闲长裤', '半裙'].any((s) => sub.contains(s));
    if (temp >= 10)
      return ['牛仔长裤', '休闲长裤', '西装长裤', '半裙'].any((s) => sub.contains(s));
    return ['牛仔长裤', '休闲长裤', '西装长裤'].any((s) => sub.contains(s));
  }

  bool _isOuterwearSuitable(String sub, double temp) {
    if (temp > 25) return false;
    if (temp >= 20) return ['夹克', '牛仔外套'].any((s) => sub.contains(s));
    if (temp >= 15) return ['夹克', '风衣', '牛仔外套'].any((s) => sub.contains(s));
    if (temp >= 10) return ['西装', '夹克', '风衣'].any((s) => sub.contains(s));
    if (temp >= 5) return ['大衣', '风衣'].any((s) => sub.contains(s));
    if (temp >= 0) return ['大衣'].any((s) => sub.contains(s));
    return true; // 低于 0° 啥外套都行
  }

  bool _isShoesSuitable(String sub, double temp, WeatherData weather) {
    if (weather.isRainy || weather.isSnowy) {
      return ['靴子', '运动鞋'].any((s) => sub.contains(s));
    }
    if (temp > 30) return ['凉鞋', '拖鞋', '平底鞋'].any((s) => sub.contains(s));
    if (temp >= 20) return ['凉鞋', '运动鞋', '平底鞋'].any((s) => sub.contains(s));
    if (temp >= 15) return ['运动鞋', '平底鞋'].any((s) => sub.contains(s));
    if (temp >= 10) return ['运动鞋', '靴子'].any((s) => sub.contains(s));
    if (temp >= 0) return ['靴子', '运动鞋'].any((s) => sub.contains(s));
    return ['靴子'].any((s) => sub.contains(s));
  }

  bool _isDressSuitable(double temp) {
    return temp >= 20; // 20° 以上才推荐连衣裙
  }

  /// 检查某类是否数量不足
  bool _anyCategoryInsufficient(Map<String, List<ClothingItem>> filtered) {
    return filtered['tops']!.isEmpty && filtered['dresses']!.isEmpty;
  }

  // ============================================================
  //  阶段二：候选池生成 + 截断
  // ============================================================

  List<RecommendationResult> _generateRecommendations(
    Map<String, List<ClothingItem>> filtered,
    WeatherData weather,
    PreferenceProfile preference,
    int count,
  ) {
    // 混排 + 截断（按上限取前 M 件）
    final tops = _shuffleAndCap(filtered['tops']!, AppConstants.maxTops);
    final bottoms = _shuffleAndCap(
      filtered['bottoms']!,
      AppConstants.maxBottoms,
    );
    final outerwear = _shuffleAndCap(
      filtered['outerwear']!,
      AppConstants.maxOuterwear,
    );
    final shoes = _shuffleAndCap(filtered['shoes']!, AppConstants.maxShoes);
    final dresses = _shuffleAndCap(filtered['dresses']!, 10);

    final candidates = <RecommendationResult>[];

    // 组合模式 A：连衣裙（自成一套）
    if (dresses.isNotEmpty && shoes.isNotEmpty) {
      for (final dress in dresses) {
        for (final shoe in shoes.take(3)) {
          candidates.add(
            RecommendationResult(
              dress: dress,
              shoes: shoe,
              score: 0, // 稍后评分
            ),
          );
        }
      }
    }

    // 组合模式 B：上衣 + 下装 + 鞋（有/无外套）
    if (tops.isNotEmpty && bottoms.isNotEmpty && shoes.isNotEmpty) {
      for (final top in tops) {
        for (final bottom in bottoms) {
          for (final shoe in shoes.take(3)) {
            // 无外套版本
            candidates.add(
              RecommendationResult(
                top: top,
                bottom: bottom,
                shoes: shoe,
                score: 0,
              ),
            );

            // 有外套版本（只取前 3 件外套）
            for (final outer in outerwear.take(3)) {
              candidates.add(
                RecommendationResult(
                  top: top,
                  bottom: bottom,
                  outerwear: outer,
                  shoes: shoe,
                  score: 0,
                ),
              );
            }
          }
        }
      }
    }

    // ============ 阶段三：评分排序 ============
    for (int i = 0; i < candidates.length; i++) {
      candidates[i] = _score(candidates[i], weather, preference);
    }

    // 按分数降序排序
    candidates.sort((a, b) => b.score.compareTo(a.score));

    // 用户明确 👎 过的同款组合直接剔除（此前该参数从未被使用）。
    // 例外：全被 👎 掉时保留原样 —— 宁可重复出现，也好过给用户一个空页面。
    final kept = _removeDisliked(candidates, preference.dislikedCombos);
    if (kept.isNotEmpty) {
      candidates
        ..clear()
        ..addAll(kept);
    }

    // 取 Top N（加入少许随机性：前 5 名随机抽 count 个）
    final topPool = candidates.take(10).toList();
    topPool.shuffle(_random);
    final results = topPool.take(count).toList();
    results.sort((a, b) => b.score.compareTo(a.score));

    return results;
  }

  /// 混排 + 截断
  List<ClothingItem> _shuffleAndCap(List<ClothingItem> items, int cap) {
    final list = List<ClothingItem>.from(items);
    // 混合取：最近添加的前一半 + 随机抽后一半
    final split = list.length ~/ 2;
    final recent = list.sublist(0, min(split, list.length));
    final rest = list.sublist(min(split, list.length))..shuffle(_random);
    return [...recent, ...rest].take(cap).toList();
  }

  // ============================================================
  //  阶段三：评分
  // ============================================================

  /// 剔除用户明确 👎 过的同款组合
  ///
  /// 判定用集合相等（同一批单品，顺序无关）。
  ///
  /// 注意：**必须返回新列表**。调用方会 `clear()` 原列表再 `addAll` 返回值，
  /// 若这里直接返回同一个实例，就会把自己清空。
  List<RecommendationResult> _removeDisliked(
    List<RecommendationResult> candidates,
    List<List<String>> disliked,
  ) {
    if (disliked.isEmpty) {
      return List<RecommendationResult>.of(candidates);
    }
    final dislikedSets = disliked
        .map((ids) => ids.toSet())
        .toList(growable: false);

    return candidates.where((c) {
      final ids = c.itemIds.toSet();
      for (final d in dislikedSets) {
        if (d.length == ids.length && d.containsAll(ids)) return false;
      }
      return true;
    }).toList();
  }

  /// 多维度评分（满分 100）
  RecommendationResult _score(
    RecommendationResult result,
    WeatherData weather,
    PreferenceProfile preference,
  ) {
    double styleScore = 0;
    double colorScore = 0;
    double freshnessScore = 0;
    double weatherScore = 0;
    double preferenceScore = 0;

    final items = result.items;
    if (items.isEmpty) return result;

    // ---------- 风格协调性（满分 30）----------
    final allTags = items.expand((item) => item.styleTags).toList();
    final tagCounts = <String, int>{};
    for (final tag in allTags) {
      tagCounts[tag] = (tagCounts[tag] ?? 0) + 1;
    }
    final sharedTags = tagCounts.entries.where((e) => e.value >= 2).length;
    if (sharedTags >= 2) {
      styleScore = 30;
    } else if (sharedTags == 1) {
      styleScore = 22;
    } else {
      styleScore = 10; // 完全没有共享标签给基础分
    }

    // ---------- 颜色协调性（满分 25）----------
    if (items.length >= 2) {
      final colors = items.expand((item) => item.colors).toList();
      if (colors.length >= 2) {
        double totalColorScore = 0;
        int pairCount = 0;
        for (int i = 0; i < colors.length; i++) {
          for (int j = i + 1; j < colors.length; j++) {
            final diff = ColorUtils.hueDifference(colors[i].hex, colors[j].hex);
            if (diff < 30) {
              totalColorScore += 25; // 同色系
            } else if (diff < 60) {
              totalColorScore += 18; // 邻近色
            } else if (diff >= 150 && diff <= 180) {
              totalColorScore += 12; // 对比色
            } else {
              totalColorScore += 8; // 无特定关系
            }
            pairCount++;
          }
        }
        colorScore = pairCount > 0 ? totalColorScore / pairCount : 8;
      } else {
        colorScore = 12;
      }
    } else {
      colorScore = 12;
    }

    // ---------- 新鲜度提升（满分 20）----------
    for (final item in items) {
      if (item.lastWornDate == null ||
          DateTime.now().difference(item.lastWornDate!).inDays > 7) {
        freshnessScore += 5; // 超 7 天未穿: +5/件
      }
    }
    freshnessScore = min(freshnessScore, 20);

    // ---------- 天气匹配度（满分 15）----------
    weatherScore = 15; // 已通过阶段一过滤，视为完全符合

    // 雨天特殊扣分
    if (weather.isRainy || weather.isSnowy) {
      bool hasWaterproofShoes = items.any((item) {
        final sub = item.subCategory ?? '';
        return ['靴子', '运动鞋'].any((s) => sub.contains(s));
      });
      if (!hasWaterproofShoes) weatherScore -= 5;
    }

    // ---------- 偏好匹配度（满分 10）----------
    // 没有反馈数据时给 5 分基础分（中性，不影响排序）；
    // 有数据时把 -1~1 的偏好分映射到 0~10。
    // 此前这里是硬编码 5 分，等于「偏好」这一维度从未参与推荐。
    preferenceScore = 5 + preference.comboScore(items) * 5;

    final total = [
      styleScore,
      colorScore,
      freshnessScore,
      weatherScore,
      preferenceScore,
    ].fold(0.0, (a, b) => a + b);

    return RecommendationResult(
      top: result.top,
      bottom: result.bottom,
      outerwear: result.outerwear,
      shoes: result.shoes,
      dress: result.dress,
      score: total.clamp(0, 100),
      scoreDetails: {
        '风格协调': styleScore,
        '颜色搭配': colorScore,
        '新鲜度': freshnessScore,
        '天气匹配': weatherScore,
        '偏好': preferenceScore,
      },
    );
  }
}

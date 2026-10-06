import 'clothing_item.dart';

/// 一条偏好反馈（对应 Supabase `preference_feedback` 表的一行）
class PreferenceFeedback {
  final String id;
  final String userId;

  /// 这次反馈涉及的单品（一套搭配可能 3-4 件）
  final List<String> itemIds;

  /// true = 👍 喜欢，false = 👎 不喜欢
  final bool liked;

  final DateTime createdAt;

  const PreferenceFeedback({
    required this.id,
    required this.userId,
    required this.itemIds,
    required this.liked,
    required this.createdAt,
  });

  factory PreferenceFeedback.fromJson(Map<String, dynamic> data) {
    return PreferenceFeedback(
      id: data['id'] as String? ?? '',
      userId: data['user_id'] as String? ?? '',
      itemIds: List<String>.from(data['item_ids'] ?? []),
      liked: data['liked'] as bool? ?? true,
      createdAt:
          DateTime.tryParse(data['created_at'] as String? ?? '')?.toLocal() ??
          DateTime.now(),
    );
  }
}

/// 聚合后的偏好画像
///
/// 把「一堆 👍/👎 记录」折算成单品与风格标签的偏好分，
/// 供推荐引擎在评分时使用。
///
/// 为什么标签也要算：用户可能只对某一类单品点过赞
/// （比如两件"针织衫"），这时新出现的针织衫也该被偏好加分，
/// 否则学到的只是"这两件具体衣服"。
class PreferenceProfile {
  /// itemId → 累计偏好分（👍 +1，👎 -1）
  final Map<String, int> itemScores;

  /// 风格标签 → 累计偏好分
  final Map<String, int> tagScores;

  /// 被 👎 过的组合（用于直接过滤掉同款组合）
  final List<List<String>> dislikedCombos;

  const PreferenceProfile({
    this.itemScores = const {},
    this.tagScores = const {},
    this.dislikedCombos = const [],
  });

  static const PreferenceProfile empty = PreferenceProfile();

  /// 没有任何反馈数据
  bool get isEmpty => itemScores.isEmpty && tagScores.isEmpty;

  /// 从反馈记录 + 衣物列表构建画像
  factory PreferenceProfile.from({
    required List<PreferenceFeedback> feedbacks,
    required List<ClothingItem> items,
  }) {
    if (feedbacks.isEmpty) return empty;

    final itemById = {for (final i in items) i.id: i};
    final itemScores = <String, int>{};
    final tagScores = <String, int>{};
    final disliked = <List<String>>[];

    for (final f in feedbacks) {
      final delta = f.liked ? 1 : -1;
      for (final id in f.itemIds) {
        itemScores[id] = (itemScores[id] ?? 0) + delta;
        final item = itemById[id];
        if (item != null) {
          for (final tag in item.styleTags) {
            tagScores[tag] = (tagScores[tag] ?? 0) + delta;
          }
        }
      }
      if (!f.liked) disliked.add(f.itemIds);
    }

    return PreferenceProfile(
      itemScores: itemScores,
      tagScores: tagScores,
      dislikedCombos: disliked,
    );
  }

  /// 单件偏好，归一化到 -1 ~ 1
  double itemScore(String itemId) => _normalize(itemScores[itemId] ?? 0);

  /// 一组标签的平均偏好，归一化到 -1 ~ 1
  double tagScore(List<String> tags) {
    if (tags.isEmpty) return 0;
    var sum = 0;
    for (final t in tags) {
      sum += tagScores[t] ?? 0;
    }
    return _normalize(sum / tags.length);
  }

  /// 整套搭配的偏好分，-1 ~ 1
  ///
  /// 单品权重高于标签：用户对具体某件的态度比"风格大类"更明确。
  double comboScore(List<ClothingItem> items) {
    if (isEmpty || items.isEmpty) return 0;
    var sum = 0.0;
    for (final item in items) {
      sum += itemScore(item.id) * 0.6 + tagScore(item.styleTags) * 0.4;
    }
    return (sum / items.length).clamp(-1.0, 1.0);
  }

  /// 归一化：累计 3 次同向反馈即接近饱和，避免个别反馈权重过大
  static double _normalize(num v) {
    if (v == 0) return 0;
    final clamped = v.clamp(-3, 3);
    return clamped / 3.0;
  }
}

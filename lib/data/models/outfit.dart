/// 解析 Supabase 返回的日期
DateTime? _parseDate(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value)?.toLocal();
  return null;
}

/// Outfit（搭配组合）模型
///
/// 对应 Supabase `outfits` 表
class Outfit {
  final String id;
  final String userId;
  final String name;
  final String? description;
  final List<String> itemIds; // 包含的单品 ID 列表
  final List<String> seasonTags;
  final List<String> styleTags;
  final String? imageUrl;
  final int wearCount;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Outfit({
    required this.id,
    required this.userId,
    required this.name,
    this.description,
    this.itemIds = const [],
    this.seasonTags = const [],
    this.styleTags = const [],
    this.imageUrl,
    this.wearCount = 0,
    required this.createdAt,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? createdAt;

  /// 从 Supabase 行创建
  factory Outfit.fromJson(Map<String, dynamic> data) {
    return Outfit(
      id: data['id'] as String? ?? '',
      userId: data['user_id'] as String? ?? '',
      name: data['name'] as String? ?? '',
      description: data['description'] as String?,
      itemIds: List<String>.from(data['item_ids'] ?? []),
      seasonTags: List<String>.from(data['season_tags'] ?? []),
      styleTags: List<String>.from(data['style_tags'] ?? []),
      imageUrl: data['image_url'] as String?,
      wearCount: data['wear_count'] as int? ?? 0,
      createdAt: _parseDate(data['created_at']) ?? DateTime.now(),
      updatedAt: _parseDate(data['updated_at']),
    );
  }

  /// 转为 Supabase 行
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'name': name,
      'description': description,
      'item_ids': itemIds,
      'season_tags': seasonTags,
      'style_tags': styleTags,
      'image_url': imageUrl,
      'wear_count': wearCount,
      'created_at': createdAt.toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    };
  }

  /// 创建副本
  ///
  /// 可空字段（description / imageUrl）要置 null 必须用显式开关，
  /// 因为参数默认 null 无法区分「没传」和「要清空」：
  ///   outfit.copyWith(clearDescription: true)
  Outfit copyWith({
    String? id,
    String? userId,
    String? name,
    String? description,
    List<String>? itemIds,
    List<String>? seasonTags,
    List<String>? styleTags,
    String? imageUrl,
    int? wearCount,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool clearDescription = false,
    bool clearImageUrl = false,
  }) {
    return Outfit(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      description: clearDescription ? null : (description ?? this.description),
      itemIds: itemIds ?? this.itemIds,
      seasonTags: seasonTags ?? this.seasonTags,
      styleTags: styleTags ?? this.styleTags,
      imageUrl: clearImageUrl ? null : (imageUrl ?? this.imageUrl),
      wearCount: wearCount ?? this.wearCount,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }
}

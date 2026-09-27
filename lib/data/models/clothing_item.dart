import '../../domain/enums/clothing_status.dart';
import 'color_info.dart';

/// 解析 Supabase 返回的日期（可能是 ISO 字符串或 DateTime）
DateTime? _parseDate(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is String) {
    return DateTime.tryParse(value)?.toLocal();
  }
  return null;
}

/// 服装单品模型
///
/// 对应 Supabase `clothing_items` 表
class ClothingItem {
  final String id;
  final String userId;
  final String name;
  final String category;
  final String? subCategory;
  final String? customCategory;
  final String imageUrl;
  final String? originalImageUrl;
  final List<ColorInfo> colors;
  final List<String> styleTags;
  final List<String> seasonTags;
  final List<String> occasionTags; // 场合：通勤/日常/约会/运动/正式/居家
  final String? wearFrequency; // 穿着频率：常穿/偶尔穿/待处理
  final String? brand;
  final double? price;
  final DateTime? purchaseDate;
  final ClothingStatus status;
  final int wearCount;
  final DateTime? lastWornDate;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ClothingItem({
    required this.id,
    required this.userId,
    required this.name,
    required this.category,
    this.subCategory,
    this.customCategory,
    required this.imageUrl,
    this.originalImageUrl,
    this.colors = const [],
    this.styleTags = const [],
    this.seasonTags = const [],
    this.occasionTags = const [],
    this.wearFrequency,
    this.brand,
    this.price,
    this.purchaseDate,
    this.status = ClothingStatus.clean,
    this.wearCount = 0,
    this.lastWornDate,
    required this.createdAt,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? createdAt;

  /// 从 Supabase 行创建
  factory ClothingItem.fromJson(Map<String, dynamic> data) {
    return ClothingItem(
      id: data['id'] as String? ?? '',
      userId: data['user_id'] as String? ?? '',
      name: data['name'] as String? ?? '未命名',
      category: data['category'] as String? ?? '其他',
      subCategory: data['sub_category'] as String?,
      customCategory: data['custom_category'] as String?,
      imageUrl: data['image_url'] as String? ?? '',
      originalImageUrl: data['original_image_url'] as String?,
      colors:
          (data['colors'] as List<dynamic>?)
              ?.map((c) => ColorInfo.fromMap(c as Map<String, dynamic>))
              .toList() ??
          [],
      styleTags: List<String>.from(data['style_tags'] ?? []),
      seasonTags: List<String>.from(data['season_tags'] ?? []),
      occasionTags: List<String>.from(data['occasion_tags'] ?? []),
      wearFrequency: data['wear_frequency'] as String?,
      brand: data['brand'] as String?,
      price: (data['price'] as num?)?.toDouble(),
      purchaseDate: _parseDate(data['purchase_date']),
      status: ClothingStatus.fromString(data['status'] as String? ?? 'clean'),
      wearCount: data['wear_count'] as int? ?? 0,
      lastWornDate: _parseDate(data['last_worn_date']),
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
      'category': category,
      'sub_category': subCategory,
      'custom_category': customCategory,
      'image_url': imageUrl,
      'original_image_url': originalImageUrl,
      'colors': colors.map((c) => c.toMap()).toList(),
      'style_tags': styleTags,
      'season_tags': seasonTags,
      'occasion_tags': occasionTags,
      'wear_frequency': wearFrequency,
      'brand': brand,
      'price': price,
      'purchase_date': purchaseDate?.toIso8601String(),
      'status': status.name,
      'wear_count': wearCount,
      'last_worn_date': lastWornDate?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    };
  }

  /// 创建副本（用于不可变更新）
  ///
  /// 关于可空字段：由于参数默认是 null，`subCategory ?? this.subCategory`
  /// 这类写法无法区分「没传」和「要清空」，所以清空必须用显式开关：
  ///   item.copyWith(clearBrand: true)      // 品牌置 null
  ///   item.copyWith(clearPrice: true)      // 价格置 null
  /// 其余 clearXxx 同理。两者同时传时 clear 优先。
  ClothingItem copyWith({
    String? id,
    String? userId,
    String? name,
    String? category,
    String? subCategory,
    String? customCategory,
    String? imageUrl,
    String? originalImageUrl,
    List<ColorInfo>? colors,
    List<String>? styleTags,
    List<String>? seasonTags,
    List<String>? occasionTags,
    String? wearFrequency,
    String? brand,
    double? price,
    DateTime? purchaseDate,
    ClothingStatus? status,
    int? wearCount,
    DateTime? lastWornDate,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool clearSubCategory = false,
    bool clearCustomCategory = false,
    bool clearOriginalImageUrl = false,
    bool clearWearFrequency = false,
    bool clearBrand = false,
    bool clearPrice = false,
    bool clearPurchaseDate = false,
    bool clearLastWornDate = false,
  }) {
    return ClothingItem(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      category: category ?? this.category,
      subCategory: clearSubCategory ? null : (subCategory ?? this.subCategory),
      customCategory: clearCustomCategory
          ? null
          : (customCategory ?? this.customCategory),
      imageUrl: imageUrl ?? this.imageUrl,
      originalImageUrl: clearOriginalImageUrl
          ? null
          : (originalImageUrl ?? this.originalImageUrl),
      colors: colors ?? this.colors,
      styleTags: styleTags ?? this.styleTags,
      seasonTags: seasonTags ?? this.seasonTags,
      occasionTags: occasionTags ?? this.occasionTags,
      wearFrequency: clearWearFrequency
          ? null
          : (wearFrequency ?? this.wearFrequency),
      brand: clearBrand ? null : (brand ?? this.brand),
      price: clearPrice ? null : (price ?? this.price),
      purchaseDate: clearPurchaseDate
          ? null
          : (purchaseDate ?? this.purchaseDate),
      status: status ?? this.status,
      wearCount: wearCount ?? this.wearCount,
      lastWornDate: clearLastWornDate
          ? null
          : (lastWornDate ?? this.lastWornDate),
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  /// 性价比：价格 / 穿着次数（穿着次数 > 0 才计算）
  double? get costPerWear {
    if (price == null || wearCount <= 0) return null;
    return price! / wearCount;
  }

  /// 是否久未穿着（超过阈值）
  bool isLongNotWorn(int thresholdDays) {
    if (lastWornDate == null) return true;
    return DateTime.now().difference(lastWornDate!).inDays > thresholdDays;
  }

  @override
  String toString() =>
      'ClothingItem(id: $id, name: $name, category: $category)';
}

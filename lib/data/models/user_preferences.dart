/// 用户偏好设置模型
class UserPreferences {
  final bool enableWeatherRecommendation;
  final String? defaultLocation;
  final List<String> favoriteStyles;
  final List<String> excludedCategories;
  final int maxRecommendationItems;

  const UserPreferences({
    this.enableWeatherRecommendation = true,
    this.defaultLocation,
    this.favoriteStyles = const [],
    this.excludedCategories = const [],
    this.maxRecommendationItems = 3,
  });

  /// 从 Firestore 文档创建
  factory UserPreferences.fromMap(Map<String, dynamic> map) {
    return UserPreferences(
      enableWeatherRecommendation: map['enableWeatherRecommendation'] as bool? ?? true,
      defaultLocation: map['defaultLocation'] as String?,
      favoriteStyles: List<String>.from(map['favoriteStyles'] ?? []),
      excludedCategories: List<String>.from(map['excludedCategories'] ?? []),
      maxRecommendationItems: map['maxRecommendationItems'] as int? ?? 3,
    );
  }

  /// 转为 Firestore 文档
  Map<String, dynamic> toMap() {
    return {
      'enableWeatherRecommendation': enableWeatherRecommendation,
      'defaultLocation': defaultLocation,
      'favoriteStyles': favoriteStyles,
      'excludedCategories': excludedCategories,
      'maxRecommendationItems': maxRecommendationItems,
    };
  }

  UserPreferences copyWith({
    bool? enableWeatherRecommendation,
    String? defaultLocation,
    List<String>? favoriteStyles,
    List<String>? excludedCategories,
    int? maxRecommendationItems,
  }) {
    return UserPreferences(
      enableWeatherRecommendation: enableWeatherRecommendation ?? this.enableWeatherRecommendation,
      defaultLocation: defaultLocation ?? this.defaultLocation,
      favoriteStyles: favoriteStyles ?? this.favoriteStyles,
      excludedCategories: excludedCategories ?? this.excludedCategories,
      maxRecommendationItems: maxRecommendationItems ?? this.maxRecommendationItems,
    );
  }
}

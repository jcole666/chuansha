/// 应用全局常量
class AppConstants {
  AppConstants._();

  /// 应用名称
  static const String appName = '穿啥';

  /// 解锁推荐所需的最少衣物数量
  static const int minItemsForRecommendation = 5;

  /// 推荐页展示数量
  static const int recommendationCount = 3;

  /// 天气缓存有效期（秒）
  static const int weatherCacheSeconds = 3600;

  /// 图片最大宽度（像素）
  static const int imageMaxWidth = 1024;

  /// 图片压缩质量（0-100）
  static const int imageQuality = 85;

  /// 图片缓存最大容量（MB）
  static const int imageCacheMaxSize = 200;

  /// 候选池截断上限
  static const int maxTops = 15;
  static const int maxBottoms = 15;
  static const int maxShoes = 10;
  static const int maxOuterwear = 10;

  /// 最近穿着天数（用于新鲜度计算）
  static const int recentWearDays = 7;

  /// 久未穿着天数阈值
  static const int longNotWornDays = 60;
}

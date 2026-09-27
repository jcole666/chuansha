/// 编译期配置（通过 --dart-define 注入）
///
/// 为什么密钥不能硬编码：
///   Dart 代码编译进 APK/IPA 后可以被反编译提取常量字符串。
///   OpenWeatherMap 的 key 一旦泄露就会被人盗刷配额（账单是你的）。
///   走 --dart-define 至少能让密钥不落在源码仓库里，
///   配合 CI 的 secret 管理即可。
///
/// 用法：
///   flutter run --dart-define=OWM_API_KEY=xxxx
///   flutter build apk --dart-define=OWM_API_KEY=xxxx
///
/// 也支持从 `--dart-define-from-file=config.json` 读取。
class AppConfig {
  AppConfig._();

  /// OpenWeatherMap API Key
  ///
  /// 未配置时为空字符串，[hasWeatherApiKey] 为 false，
  /// 天气功能会明确提示"未配置"而不是静默返回假数据。
  static const String owmApiKey = String.fromEnvironment(
    'OWM_API_KEY',
    defaultValue: '',
  );

  /// 是否配置了天气密钥
  static bool get hasWeatherApiKey => owmApiKey.isNotEmpty;

  /// 定位超时（秒）—— 定位不可用时不至于让首屏卡太久
  static const int locationTimeoutSeconds = 8;

  /// 定位不可用时的兜底城市坐标（默认上海）
  ///
  /// 仅在用户拒绝授权 / 定位失败时使用，避免整个天气功能不可用。
  static const double fallbackLat = 31.2304;
  static const double fallbackLon = 121.4737;
  static const String fallbackCity = '上海';
}

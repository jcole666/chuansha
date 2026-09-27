/// 天气数据模型
class WeatherData {
  /// 当前温度（摄氏度）
  final double temperature;

  /// 体感温度
  final double feelsLike;

  /// 天气状况码（OpenWeatherMap 格式）
  /// 800=晴, 2xx=雷雨, 3xx=毛毛雨, 5xx=雨, 6xx=雪
  final int conditionCode;

  /// 天气状况中文描述（如"晴"、"多云"、"小雨"）
  final String description;

  /// 风力等级
  final double windSpeed;

  /// 湿度百分比
  final int humidity;

  /// 城市名称
  final String cityName;

  /// 数据获取时间
  final DateTime timestamp;

  const WeatherData({
    required this.temperature,
    required this.feelsLike,
    required this.conditionCode,
    required this.description,
    required this.windSpeed,
    required this.humidity,
    required this.cityName,
    required this.timestamp,
  });

  /// 是否为晴天
  bool get isSunny => conditionCode == 800;

  /// 是否为雨天（码 2xx, 3xx, 5xx）
  bool get isRainy {
    return (conditionCode >= 200 && conditionCode < 400) ||
        (conditionCode >= 500 && conditionCode < 600);
  }

  /// 是否为雪天（码 6xx）
  bool get isSnowy => conditionCode >= 600 && conditionCode < 700;

  /// 是否为大风天（风力 > 5 级，约 8 m/s）
  bool get isWindy => windSpeed >= 8.0;

  /// 是否数据过期（超过 1 小时）
  bool get isStale {
    return DateTime.now().difference(timestamp).inSeconds > 3600;
  }

  /// 天气图标（Material Icons）
  String get iconName {
    if (isSnowy) return 'ac_unit';
    if (isRainy) return 'water_drop';
    if (isWindy) return 'air';
    if (conditionCode >= 801 && conditionCode <= 804) return 'cloud';
    if (conditionCode == 800) return 'wb_sunny';
    return 'cloud_queue'; // 多云
  }

  /// 风向人类可读描述
  String get weatherSummary {
    final buf = StringBuffer('$description · ${temperature.toInt()}℃');
    if (windSpeed >= 8.0) buf.write(' · 大风');
    return buf.toString();
  }

  /// 根据 OpenWeatherMap JSON 构造
  factory WeatherData.fromJson(Map<String, dynamic> json) {
    return WeatherData(
      temperature: (json['main']['temp'] as num).toDouble(),
      feelsLike: (json['main']['feels_like'] as num).toDouble(),
      conditionCode: json['weather'][0]['id'] as int,
      description: json['weather'][0]['description'] as String,
      windSpeed: (json['wind']['speed'] as num).toDouble(),
      humidity: json['main']['humidity'] as int,
      cityName: json['name'] as String? ?? '未知',
      timestamp: DateTime.now(),
    );
  }

  /// 创建 Mock 天气数据（开发用）
  factory WeatherData.mock() {
    return WeatherData(
      temperature: 26.0,
      feelsLike: 28.0,
      conditionCode: 800,
      description: '晴',
      windSpeed: 3.5,
      humidity: 55,
      cityName: '上海（Mock）',
      timestamp: DateTime.now(),
    );
  }
}

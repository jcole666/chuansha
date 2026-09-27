import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/app_config.dart';
import '../data/models/weather_data.dart';
import 'location_service.dart';

/// 天气服务
///
/// 接入 OpenWeatherMap API，按**真实定位**取天气，缓存 1 小时。
///
/// 相比之前的三点改进：
/// 1. 坐标不再写死上海 —— 走 [LocationService]（授权失败才兜底）
/// 2. API Key 不再硬编码 —— 从 --dart-define=OWM_API_KEY 注入
/// 3. 失败不再静默返回 mock 假数据 —— 抛出 [WeatherException]，
///    由 UI 决定怎么提示（用户有权知道看到的是不是真数据）
class WeatherService {
  static const String _baseUrl =
      'https://api.openweathermap.org/data/2.5/weather';

  final LocationService _locationService;

  WeatherService({LocationService? locationService})
    : _locationService = locationService ?? LocationService();

  WeatherData? _cached;

  /// 获取天气数据（带缓存）
  ///
  /// [lat] / [lon] 显式指定坐标时优先使用（比如用户在设置里手动选了城市），
  /// 否则自动定位。
  Future<WeatherData> getWeather({
    double? lat,
    double? lon,
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _cached != null && !_cached!.isStale) {
      return _cached!;
    }

    if (!AppConfig.hasWeatherApiKey) {
      throw const WeatherException(
        '未配置天气服务（缺少 OWM_API_KEY），'
        '请用 --dart-define=OWM_API_KEY=你的密钥 启动',
      );
    }

    // 坐标：显式传入 > 自动定位（含兜底）
    double useLat;
    double useLon;
    if (lat != null && lon != null) {
      useLat = lat;
      useLon = lon;
    } else {
      final place = await _locationService.getCurrentPlace(
        forceRefresh: forceRefresh,
      );
      useLat = place.lat;
      useLon = place.lon;
    }

    final url = Uri.parse(
      '$_baseUrl'
      '?lat=$useLat'
      '&lon=$useLon'
      '&appid=${AppConfig.owmApiKey}'
      '&units=metric'
      '&lang=zh_cn',
    );

    final http.Response response;
    try {
      response = await http.get(url).timeout(const Duration(seconds: 10));
    } on TimeoutException {
      throw const WeatherException('获取天气超时，请检查网络');
    } catch (e) {
      throw WeatherException('获取天气失败：$e');
    }

    if (response.statusCode == 401) {
      throw const WeatherException('天气服务密钥无效，请检查 OWM_API_KEY');
    }
    if (response.statusCode != 200) {
      throw WeatherException('天气服务返回异常（${response.statusCode}）');
    }

    try {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      _cached = WeatherData.fromJson(json);
      return _cached!;
    } catch (e) {
      throw WeatherException('天气数据解析失败：$e');
    }
  }

  /// 强制刷新（忽略缓存）
  Future<WeatherData> refreshWeather({double? lat, double? lon}) {
    return getWeather(lat: lat, lon: lon, forceRefresh: true);
  }

  /// 缓存时间戳
  DateTime? get lastUpdateTime => _cached?.timestamp;

  /// 释放资源
  void dispose() {
    _cached = null;
  }
}

/// 天气异常（用户可理解的错误，UI 直接展示 message）
class WeatherException implements Exception {
  final String message;
  const WeatherException(this.message);

  @override
  String toString() => message;
}

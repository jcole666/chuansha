import 'dart:async';

import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

import '../core/app_config.dart';

/// 定位结果
class LocatedPlace {
  final double lat;
  final double lon;

  /// 城市名（反查失败时为空）
  final String city;

  /// 是否用的是兜底坐标（用户拒绝授权 / 定位失败）
  final bool isFallback;

  const LocatedPlace({
    required this.lat,
    required this.lon,
    this.city = '',
    this.isFallback = false,
  });

  /// 兜底（上海）
  static const LocatedPlace fallback = LocatedPlace(
    lat: AppConfig.fallbackLat,
    lon: AppConfig.fallbackLon,
    city: AppConfig.fallbackCity,
    isFallback: true,
  );
}

/// 定位服务
///
/// 之前项目的 geolocator / geocoding 依赖装了却从来没用过，
/// 天气一直写死上海坐标。这里把它接上：
/// 授权 → 取坐标 → 反查城市名。
///
/// 任何一步失败都不抛异常，返回 [LocatedPlace.fallback]，
/// 保证天气功能始终可用（只是位置不准）。
class LocationService {
  /// 获取当前位置（带超时与兜底）
  ///
  /// [forceRefresh] 为 true 时忽略系统缓存，拿最新位置。
  Future<LocatedPlace> getCurrentPlace({bool forceRefresh = false}) async {
    try {
      return await _resolve(
        forceRefresh: forceRefresh,
      ).timeout(Duration(seconds: AppConfig.locationTimeoutSeconds));
    } catch (_) {
      // 超时 / 权限被拒 / 定位服务关闭 —— 一律兜底，不打断主流程
      return LocatedPlace.fallback;
    }
  }

  Future<LocatedPlace> _resolve({required bool forceRefresh}) async {
    // 1. 定位服务是否打开（比如用户关掉了 GPS）
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return LocatedPlace.fallback;

    // 2. 权限
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return LocatedPlace.fallback;
    }

    // 3. 取坐标
    final position = await Geolocator.getCurrentPosition(
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.low, // 天气用城市级精度足够，省电
        timeLimit: Duration(seconds: AppConfig.locationTimeoutSeconds),
      ),
    );

    // 4. 反查城市名（失败不影响坐标使用）
    var city = '';
    try {
      final marks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );
      if (marks.isNotEmpty) {
        final m = marks.first;
        city =
            m.locality ?? m.subAdministrativeArea ?? m.administrativeArea ?? '';
      }
    } catch (_) {
      // 反查失败就留空，UI 会退化成只显示温度
    }

    return LocatedPlace(
      lat: position.latitude,
      lon: position.longitude,
      city: city,
    );
  }
}

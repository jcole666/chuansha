import 'package:shared_preferences/shared_preferences.dart';

/// 本地键值存储
///
/// 之前项目完全没有本地持久化，导致：
/// - 引导页每次冷启动都出现
/// - 视图模式（网格/列表）切了又变回去
///
/// 统一收在这里，避免各处散落字符串 key。
class LocalStore {
  LocalStore._();

  static const String _kOnboardingSeen = 'onboarding_seen';
  static const String _kGridView = 'wardrobe_grid_view';

  static Future<SharedPreferences> get _prefs =>
      SharedPreferences.getInstance();

  // ---------------- 引导页 ----------------

  /// 是否已经看过新手引导
  static Future<bool> hasSeenOnboarding() async {
    final prefs = await _prefs;
    return prefs.getBool(_kOnboardingSeen) ?? false;
  }

  static Future<void> setOnboardingSeen() async {
    final prefs = await _prefs;
    await prefs.setBool(_kOnboardingSeen, true);
  }

  // ---------------- 衣橱视图模式 ----------------

  /// 是否网格视图（默认网格）
  static Future<bool> isGridView() async {
    final prefs = await _prefs;
    return prefs.getBool(_kGridView) ?? true;
  }

  static Future<void> setGridView(bool value) async {
    final prefs = await _prefs;
    await prefs.setBool(_kGridView, value);
  }
}

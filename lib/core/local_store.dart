import 'package:shared_preferences/shared_preferences.dart';

/// 本地键值存储 + 离线缓存
///
/// 之前项目完全没有本地持久化，导致：
/// - 引导页每次冷启动都出现
/// - 视图模式（网格/列表）切了又变回去
/// - 断网就是白屏，看不到任何已有数据
///
/// 统一收在这里，避免各处散落字符串 key。
///
/// 用法：`main()` 里先 `await LocalStore.preload()`，
/// 之后 [seenOnboardingSync] / [gridViewSync] / [readCache] 可同步读取
/// （路由的 redirect 是同步的，拿不到 Future）。
class LocalStore {
  LocalStore._();

  static const String _kOnboardingSeen = 'onboarding_seen';
  static const String _kGridView = 'wardrobe_grid_view';

  /// 离线缓存 key 前缀，便于一键清理且不误伤偏好设置
  static const String cachePrefix = 'cache_';

  static SharedPreferences? _prefs;

  /// 启动时调用一次；未调用时所有同步 getter 返回安全默认值
  static Future<void> preload() async {
    try {
      _prefs = await SharedPreferences.getInstance();
    } catch (_) {
      // 存储不可用（极少见）时降级为「无本地状态」，不影响启动
      _prefs = null;
    }
  }

  static SharedPreferences? get _p => _prefs;

  // ---------------- 引导页 ----------------

  /// 是否已经看过新手引导（同步）
  static bool get seenOnboardingSync => _p?.getBool(_kOnboardingSeen) ?? false;

  static Future<void> setOnboardingSeen() async {
    await _p?.setBool(_kOnboardingSeen, true);
  }

  // ---------------- 衣橱视图模式 ----------------

  /// 是否网格视图（默认网格，同步）
  static bool get gridViewSync => _p?.getBool(_kGridView) ?? true;

  static Future<void> setGridView(bool value) async {
    await _p?.setBool(_kGridView, value);
  }

  // ---------------- 离线缓存 ----------------

  /// 读缓存（同步）。没有缓存返回 null。
  static String? readCache(String key) => _p?.getString('$cachePrefix$key');

  /// 写缓存。失败静默 —— 缓存写不进去不该影响主流程。
  static Future<void> writeCache(String key, String value) async {
    try {
      await _p?.setString('$cachePrefix$key', value);
    } catch (_) {
      // 忽略
    }
  }

  /// 清除所有离线缓存（保留偏好设置）
  static Future<void> clearCache() async {
    final prefs = _p;
    if (prefs == null) return;
    for (final key in prefs.getKeys().toList()) {
      if (key.startsWith(cachePrefix)) {
        await prefs.remove(key);
      }
    }
  }
}

/// 离线缓存的 key 常量
class CacheKeys {
  CacheKeys._();

  /// 衣橱列表（按用户区分）
  static String clothingItems(String userId) => 'clothing_items_$userId';

  /// 搭配列表（按用户区分）
  static String outfits(String userId) => 'outfits_$userId';
}

/// 路由路径常量
class AppRoutes {
  AppRoutes._();

  /// 新手引导页（首次启动）
  static const String onboarding = '/onboarding';

  /// 衣橱页
  static const String wardrobe = '/wardrobe';

  /// 推荐页（已并入搭配页，保留路径兼容）
  static const String recommend = '/recommend';

  /// 穿搭日历页
  static const String calendar = '/calendar';

  /// 我的页
  static const String profile = '/profile';

  /// 登录页
  static const String login = '/auth/login';

  /// 注册页
  static const String register = '/auth/register';

  /// 衣物详情页
  static const String itemDetail = '/wardrobe/detail';

  /// 添衣页面（拍照+信息编辑）
  static const String addItem = '/wardrobe/add';

  /// 衣物编辑页
  static const String editItem = '/wardrobe/edit';

  /// 设置页
  static const String settings = '/profile/settings';

  /// Outfit 搭配列表
  static const String outfits = '/outfits';

  /// 统计分析页
  static const String stats = '/profile/stats';
}

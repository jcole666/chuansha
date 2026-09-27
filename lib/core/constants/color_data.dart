/// 预设色系（中文色系名 → 代表色值）
///
/// 按色系归位，方便搭配推荐
class ColorData {
  ColorData._();

  /// 预设色系列表：{色系名: 代表色值}
  static const Map<String, String> presetColors = {
    '黑色系': '#1A1A1A',
    '白色系': '#FFFFFF',
    '灰色系': '#9E9E9E',
    '红色系': '#D32F2F',
    '橙色系': '#F57C00',
    '黄色系': '#FBC02D',
    '绿色系': '#388E3C',
    '蓝色系': '#1976D2',
    '紫色系': '#7B1FA2',
    '粉色系': '#F48FB1',
    '棕色系': '#6D4C41',
    '米色系': '#F0E6D6',
    '牛仔蓝': '#5B7FA6',
    '卡其色系': '#C9B18B',
    '彩色': '#E91E63',
  };

  /// 获取色系名称列表
  static List<String> get colorNames => presetColors.keys.toList();

  /// 根据名称获取色值
  static String? getHex(String name) => presetColors[name];

  /// 根据色值模糊匹配色系名称
  static String findClosestColorName(String hex) {
    final upper = hex.toUpperCase();
    final found = presetColors.entries.where(
      (e) => e.value.toUpperCase() == upper,
    );
    if (found.isNotEmpty) return found.first.key;
    return '彩色';
  }
}

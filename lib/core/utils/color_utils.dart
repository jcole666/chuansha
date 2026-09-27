/// 颜色计算工具
class ColorUtils {
  ColorUtils._();

  /// 将十六进制色值字符串转为 RGB 分量
  ///
  /// [hex] 格式如 "#FF0000" 或 "FF0000"
  static List<int> hexToRgb(String hex) {
    hex = hex.replaceAll('#', '');
    return [
      int.parse(hex.substring(0, 2), radix: 16),
      int.parse(hex.substring(2, 4), radix: 16),
      int.parse(hex.substring(4, 6), radix: 16),
    ];
  }

  /// 计算两个颜色的色相差值（简化版）
  ///
  /// 将 RGB 转为色相角（0-360），返回角度差（0-180）
  static double hueDifference(String hex1, String hex2) {
    final rgb1 = hexToRgb(hex1);
    final rgb2 = hexToRgb(hex2);

    final hue1 = _rgbToHue(rgb1[0], rgb1[1], rgb1[2]);
    final hue2 = _rgbToHue(rgb2[0], rgb2[1], rgb2[2]);

    final diff = (hue1 - hue2).abs();
    return diff > 180 ? 360 - diff : diff;
  }

  /// 简化版 RGB → 色相转换（0-360）
  static double _rgbToHue(int r, int g, int b) {
    final rn = r / 255.0;
    final gn = g / 255.0;
    final bn = b / 255.0;

    final max = [rn, gn, bn].reduce((a, b) => a > b ? a : b);
    final min = [rn, gn, bn].reduce((a, b) => a < b ? a : b);
    final delta = max - min;

    if (delta == 0) return 0;

    double hue;
    if (max == rn) {
      hue = ((gn - bn) / delta) % 6;
    } else if (max == gn) {
      hue = (bn - rn) / delta + 2;
    } else {
      hue = (rn - gn) / delta + 4;
    }

    hue *= 60;
    if (hue < 0) hue += 360;
    return hue;
  }
}

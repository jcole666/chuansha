/// 颜色信息
class ColorInfo {
  /// 中文颜色名（如"黑色"、"白色"）
  final String name;

  /// 十六进制色值（如 "#FF0000"）
  final String hex;

  /// 颜色在图片中的占比（0.0-1.0）
  final double ratio;

  const ColorInfo({
    required this.name,
    required this.hex,
    this.ratio = 0.0,
  });

  /// 从 JSON 创建
  factory ColorInfo.fromMap(Map<String, dynamic> map) {
    return ColorInfo(
      name: map['name'] as String? ?? '',
      hex: map['hex'] as String? ?? '#000000',
      ratio: (map['ratio'] as num?)?.toDouble() ?? 0.0,
    );
  }

  /// 转为 JSON
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'hex': hex,
      'ratio': ratio,
    };
  }

  @override
  String toString() => 'ColorInfo(name: $name, hex: $hex)';
}

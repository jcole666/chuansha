import 'package:flutter/material.dart';

/// 颜色色块选择器
///
/// 用于衣物录入时的手动颜色选择
class ColorSwatch extends StatelessWidget {
  /// 颜色映射：{名称: 色值}
  final Map<String, String> colorMap;

  /// 当前选中颜色名称
  final String? selectedColor;

  /// 选择回调
  final ValueChanged<String>? onColorSelected;

  /// 是否允许多选
  final bool multiSelect;

  /// 多选时已选中的颜色
  final List<String>? selectedColors;

  const ColorSwatch({
    super.key,
    required this.colorMap,
    this.selectedColor,
    this.onColorSelected,
    this.multiSelect = false,
    this.selectedColors,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: colorMap.entries.map((entry) {
        final isSelected = multiSelect
            ? (selectedColors?.contains(entry.key) ?? false)
            : selectedColor == entry.key;

        return GestureDetector(
          onTap: () => onColorSelected?.call(entry.key),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _hexToColor(entry.value),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : Colors.grey.shade300,
                    width: isSelected ? 3 : 1,
                  ),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: Theme.of(context)
                                .colorScheme
                                .primary
                                .withValues(alpha: 0.3),
                            blurRadius: 8,
                            spreadRadius: 1,
                          ),
                        ]
                      : null,
                ),
                child: isSelected
                    ? Icon(
                        Icons.check,
                        size: 16,
                        color: _isLightColor(entry.value)
                            ? Colors.black54
                            : Colors.white,
                      )
                    : null,
              ),
              const SizedBox(height: 4),
              Text(
                entry.key,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: isSelected
                          ? Theme.of(context).colorScheme.primary
                          : null,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.normal,
                    ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  /// 十六进制字符串 → Color
  Color _hexToColor(String hex) {
    hex = hex.replaceAll('#', '');
    if (hex.length == 6) hex = 'FF$hex';
    return Color(int.parse(hex, radix: 16));
  }

  /// 判断是否为浅色（用于决定勾选图标颜色）
  bool _isLightColor(String hex) {
    hex = hex.replaceAll('#', '');
    final r = int.parse(hex.substring(0, 2), radix: 16);
    final g = int.parse(hex.substring(2, 4), radix: 16);
    final b = int.parse(hex.substring(4, 6), radix: 16);
    // 相对亮度公式
    final brightness = (r * 299 + g * 587 + b * 114) / 1000;
    return brightness > 150;
  }
}

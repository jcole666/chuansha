import 'package:flutter/material.dart';

/// 标签 Chip
///
/// 用于筛选栏、风格标签等场景
class TagChip extends StatelessWidget {
  /// 标签文本
  final String label;

  /// 是否选中
  final bool isSelected;

  /// 选中回调
  final ValueChanged<bool>? onSelected;

  /// 删除回调（设置后显示删除按钮）
  final VoidCallback? onDeleted;

  /// 前缀图标
  final IconData? leadingIcon;

  const TagChip({
    super.key,
    required this.label,
    this.isSelected = false,
    this.onSelected,
    this.onDeleted,
    this.leadingIcon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (onSelected != null) {
      // 可选模式（FilterChip）
      return FilterChip(
        label: Text(label),
        selected: isSelected,
        onSelected: onSelected,
        avatar: leadingIcon != null ? Icon(leadingIcon, size: 18) : null,
        selectedColor: theme.colorScheme.primary.withValues(alpha: 0.15),
        checkmarkColor: theme.colorScheme.primary,
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      );
    }

    if (onDeleted != null) {
      // 可删除模式（InputChip）
      return InputChip(
        label: Text(label),
        onDeleted: onDeleted,
        deleteIconColor: theme.colorScheme.onSurface.withValues(alpha: 0.5),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      );
    }

    // 纯展示模式
    return Chip(
      label: Text(label),
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    );
  }
}

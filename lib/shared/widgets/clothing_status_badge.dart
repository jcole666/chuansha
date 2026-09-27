import 'package:flutter/material.dart';
import '../../domain/enums/clothing_status.dart';

/// 衣物状态角标 + 颜色映射
///
/// 统一各处的状态展示（衣橱卡片角标、详情页状态标签），
/// 避免每个页面重复写 _statusColor。
class ClothingStatusBadge extends StatelessWidget {
  final ClothingStatus status;
  final bool compact;

  const ClothingStatusBadge({
    super.key,
    required this.status,
    this.compact = false,
  });

  /// 状态对应颜色
  static Color colorFor(ClothingStatus status) {
    return switch (status) {
      ClothingStatus.clean => Colors.green,
      ClothingStatus.dirty => Colors.orange,
      ClothingStatus.dryCleaning => Colors.blue,
      ClothingStatus.inLaundry => Colors.purple,
    };
  }

  @override
  Widget build(BuildContext context) {
    final color = colorFor(status);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 5 : 8,
        vertical: compact ? 1 : 3,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          color: color,
          fontSize: compact ? 9 : 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

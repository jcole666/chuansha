import 'package:flutter/material.dart';

/// 通用错误状态组件
///
/// 显示错误信息和重试按钮
class ErrorView extends StatelessWidget {
  /// 错误信息
  final String message;

  /// 图标（可选）
  final IconData? icon;

  /// 重试回调
  final VoidCallback? onRetry;

  /// 次要操作文案
  final String? secondaryLabel;

  /// 次要操作回调
  final VoidCallback? onSecondaryAction;

  const ErrorView({
    super.key,
    required this.message,
    this.icon,
    this.onRetry,
    this.secondaryLabel,
    this.onSecondaryAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 图标
            Icon(
              icon ?? Icons.wifi_off_rounded,
              size: 64,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 16),

            // 错误信息
            Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),

            // 重试按钮
            if (onRetry != null)
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('重试'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                ),
              ),

            // 次要操作
            if (secondaryLabel != null && onSecondaryAction != null) ...[
              const SizedBox(height: 12),
              TextButton(
                onPressed: onSecondaryAction,
                child: Text(secondaryLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

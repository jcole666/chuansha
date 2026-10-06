import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

/// 全屏半透明加载遮罩
///
/// 用于图片处理等耗时操作的加载提示
class LoadingOverlay extends StatelessWidget {
  /// 加载文案
  final String message;

  const LoadingOverlay({super.key, this.message = '正在处理...'});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black38,
      child: Center(
        child: Card(
          margin: const EdgeInsets.all(32),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 48,
                  height: 48,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: AppTheme.primaryColor,
                  ),
                ),
                const SizedBox(height: 20),
                Text(message, style: Theme.of(context).textTheme.bodyLarge),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

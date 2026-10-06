import 'package:flutter/material.dart';

/// 离线提示条
///
/// 网络请求失败、界面回退到本地缓存时显示，
/// 让用户知道「看到的是旧数据」而不是以为数据丢了。
class OfflineBanner extends StatelessWidget {
  /// 点击重试（可为 null，则不显示重试按钮）
  final VoidCallback? onRetry;

  const OfflineBanner({super.key, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: Colors.orange.shade50,
      child: Row(
        children: [
          Icon(Icons.cloud_off, size: 16, color: Colors.orange.shade800),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '当前无网络，显示的是本地缓存数据',
              style: TextStyle(fontSize: 12, color: Colors.orange.shade900),
            ),
          ),
          if (onRetry != null)
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('重试', style: TextStyle(fontSize: 12)),
            ),
        ],
      ),
    );
  }
}

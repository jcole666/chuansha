import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/error_log.dart';
import '../../../../core/theme/app_theme.dart';

/// 运行日志页
///
/// 真机联调时用：把运行期异常与关键流程记录显示出来，
/// 一键复制后可以直接发出去定位问题。
class LogPage extends StatefulWidget {
  const LogPage({super.key});

  @override
  State<LogPage> createState() => _LogPageState();
}

class _LogPageState extends State<LogPage> {
  @override
  Widget build(BuildContext context) {
    // 监听日志变化，有新日志自动刷新
    return ValueListenableBuilder<int>(
      valueListenable: ErrorLog.revision,
      builder: (context, _, _) {
        final entries = ErrorLog.entries.reversed.toList(growable: false);

        return Scaffold(
          appBar: AppBar(
            title: const Text('运行日志'),
            actions: [
              IconButton(
                icon: const Icon(Icons.copy_all_outlined),
                tooltip: '复制全部',
                onPressed: entries.isEmpty ? null : _copyAll,
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: '清空',
                onPressed: entries.isEmpty ? null : _confirmClear,
              ),
            ],
          ),
          body: entries.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.check_circle_outline,
                          size: 56,
                          color: Colors.green.shade400,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '暂无异常记录',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '应用运行正常。出现问题时这里会记录详情，'
                          '可直接复制反馈。',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: entries.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) => _LogTile(entry: entries[i]),
                ),
        );
      },
    );
  }

  Future<void> _copyAll() async {
    await Clipboard.setData(ClipboardData(text: ErrorLog.export()));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('日志已复制到剪贴板')));
  }

  Future<void> _confirmClear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空日志？'),
        content: const Text('清空后无法恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (ok == true) ErrorLog.clear();
  }
}

class _LogTile extends StatelessWidget {
  final ErrorLogEntry entry;

  const _LogTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final time = entry.time.toIso8601String();
    final stamp = '${time.substring(5, 10)} ${time.substring(11, 19)}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  entry.tag,
                  style: TextStyle(
                    fontSize: 11,
                    color: AppTheme.primaryColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                stamp,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: context.textHintColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SelectableText(
            entry.message,
            style: theme.textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
              height: 1.5,
            ),
          ),
          if (entry.stack != null) ...[
            const SizedBox(height: 4),
            Text(
              entry.stack!.split('\n').take(3).join('\n'),
              style: theme.textTheme.labelSmall?.copyWith(
                color: context.textHintColor,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ],
      ),
    );
  }
}

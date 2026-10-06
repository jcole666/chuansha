import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/constants/routes.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

/// "我的"页面
///
/// 用户资料、设置入口、统计入口
class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final authState = ref.watch(authProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: ListView(
        children: [
          // 用户概览卡片
          Container(
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                // 头像
                CircleAvatar(
                  radius: 32,
                  backgroundColor: theme.colorScheme.primary.withValues(
                    alpha: 0.1,
                  ),
                  child: Icon(
                    Icons.person,
                    size: 36,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 16),
                // 用户名
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        authState.isLoggedIn
                            ? (authState.user?.email ?? '已登录')
                            : '未登录',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        authState.isLoggedIn ? '登录后可同步数据' : '登录后查看更多功能',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                // 操作按钮
                if (authState.isLoggedIn)
                  TextButton(
                    onPressed: () => ref.read(authProvider.notifier).signOut(),
                    child: const Text('退出'),
                  )
                else
                  IconButton(
                    onPressed: () => context.push(AppRoutes.login),
                    icon: const Icon(Icons.chevron_right),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),

          const SizedBox(height: 16),

          // 菜单列表
          _MenuTile(
            icon: Icons.bar_chart_rounded,
            title: '穿着统计',
            subtitle: '查看衣物穿着频次和性价比',
            onTap: () => context.push(AppRoutes.stats),
          ),
          _MenuTile(
            icon: Icons.settings_outlined,
            title: '设置',
            subtitle: '偏好设置、数据管理',
            onTap: () => context.push(AppRoutes.settings),
          ),
          _MenuTile(
            icon: Icons.info_outline,
            title: '关于',
            // 版本号不再写死（之前写死 1.0.0，实际已是 1.1.x），
            // 具体版本在关于页里从安装包读取
            subtitle: '版本信息、数据说明',
            onTap: () => context.push(AppRoutes.about),
          ),
        ],
      ),
    );
  }
}

/// 菜单项
class _MenuTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  const _MenuTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          icon,
          color: Theme.of(context).colorScheme.primary,
          size: 22,
        ),
      ),
      title: Text(title),
      subtitle: subtitle != null ? Text(subtitle!) : null,
      trailing: const Icon(Icons.chevron_right, size: 20),
      onTap: onTap,
    );
  }
}

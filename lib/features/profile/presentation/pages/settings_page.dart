import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/routes.dart';
import '../../../../core/local_store.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../auth/presentation/providers/gender_provider.dart';
import '../../../wardrobe/presentation/providers/wardrobe_provider.dart';
import '../../../../services/account_service.dart';

/// 设置页
///
/// 此前「设置」入口是空的 `onTap: () {}`。
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  bool _isClearing = false;

  /// 注销进行中
  bool _isDeleting = false;

  /// 注销账号
  ///
  /// 要求手动输入「确认注销」才能继续 —— 这是不可逆操作。
  /// 成功后由路由守卫自动回到登录页，这里不用手动跳转。
  Future<void> _deleteAccount() async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('注销账号'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '注销后，你的衣物、照片、穿搭记录将被永久删除，且无法恢复。\n\n'
                '请输入「确认注销」以继续。',
                style: TextStyle(fontSize: 13, height: 1.6),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                onChanged: (_) => setDialogState(() {}),
                decoration: const InputDecoration(
                  hintText: '确认注销',
                  isDense: true,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: controller.text.trim() == '确认注销'
                  ? () => Navigator.of(ctx).pop(true)
                  : null,
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('永久删除'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();

    if (confirmed != true || !mounted) return;

    setState(() => _isDeleting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await AccountService().deleteAccount();
      // 成功后路由守卫会接管跳转；这里不需要再做什么
    } catch (e) {
      if (mounted) setState(() => _isDeleting = false);
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _changeGender() async {
    final current = ref.read(userGenderProvider);
    final picked = await showDialog<UserGender>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('选择性别'),
        children: [
          // 用 ListTile + 勾选图标而不是 RadioListTile：
          // 后者的 groupValue/onChanged 在新版 Flutter 已弃用
          _genderOption(ctx, current, UserGender.male, '男'),
          _genderOption(ctx, current, UserGender.female, '女'),
        ],
      ),
    );
    if (picked == null || !mounted) return;

    final ok = await ref.read(userGenderProvider.notifier).save(picked);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(ok ? '性别已更新' : '更新失败，请检查网络后重试')));
  }

  Widget _genderOption(
    BuildContext ctx,
    UserGender current,
    UserGender value,
    String label,
  ) {
    final selected = current == value;
    return ListTile(
      title: Text(label),
      trailing: selected
          ? Icon(Icons.check, color: AppTheme.primaryColor)
          : null,
      onTap: () => Navigator.of(ctx).pop(value),
    );
  }

  Future<void> _toggleGridView(bool value) async {
    ref.read(wardrobeListProvider.notifier).setGridView(value);
    await LocalStore.setGridView(value);
  }

  Future<void> _clearCache() async {
    setState(() => _isClearing = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await DefaultCacheManager().emptyCache();
      messenger.showSnackBar(const SnackBar(content: Text('图片缓存已清除')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('清除失败：$e')));
    } finally {
      if (mounted) setState(() => _isClearing = false);
    }
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('退出登录？'),
        content: const Text('退出后需要重新登录才能查看你的衣橱。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('退出'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    // 退出后由路由守卫自动回到登录页，这里不用手动跳转
    await ref.read(authProvider.notifier).signOut();
  }

  @override
  Widget build(BuildContext context) {
    final email = ref.watch(authProvider).user?.email ?? '未登录';
    final gender = ref.watch(userGenderProvider);
    final isGridView = ref.watch(wardrobeListProvider).isGridView;

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: [
          _sectionTitle('账号'),
          ListTile(
            leading: const Icon(Icons.mail_outline),
            title: const Text('邮箱'),
            subtitle: Text(email),
          ),
          ListTile(
            leading: const Icon(Icons.wc_outlined),
            title: const Text('性别'),
            subtitle: Text(_genderLabel(gender)),
            trailing: const Icon(Icons.chevron_right, size: 20),
            onTap: _changeGender,
          ),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('退出登录', style: TextStyle(color: Colors.red)),
            onTap: _signOut,
          ),

          const Divider(height: 32),
          _sectionTitle('显示'),
          SwitchListTile(
            secondary: const Icon(Icons.grid_view_outlined),
            title: const Text('衣橱默认网格视图'),
            subtitle: const Text('关闭则默认列表视图'),
            value: isGridView,
            onChanged: _toggleGridView,
          ),

          const Divider(height: 32),
          _sectionTitle('数据'),
          ListTile(
            leading: const Icon(Icons.cleaning_services_outlined),
            title: const Text('清除图片缓存'),
            subtitle: const Text('不会删除你的衣物数据'),
            trailing: _isClearing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.chevron_right, size: 20),
            onTap: _isClearing ? null : _clearCache,
          ),

          const Divider(height: 32),
          _sectionTitle('危险操作'),
          ListTile(
            leading: _isDeleting
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.person_remove_outlined, color: Colors.red),
            title: const Text('注销账号', style: TextStyle(color: Colors.red)),
            subtitle: const Text('永久删除账号与全部数据，不可恢复'),
            onTap: _isDeleting ? null : _deleteAccount,
          ),

          const Divider(height: 32),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('隐私政策'),
            trailing: const Icon(Icons.chevron_right, size: 20),
            onTap: () => context.push(AppRoutes.privacy),
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('关于穿啥'),
            trailing: const Icon(Icons.chevron_right, size: 20),
            onTap: () => context.push(AppRoutes.about),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  String _genderLabel(UserGender g) {
    switch (g) {
      case UserGender.male:
        return '男';
      case UserGender.female:
        return '女';
      case UserGender.unknown:
        return '未设置（分类显示全部）';
    }
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: AppTheme.textSecondary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

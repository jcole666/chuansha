import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;
import '../../../../../core/theme/app_theme.dart';
import '../../../../../core/constants/routes.dart';
import '../providers/auth_provider.dart';
import '../providers/gender_provider.dart';

/// 登录/注册页面
///
/// - 注册时需要选择性别
/// - 登录成功后进入主页
/// - 不允许跳过
class AuthPage extends ConsumerStatefulWidget {
  final UserGender initialGender;

  const AuthPage({super.key, this.initialGender = UserGender.male});

  @override
  ConsumerState<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends ConsumerState<AuthPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  late UserGender _selectedGender = widget.initialGender;

  /// 重置密码邮件发送中
  bool _isSendingReset = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    // 默认显示注册页（新用户优先注册）
    _tabController.index = 1;
  }

  @override
  void dispose() {
    _tabController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final notifier = ref.read(authProvider.notifier);
    final isRegister = _tabController.index == 1;

    // 登录成功后自动跳转主页（衣橱）
    ref.listen<AuthState>(authProvider, (prev, next) {
      // 只在「本次会话刚变成已登录」时处理，避免重复触发
      final justLoggedIn = next.isLoggedIn && (prev?.isLoggedIn != true);
      if (justLoggedIn) {
        // 注意：这里不再无条件写回性别。
        // 旧实现会在「登录」时也把默认 gender（male）写回 users 表，
        // 把老用户已保存的性别覆盖掉。性别仅在注册时写入。
        if (isRegister) {
          _saveGenderPreference(next.user?.id);
        }
        context.go(AppRoutes.wardrobe);
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('登录 / 注册')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 24),

                // Logo
                Icon(
                  Icons.checkroom_rounded,
                  size: 72,
                  color: AppTheme.primaryColor.withValues(alpha: 0.6),
                ),
                const SizedBox(height: 16),
                Text(
                  '穿啥',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),

                // Tab 切换（自定义分段控件，整格高亮）
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: context.subtleFillColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      _buildSegmentedTab(
                        label: '登录',
                        isSelected: !isRegister,
                        onTap: () => setState(() {
                          _tabController.index = 0;
                        }),
                      ),
                      const SizedBox(width: 3),
                      _buildSegmentedTab(
                        label: '注册',
                        isSelected: isRegister,
                        onTap: () => setState(() {
                          _tabController.index = 1;
                        }),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // ===== 性别选择（仅注册时显示）=====
                if (isRegister) ...[
                  Text('选择性别', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _GenderCard(
                          icon: Icons.male,
                          label: '男',
                          isSelected: _selectedGender == UserGender.male,
                          onTap: () =>
                              setState(() => _selectedGender = UserGender.male),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _GenderCard(
                          icon: Icons.female,
                          label: '女',
                          isSelected: _selectedGender == UserGender.female,
                          onTap: () => setState(
                            () => _selectedGender = UserGender.female,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                ],

                // 邮箱
                TextFormField(
                  controller: _emailController,
                  decoration: const InputDecoration(
                    labelText: '邮箱',
                    hintText: '请输入邮箱地址',
                    prefixIcon: Icon(Icons.email_outlined, size: 20),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return '请输入邮箱';
                    if (!v.contains('@')) return '邮箱格式不正确';
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // 密码
                TextFormField(
                  controller: _passwordController,
                  decoration: const InputDecoration(
                    labelText: '密码',
                    hintText: '至少 6 位密码',
                    prefixIcon: Icon(Icons.lock_outlined, size: 20),
                  ),
                  obscureText: true,
                  validator: (v) {
                    if (v == null || v.isEmpty) return '请输入密码';
                    if (v.length < 6) return '密码至少 6 位';
                    return null;
                  },
                ),
                const SizedBox(height: 8),

                // 结果提示（成功绿色 / 失败红色）
                //
                // Supabase 开启邮箱验证时，注册接口返回 user == null，
                // auth_provider 把「注册成功，请前往邮箱验证后登录」放进了
                // errorMessage。若一律按红色渲染，用户会以为注册失败。
                if (authState.errorMessage != null)
                  _buildMessageBanner(context, authState.errorMessage!),

                // 忘记密码（仅登录模式；注册模式没有"忘记"一说）
                if (!isRegister)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _isSendingReset
                          ? null
                          : () => _showResetDialog(notifier),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text(
                        '忘记密码？',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                  ),

                const SizedBox(height: 24),

                // 提交按钮
                SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    onPressed: authState.isLoading
                        ? null
                        : () => _submit(notifier),
                    style: ElevatedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: authState.isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            _tabController.index == 0 ? '登录' : '注册',
                            style: const TextStyle(fontSize: 16),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 弹窗输入邮箱并发送重置密码邮件
  Future<void> _showResetDialog(AuthNotifier notifier) async {
    final controller = TextEditingController(
      text: _emailController.text.trim(),
    );

    final email = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重置密码'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(hintText: '输入注册时用的邮箱'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('发送'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (email == null || email.isEmpty || !mounted) return;

    setState(() => _isSendingReset = true);
    final messenger = ScaffoldMessenger.of(context);
    final error = await notifier.sendPasswordReset(email);
    if (!mounted) return;
    setState(() => _isSendingReset = false);

    messenger.showSnackBar(
      SnackBar(content: Text(error ?? '重置链接已发送到 $email，请查收邮件')),
    );
  }

  void _submit(AuthNotifier notifier) {
    if (!_formKey.currentState!.validate()) return;

    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (_tabController.index == 0) {
      notifier.signIn(email, password);
    } else {
      notifier.signUp(email, password);
    }
  }

  /// 结果提示条
  ///
  /// 成功类（如「注册成功，请前往邮箱验证后登录」）用绿色 + ✓，
  /// 真正的错误（邮箱已注册、密码错误…）保持红色 + ⚠，
  /// 让用户一眼分清「注册成了」和「注册失败」。
  Widget _buildMessageBanner(BuildContext context, String message) {
    final isSuccess = _isSuccessMessage(message);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // 深色模式下品牌色偏暗，提示色各提亮一档保证对比度
    final successColor = isDark
        ? const Color(0xFF66BB6A)
        : AppTheme.successColor;
    final errorColor = isDark ? const Color(0xFFEF5350) : AppTheme.errorColor;
    final color = isSuccess ? successColor : errorColor;

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              isSuccess ? Icons.check_circle_outline : Icons.error_outline,
              size: 18,
              color: color,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: color, fontSize: 13, height: 1.3),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 判断提示文案是否属于「成功」性质
  ///
  /// 先排除明显的失败词，再匹配成功词，避免把「注册失败」误判成成功。
  bool _isSuccessMessage(String message) {
    for (final word in const ['失败', '错误', '超时', '不正确', '已被注册']) {
      if (message.contains(word)) return false;
    }
    return message.contains('成功') ||
        message.contains('已发送') ||
        message.contains('请查收');
  }

  /// 仅在「注册成功」时把性别写入 Supabase users 表
  ///
  /// 登录时不调用（否则会用默认值覆盖用户已保存的性别）。
  /// 只插 id 列（满足外键），gender/email 单独尝试，列不存在也不影响。
  Future<void> _saveGenderPreference(String? uid) async {
    if (uid == null) return;

    // 先本地生效，避免云端回读前分类列表还是旧的
    ref.read(userGenderProvider.notifier).setLocal(_selectedGender);

    try {
      // 1. 确保用户记录存在（只插 id，100% 满足外键）
      await Supabase.instance.client.from('users').upsert({'id': uid});
      // 2. 尝试补充性别（若 gender 列存在）
      try {
        await Supabase.instance.client
            .from('users')
            .update({
              'gender': _selectedGender == UserGender.male ? 'male' : 'female',
            })
            .eq('id', uid);
      } catch (_) {
        // gender 列可能不存在，忽略
      }
      // 3. 尝试补充邮箱（若 email 列存在）
      try {
        await Supabase.instance.client
            .from('users')
            .update({'email': _emailController.text.trim()})
            .eq('id', uid);
      } catch (_) {
        // email 列可能不存在，忽略
      }
    } catch (_) {
      // 静默失败，不影响主流程
    }
  }

  /// 分段式 Tab（选中时整格变蓝）
  Widget _buildSegmentedTab({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.primaryColor : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isSelected ? Colors.white : context.textSecondaryColor,
              fontSize: 15,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }
}

/// 性别选择卡片
class _GenderCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _GenderCard({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primaryColor.withValues(alpha: 0.1)
              : context.subtleFillColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppTheme.primaryColor : context.subtleFillColor,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 40,
              color: isSelected ? AppTheme.primaryColor : Colors.grey.shade400,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 16,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected
                    ? AppTheme.primaryColor
                    : context.textSecondaryColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

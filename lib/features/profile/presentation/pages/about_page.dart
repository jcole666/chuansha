import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../../core/app_config.dart';
import '../../../../core/theme/app_theme.dart';

/// 关于页
///
/// 版本号从安装包信息读取，不再写死
/// （此前 profile 页写死「版本 1.0.0」，而 pubspec 已经是 1.1.3+9）。
class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  String _version = '读取中...';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        _version = info.version.isEmpty
            ? '未知'
            : '${info.version} (${info.buildNumber})';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _version = '未知');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('关于')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 16),
          Center(
            child: Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                Icons.checkroom_rounded,
                size: 48,
                color: AppTheme.primaryColor,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              '穿啥',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Center(
            child: Text(
              '版本 $_version',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppTheme.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: 32),

          _row(
            context,
            '简介',
            '智能衣橱管理 App：拍照录入衣物、自动抠图归类，'
                '根据天气帮你决定今天穿什么。',
          ),
          const SizedBox(height: 20),

          _row(
            context,
            '数据存储',
            '衣物照片与信息保存在 Supabase 云端，'
                '每个账号只能访问自己的数据。',
          ),
          const SizedBox(height: 20),

          _row(
            context,
            '天气服务',
            AppConfig.hasWeatherApiKey
                ? '已配置 OpenWeatherMap'
                : '未配置（推荐页会提示，不会显示假数据）',
          ),
          const SizedBox(height: 32),

          Center(
            child: Text(
              '© 2026 穿啥',
              style: theme.textTheme.labelSmall?.copyWith(
                color: AppTheme.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, String title, String body) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          body,
          style: theme.textTheme.bodySmall?.copyWith(
            color: AppTheme.textSecondary,
            height: 1.6,
          ),
        ),
      ],
    );
  }
}

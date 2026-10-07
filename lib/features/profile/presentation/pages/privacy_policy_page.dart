import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

/// 隐私政策页
///
/// 应用市场（尤其 App Store）上架时要求提供可访问的隐私政策，
/// 并说明收集的数据、用途、存储位置与删除方式。
class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('隐私政策')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            '更新日期：2026 年 10 月',
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: context.textSecondaryColor),
          ),
          const SizedBox(height: 20),

          _section(context, '一、我们收集哪些信息', [
            '账号信息：你注册时提供的邮箱地址，以及你选择的性别（用于展示对应的衣物分类）。',
            '衣物信息：你拍摄或从相册选择的衣物照片，以及你填写的名称、分类、颜色、'
                '季节、风格、品牌、价格等描述。',
            '穿着记录：你在穿搭日历中记录的日期与所穿衣物。',
            '位置信息：在你使用天气与穿搭推荐功能时，用于获取当地天气。'
                '位置只用于查询天气，不会上传到我们自己的服务器存储。',
          ]),

          _section(context, '二、我们如何使用这些信息', [
            '为你展示和管理你的衣橱；',
            '根据当地天气和你的衣橱内容生成穿搭推荐；',
            '统计你的穿着频次与性价比；',
            '在你更换设备后同步你的数据。',
          ]),

          _section(context, '三、信息存储在哪里', [
            '账号、衣物信息与照片存储于 Supabase 提供的云数据库中，'
                '数据传输使用 HTTPS 加密。',
            '每张数据表均启用了行级安全策略（Row Level Security），'
                '你的账号只能读取和修改属于自己的数据，无法访问其他用户的数据。',
          ]),

          _section(context, '四、第三方服务', [
            '天气数据由 OpenWeatherMap 提供。查询天气时，我们会把粗略的地理坐标'
                '发送给该服务，除此之外不发送任何个人身份信息。',
          ]),

          _section(context, '五、你的权利', [
            '查看与修改：你可以随时在「衣橱」中查看和编辑已录入的全部信息。',
            '删除数据：你可以逐件删除衣物与穿搭记录。',
            '注销账号：你可以在「设置」中注销账号，'
                '注销后与你账号关联的衣物、照片、穿搭记录将被一并删除且无法恢复。',
          ]),

          _section(context, '六、权限说明', [
            '相机：用于拍摄衣物照片。',
            '相册：用于从相册选择衣物照片。',
            '位置：用于获取当地天气以生成穿搭推荐。',
            '以上权限均可拒绝，拒绝后对应功能不可用，但不影响其他功能。',
          ]),

          _section(context, '七、联系我们', [
            '如果你对本政策有任何疑问，或需要协助删除数据，'
                '可通过应用内「设置 — 关于」页面提供的方式联系我们。',
          ]),

          const SizedBox(height: 32),
          Center(
            child: Text(
              '© 2026 穿啥',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: context.textSecondaryColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(BuildContext context, String title, List<String> paragraphs) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          ...paragraphs.map(
            (p) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                p,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: context.textSecondaryColor,
                  height: 1.7,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

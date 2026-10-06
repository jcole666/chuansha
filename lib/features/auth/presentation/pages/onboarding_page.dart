import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../../core/theme/app_theme.dart';
import '../../../../../core/constants/routes.dart';
import '../../../../../core/local_store.dart';
import '../../../profile/presentation/pages/privacy_policy_page.dart';

/// 新手引导页
///
/// 首次启动时展示 3 页滑页引导，完成后跳转登录页
/// - 第 1 页：欢迎 + 核心功能介绍
/// - 第 2 页：演示拍照录入流程
/// - 第 3 页：开始使用 → 登录
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final PageController _controller = PageController();
  int _currentPage = 0;

  /// 是否已同意隐私政策（最后一页要求勾选后才能开始使用）
  bool _agreed = false;

  bool get _isLastPage => _currentPage == 2;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // 不展示跳过按钮，必须走完引导 → 登录

            // 滑页内容
            Expanded(
              child: PageView(
                controller: _controller,
                onPageChanged: (page) => setState(() => _currentPage = page),
                children: const [
                  _OnboardingPageView(
                    image: _PageContent(
                      icon: Icons.checkroom_rounded,
                      color: Color(0xFFFF6B6B),
                    ),
                    title: '欢迎来到穿啥',
                    subtitle: '一款智能衣橱管理 App\n让你的每一件衣服都被看见、被记起、被穿出去',
                  ),
                  _OnboardingPageView(
                    image: _PageContent(
                      icon: Icons.add_a_photo_rounded,
                      color: Color(0xFF4ECDC4),
                    ),
                    title: '拍照录入，轻松管理',
                    subtitle: '拍下衣服的照片\nAI 自动抠图去背景\n系统自动帮你整理归类',
                  ),
                  _OnboardingPageView(
                    image: _PageContent(
                      icon: Icons.auto_awesome_rounded,
                      color: Color(0xFF6C63FF),
                    ),
                    title: '开始使用，马上管理衣橱',
                    subtitle: '注册账号后，拍照录入 5 件衣服\n天气推荐功能自动解锁\n根据天气和你的衣橱智能搭配',
                  ),
                ],
              ),
            ),

            // 隐私政策同意（仅最后一页）
            if (_isLastPage)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
                child: Row(
                  children: [
                    Checkbox(
                      value: _agreed,
                      onChanged: (v) => setState(() => _agreed = v ?? false),
                      visualDensity: VisualDensity.compact,
                    ),
                    Expanded(
                      child: Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          const Text('我已阅读并同意', style: TextStyle(fontSize: 13)),
                          GestureDetector(
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const PrivacyPolicyPage(),
                              ),
                            ),
                            child: Text(
                              '《隐私政策》',
                              style: TextStyle(
                                fontSize: 13,
                                color: AppTheme.primaryColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

            // 底部指示器 + 按钮
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
              child: Row(
                children: [
                  // 圆点指示器
                  ...List.generate(3, (index) {
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: _currentPage == index ? 24 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: _currentPage == index
                            ? AppTheme.primaryColor
                            : Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    );
                  }),
                  const Spacer(),

                  // 下一步 / 开始按钮（最后一页需先勾选同意隐私政策）
                  FloatingActionButton(
                    onPressed: (_isLastPage && !_agreed)
                        ? null
                        : () {
                            if (!_isLastPage) {
                              _controller.nextPage(
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeInOut,
                              );
                            } else {
                              _finish();
                            }
                          },
                    backgroundColor: AppTheme.primaryColor,
                    child: Icon(
                      _currentPage < 2 ? Icons.arrow_forward : Icons.check,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _finish() async {
    // 记下「已看过」，下次冷启动不再走引导页
    await LocalStore.setOnboardingSeen();
    if (!mounted) return;
    // 引导结束 → 进入登录页
    context.go(AppRoutes.login);
  }
}

/// 单页引导内容
class _OnboardingPageView extends StatelessWidget {
  final _PageContent image;
  final String title;
  final String subtitle;

  const _OnboardingPageView({
    required this.image,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 图标
          Container(
            width: 160,
            height: 160,
            decoration: BoxDecoration(
              color: image.color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(image.icon, size: 80, color: image.color),
          ),
          const SizedBox(height: 48),

          // 标题
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),

          // 副标题
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: AppTheme.textSecondary,
              height: 1.6,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _PageContent {
  final IconData icon;
  final Color color;

  const _PageContent({required this.icon, required this.color});
}

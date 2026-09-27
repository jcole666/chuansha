import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/theme/app_theme.dart';
import '../../../recommend/presentation/pages/recommend_page.dart';
import 'outfit_list_page.dart';

/// 搭配首页
///
/// 两个 Tab：「今日推荐」|「我的搭配」
/// 推荐功能（天气 + 智能搭配）从原来的独立 Tab 移到这里。
class OutfitHomePage extends ConsumerStatefulWidget {
  const OutfitHomePage({super.key});

  @override
  ConsumerState<OutfitHomePage> createState() => _OutfitHomePageState();
}

class _OutfitHomePageState extends ConsumerState<OutfitHomePage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('搭配'),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppTheme.primaryColor,
          indicatorColor: AppTheme.primaryColor,
          tabs: const [
            Tab(text: '今日推荐'),
            Tab(text: '我的搭配'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          RecommendPage(showAppBar: false),
          OutfitListPage(showAppBar: false),
        ],
      ),
    );
  }
}

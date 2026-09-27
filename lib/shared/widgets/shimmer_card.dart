import 'package:flutter/material.dart';

/// Shimmer 骨架卡片
///
/// 用于列表加载时的占位展示
class ShimmerCard extends StatefulWidget {
  final double height;
  final double? width;
  final EdgeInsetsGeometry? margin;

  const ShimmerCard({
    super.key,
    this.height = 200,
    this.width,
    this.margin,
  });

  @override
  State<ShimmerCard> createState() => _ShimmerCardState();
}

class _ShimmerCardState extends State<ShimmerCard> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _animation = Tween(begin: 0.3, end: 0.7).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          height: widget.height,
          width: widget.width,
          margin: widget.margin ??
              const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.grey.withValues(alpha: _animation.value),
            borderRadius: BorderRadius.circular(12),
          ),
        );
      },
    );
  }
}

/// 骨架网格（网格视图加载）
class ShimmerGrid extends StatelessWidget {
  final int count;
  final int crossAxisCount;

  const ShimmerGrid({
    super.key,
    this.count = 6,
    this.crossAxisCount = 3,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 0.75,
      ),
      itemCount: count,
      itemBuilder: (_, _) => const ShimmerCard(
        height: double.infinity,
        margin: EdgeInsets.zero,
      ),
    );
  }
}

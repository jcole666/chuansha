import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// 衣物图片组件
///
/// 自动识别：
/// - http/https 开头 → 网络图片（带缓存）
/// - 其他 → 本地文件
class ItemImage extends StatelessWidget {
  /// 图片路径或 URL
  final String imageUrl;

  /// 填充方式
  final BoxFit fit;

  /// 宽高
  final double? width;
  final double? height;

  const ItemImage({
    super.key,
    required this.imageUrl,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
  });

  bool get _isNetwork =>
      imageUrl.startsWith('http://') || imageUrl.startsWith('https://');

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      color: Colors.grey.shade200,
      child: const Icon(Icons.checkroom, color: Colors.grey, size: 24),
    );

    if (_isNetwork) {
      return CachedNetworkImage(
        imageUrl: imageUrl,
        fit: fit,
        width: width,
        height: height,
        placeholder: (_, _) => placeholder,
        errorWidget: (_, _, _) => placeholder,
      );
    }

    return Image.file(
      File(imageUrl),
      fit: fit,
      width: width,
      height: height,
      errorBuilder: (_, _, _) => placeholder,
    );
  }
}

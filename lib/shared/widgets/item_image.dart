import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// 衣物图片组件
///
/// 自动识别：
/// - http/https 开头 → 网络图片（带磁盘缓存）
/// - 其他 → 本地文件
///
/// 相比之前：
/// - 占位色改为跟随主题（原来写死浅灰，深色模式下是块白斑）
/// - 支持 [thumbnailWidth]：列表里按缩略尺寸请求与解码，避免加载原图
///   （原图动辄 1080×1440，网格里几十张会明显卡顿且吃内存）
class ItemImage extends StatelessWidget {
  /// 图片路径或 URL
  final String imageUrl;

  /// 填充方式
  final BoxFit fit;

  /// 宽高
  final double? width;
  final double? height;

  /// 缩略图宽度（像素）
  ///
  /// 传入后网络图会请求缩放版本、本地图会按此宽度解码。
  /// 列表/网格建议传（如 300）；详情页大图**不要传**，否则会糊。
  final int? thumbnailWidth;

  const ItemImage({
    super.key,
    required this.imageUrl,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.thumbnailWidth,
  });

  bool get _isNetwork =>
      imageUrl.startsWith('http://') || imageUrl.startsWith('https://');

  @override
  Widget build(BuildContext context) {
    if (_isNetwork) {
      return CachedNetworkImage(
        imageUrl: imageUrl,
        fit: fit,
        width: width,
        height: height,
        memCacheWidth: thumbnailWidth,
        maxWidthDiskCache: thumbnailWidth,
        placeholder: (_, _) => _Placeholder(width: width, height: height),
        errorWidget: (_, _, _) =>
            _Placeholder(width: width, height: height, isError: true),
      );
    }

    return Image.file(
      File(imageUrl),
      fit: fit,
      width: width,
      height: height,
      // 本地文件同样限制解码尺寸，避免大图吃内存
      cacheWidth: thumbnailWidth,
      errorBuilder: (_, _, _) =>
          _Placeholder(width: width, height: height, isError: true),
    );
  }
}

/// 占位块：加载中 / 加载失败
class _Placeholder extends StatelessWidget {
  final double? width;
  final double? height;
  final bool isError;

  const _Placeholder({this.width, this.height, this.isError = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      color: context.subtleFillColor,
      alignment: Alignment.center,
      child: Icon(
        isError ? Icons.broken_image_outlined : Icons.checkroom,
        color: context.textHintColor,
        size: 24,
      ),
    );
  }
}

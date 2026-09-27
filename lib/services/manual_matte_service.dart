import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import 'matte_blend.dart';
import 'matte_geometry.dart';

/// 手动抠图服务：按用户手指描出的闭合轮廓裁出衣服，背景填白。
///
/// 与自动抠图（[MattingService]）互补 —— 自动抠图靠颜色相似度猜背景，
/// 遇到花地板 / 衣服摞一起 / 浅色衣服就废了；手动抠图由用户明确指定轮廓，
/// 结果可控。
///
/// 坐标约定：[polygons] 里每个 Offset 是**归一化坐标**（dx/dy ∈ 0~1，
/// 相对原图宽高），UI 层不用关心图片实际像素尺寸。
class ManualMatteService {
  /// 处理时的最长边上限（比自动抠图高一些，保证手动描边的精度）
  static const int _maxDim = 1600;

  /// 按轮廓裁出白底图。
  ///
  /// [polygons] 一条 = 一个闭合轮廓；可以描多条，结果取并集
  /// （比如袖子和主体没连上时分开描）。
  /// [snapToEdge] 是否把描边点吸附到图像梯度最强处，让轮廓自动贴边。
  Future<File> cutOut({
    required File imageFile,
    required List<List<Offset>> polygons,
    bool snapToEdge = true,
  }) async {
    final valid = polygons.where((p) => p.length >= 3).toList(growable: false);
    if (valid.isEmpty) {
      throw const ManualMatteException('还没有描出完整的轮廓');
    }

    final original = img.decodeImage(imageFile.readAsBytesSync());
    if (original == null) throw Exception('无法解析图片');

    final scale = _computeScale(original.width, original.height);
    final working = (scale < 1.0)
        ? img.copyResize(
            original,
            width: (original.width * scale).round(),
            height: (original.height * scale).round(),
            interpolation: img.Interpolation.linear,
          )
        : original;

    final w = working.width;
    final h = working.height;
    final bytes = working.getBytes(order: img.ChannelOrder.rgba);

    // 边缘吸附用的梯度图
    Float32List? grad;
    var minGrad = 0.0;
    var radius = 0;
    if (snapToEdge) {
      grad = sobelGradient(bytes, w, h);
      var sum = 0.0;
      for (var i = 0; i < grad.length; i++) {
        sum += grad[i];
      }
      minGrad = math.max(18.0, (sum / grad.length) * 1.5);
      radius = math.max(4, math.min(w, h) ~/ 150);
    }

    final keep = Uint8List(w * h); // 1 = 保留
    final scratch = Uint8List(w * h);

    for (final poly in valid) {
      // 归一化坐标 → 像素坐标
      final pts = <MattePoint>[];
      for (final o in poly) {
        var p = MattePoint(o.dx * w, o.dy * h);
        if (grad != null) {
          p = snapPointToEdge(p, grad, w, h, radius, minGrad);
        }
        pts.add(p);
      }

      scratch.fillRange(0, scratch.length, 0);
      rasterizePolygon(scratch, w, h, smoothPath(pts));
      for (var i = 0; i < keep.length; i++) {
        if (scratch[i] != 0) keep[i] = 1;
      }
    }

    // keep → isBg（被抠掉的部分才是背景）
    final isBg = Uint8List(w * h);
    for (var i = 0; i < isBg.length; i++) {
      isBg[i] = keep[i] == 0 ? 1 : 0;
    }

    final outBytes = compositeOnWhite(bytes, w, h, isBg);

    final outDir = imageFile.parent;
    final outPath =
        '${outDir.path}${Platform.pathSeparator}manual_matte_${DateTime.now().millisecondsSinceEpoch}.png';
    File(outPath).writeAsBytesSync(
      img.encodePng(
        img.Image.fromBytes(
          width: w,
          height: h,
          bytes: outBytes.buffer,
          numChannels: 4,
        ),
      ),
    );
    return File(outPath);
  }

  double _computeScale(int w, int h) {
    final longest = math.max(w, h);
    if (longest <= _maxDim) return 1.0;
    return _maxDim / longest;
  }
}

/// 手动抠图异常（用户可理解的错误，页面直接展示 message）
class ManualMatteException implements Exception {
  final String message;
  const ManualMatteException(this.message);

  @override
  String toString() => message;
}

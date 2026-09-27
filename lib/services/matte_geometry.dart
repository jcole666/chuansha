import 'dart:math' as math;
import 'dart:typed_data';

/// 手动抠图用到的几何 / 图像算法。
///
/// 单独抽出来（不依赖 Flutter），一是职责清晰，
/// 二是扫描线填充这块逻辑可以在纯 Dart 里单测。
///
/// 坐标一律是**像素坐标**（double，保证描边平滑）。

/// 像素坐标点
class MattePoint {
  final double x, y;
  const MattePoint(this.x, this.y);
}

/// 扫描线填充多边形（even-odd 规则），把内部像素标记为 1。
///
/// [mask] 长度 w*h，会被写入（不负责清零，多条轮廓由调用方自行 OR 合并）。
void rasterizePolygon(Uint8List mask, int w, int h, List<MattePoint> pts) {
  final n = pts.length;
  if (n < 3) return;

  var minY = double.infinity;
  var maxY = double.negativeInfinity;
  for (final p in pts) {
    if (p.y < minY) minY = p.y;
    if (p.y > maxY) maxY = p.y;
  }
  final y0 = math.max(0, minY.floor());
  final y1 = math.min(h - 1, maxY.ceil());

  final xs = <double>[];
  for (var y = y0; y <= y1; y++) {
    // 取像素中心，避免顶点处的重复计数；
    // 最后一行可能整体越过 maxY，钳回来，否则底边会漏掉一条扫描线。
    var sy = y + 0.5;
    if (sy >= maxY) sy = maxY - 0.001;
    xs.clear();
    for (var i = 0; i < n; i++) {
      final a = pts[i];
      final b = pts[(i + 1) % n];
      if (a.y == b.y) continue;
      if ((sy >= a.y && sy < b.y) || (sy >= b.y && sy < a.y)) {
        final t = (sy - a.y) / (b.y - a.y);
        xs.add(a.x + t * (b.x - a.x));
      }
    }
    if (xs.length < 2) continue;
    xs.sort();
    for (var k = 0; k + 1 < xs.length; k += 2) {
      var x0 = xs[k].ceil();
      var x1 = xs[k + 1].floor();
      if (x0 < 0) x0 = 0;
      if (x1 >= w) x1 = w - 1;
      for (var x = x0; x <= x1; x++) {
        mask[y * w + x] = 1;
      }
    }
  }
}

/// 三点移动平均，抹掉手指抖动产生的锯齿点
List<MattePoint> smoothPath(List<MattePoint> pts) {
  if (pts.length < 3) return pts;
  final out = <MattePoint>[pts.first];
  for (var i = 1; i < pts.length - 1; i++) {
    out.add(
      MattePoint(
        (pts[i - 1].x + pts[i].x + pts[i + 1].x) / 3,
        (pts[i - 1].y + pts[i].y + pts[i + 1].y) / 3,
      ),
    );
  }
  out.add(pts.last);
  return out;
}

/// Sobel 梯度幅值图（灰度）
Float32List sobelGradient(Uint8List bytes, int w, int h) {
  final gray = Float32List(w * h);
  for (var i = 0; i < gray.length; i++) {
    final base = i * 4;
    gray[i] =
        0.299 * bytes[base] + 0.587 * bytes[base + 1] + 0.114 * bytes[base + 2];
  }

  final grad = Float32List(w * h);
  for (var y = 1; y < h - 1; y++) {
    final row = y * w;
    for (var x = 1; x < w - 1; x++) {
      final i = row + x;
      final gx =
          -gray[i - w - 1] -
          2 * gray[i - 1] -
          gray[i + w - 1] +
          gray[i - w + 1] +
          2 * gray[i + 1] +
          gray[i + w + 1];
      final gy =
          -gray[i - w - 1] -
          2 * gray[i - w] -
          gray[i - w + 1] +
          gray[i + w - 1] +
          2 * gray[i + w] +
          gray[i + w + 1];
      grad[i] = math.sqrt(gx * gx + gy * gy);
    }
  }
  return grad;
}

/// 把点吸附到附近梯度最强处（让描边自动贴到衣服边缘）
///
/// 只在 [radius] 半径内搜索并带距离惩罚；
/// 梯度达不到 [minGrad] 就保持原点不动，避免在平坦背景上乱跑。
MattePoint snapPointToEdge(
  MattePoint p,
  Float32List grad,
  int w,
  int h,
  int radius,
  double minGrad,
) {
  var bestX = p.x;
  var bestY = p.y;
  var bestScore = 0.0;
  final cx = p.x.round();
  final cy = p.y.round();
  final r = radius.toDouble();

  for (var dy = -radius; dy <= radius; dy++) {
    final yy = cy + dy;
    if (yy < 0 || yy >= h) continue;
    for (var dx = -radius; dx <= radius; dx++) {
      final xx = cx + dx;
      if (xx < 0 || xx >= w) continue;
      final d = math.sqrt((dx * dx + dy * dy).toDouble());
      if (d > r) continue;
      final score = grad[yy * w + xx] * (1.0 - 0.5 * d / (r + 1));
      if (score > bestScore) {
        bestScore = score;
        bestX = xx.toDouble();
        bestY = yy.toDouble();
      }
    }
  }

  if (bestScore < minGrad) return p;
  return MattePoint(bestX, bestY);
}

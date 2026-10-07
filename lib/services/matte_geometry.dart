import 'dart:math' as math;
import 'dart:typed_data';

/// 手动抠图用到的几何 / 图像算法。
///
/// 单独抽出来（不依赖 Flutter），一是职责清晰，
/// 二是扫描线填充 / 磁性套索这块逻辑可以在纯 Dart 里单测。
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
///
/// 注意：[bytes] 必须是 **RGBA** 像素数据（每像素 4 字节），
/// 不是单通道灰度数组 —— 长度应为 `w * h * 4`，
/// 否则会越界抛 RangeError。内部按 0.299/0.587/0.114 转灰度。
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

/// 把梯度图转成「强边缘」掩码：梯度 > [threshold] 的像素为 1。
Uint8List strongEdges(Float32List grad, double threshold) {
  final out = Uint8List(grad.length);
  for (var i = 0; i < grad.length; i++) {
    if (grad[i] > threshold) out[i] = 1;
  }
  return out;
}

/// 从「强边缘」掩码生成距离变换图。
///
/// [feature] 非 0 表示该像素是强边缘。返回每个像素到最近强边缘的
/// **近似像素距离**（0 = 就在边缘上，越大越远离边缘）。用
/// [maxRounds] 限制传播轮数，超出的一律记为该上限，够用即可。
Float32List distanceToFeature(Uint8List feature, int w, int h, int maxRounds) {
  final dist = Float32List(w * h);
  final reached = Uint8List(w * h);
  var frontier = <int>[];
  for (var i = 0; i < feature.length; i++) {
    if (feature[i] != 0) {
      reached[i] = 1;
      dist[i] = 0;
      frontier.add(i);
    }
  }
  var round = 0;
  while (frontier.isNotEmpty && round < maxRounds) {
    final next = <int>[];
    for (final idx in frontier) {
      final x = idx % w;
      final y = idx ~/ w;
      final nd = dist[idx] + 1;
      if (x > 0) {
        final n = idx - 1;
        if (reached[n] == 0) {
          reached[n] = 1;
          dist[n] = nd;
          next.add(n);
        }
      }
      if (x < w - 1) {
        final n = idx + 1;
        if (reached[n] == 0) {
          reached[n] = 1;
          dist[n] = nd;
          next.add(n);
        }
      }
      if (y > 0) {
        final n = idx - w;
        if (reached[n] == 0) {
          reached[n] = 1;
          dist[n] = nd;
          next.add(n);
        }
      }
      if (y < h - 1) {
        final n = idx + w;
        if (reached[n] == 0) {
          reached[n] = 1;
          dist[n] = nd;
          next.add(n);
        }
      }
    }
    frontier = next;
    round++;
  }
  // 从未到达的像素（离所有边缘都超过 maxRounds）记上限
  for (var i = 0; i < dist.length; i++) {
    if (reached[i] == 0) dist[i] = maxRounds.toDouble();
  }
  return dist;
}

/// 二值掩码的边界点集合（4-邻域内既有 1 又有 0 的像素）。
Uint8List maskBoundary(Uint8List mask, int w, int h) {
  final out = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    final row = y * w;
    for (var x = 0; x < w; x++) {
      final idx = row + x;
      final v = mask[idx];
      final l = x > 0 ? mask[idx - 1] : v;
      final r = x < w - 1 ? mask[idx + 1] : v;
      final u = y > 0 ? mask[idx - w] : v;
      final d = y < h - 1 ? mask[idx + w] : v;
      if (v != l || v != r || v != u || v != d) out[idx] = 1;
    }
  }
  return out;
}

/// 磁性套索（Livewire / 智能剪刀）核心：从 [seed] 到 [goal] 求总代价最小的路径。
///
/// 这是 Photoshop「磁性套索」真正用的算法简化版 —— 在代价图上跑
/// **Dijkstra 最短路**，而不是每步贪心。贪心版（每步只看一圈邻域）
/// 到了边缘上会在几个点之间来回抖（因为边缘上所有点的"贴边代价"都是 0，
/// 没有全局信息决定往哪走）；最短路则天然会沿着边缘一路走到底。
///
/// 代价设计：
///   单步代价 = 步长 × ([edgeDist] 在该点的值 + [flatCost])
///   - 贴边的像素 edgeDist ≈ 0 → 走起来便宜 → 路径自然吸在边缘上
///   - 平坦区 edgeDist 很大，但被 [flatCost] 兜底（默认 0.5），
///     所以**不会**为了找边缘而绕远路：平坦区里"抄近道走直线"更划算，
///     与 PS 在无边缘区域自动走直线的行为一致
///
/// [edgeDist] 由 [distanceToFeature] 生成（0 = 就在强边缘上）。
/// 返回从 seed 到 goal 的像素点序列（含两端）；不可达时退化成 [seed, goal]。
List<MattePoint> livewirePath({
  required MattePoint seed,
  required MattePoint goal,
  required Float32List edgeDist,
  required int w,
  required int h,
  double flatCost = 0.5,
}) {
  final sx = seed.x.round().clamp(0, w - 1);
  final sy = seed.y.round().clamp(0, h - 1);
  final gx = goal.x.round().clamp(0, w - 1);
  final gy = goal.y.round().clamp(0, h - 1);

  final startIdx = sy * w + sx;
  final goalIdx = gy * w + gx;
  if (startIdx == goalIdx) return [seed, goal];

  const dxs = [-1, 0, 1, -1, 1, -1, 0, 1];
  const dys = [-1, -1, -1, 0, 0, 1, 1, 1];
  const diag = 1.41421356;

  final dist = Float32List(w * h)..fillRange(0, w * h, double.infinity);
  final prev = Int32List(w * h)..fillRange(0, w * h, -1);
  dist[startIdx] = 0;

  // 手写二叉最小堆（并行两个数组存 cost / index），避免引入 collection 依赖。
  final heapCost = <double>[0];
  final heapIdx = <int>[startIdx];

  void push(double c, int idx) {
    heapCost.add(c);
    heapIdx.add(idx);
    var i = heapCost.length - 1;
    while (i > 0) {
      final p = (i - 1) >> 1;
      if (heapCost[p] <= heapCost[i]) break;
      final tc = heapCost[p];
      heapCost[p] = heapCost[i];
      heapCost[i] = tc;
      final ti = heapIdx[p];
      heapIdx[p] = heapIdx[i];
      heapIdx[i] = ti;
      i = p;
    }
  }

  bool popInto(void Function(double cost, int idx) sink) {
    if (heapCost.isEmpty) return false;
    sink(heapCost[0], heapIdx[0]);
    final lastC = heapCost.removeLast();
    final lastI = heapIdx.removeLast();
    if (heapCost.isNotEmpty) {
      heapCost[0] = lastC;
      heapIdx[0] = lastI;
      var i = 0;
      final n = heapCost.length;
      while (true) {
        final l = 2 * i + 1;
        final r = 2 * i + 2;
        var m = i;
        if (l < n && heapCost[l] < heapCost[m]) m = l;
        if (r < n && heapCost[r] < heapCost[m]) m = r;
        if (m == i) break;
        final tc = heapCost[m];
        heapCost[m] = heapCost[i];
        heapCost[i] = tc;
        final ti = heapIdx[m];
        heapIdx[m] = heapIdx[i];
        heapIdx[i] = ti;
        i = m;
      }
    }
    return true;
  }

  var done = false;
  while (!done) {
    done = !popInto((c, idx) {
      if (c > dist[idx]) return; // 过期条目
      if (idx == goalIdx) return;

      final x = idx % w;
      final y = idx ~/ w;
      for (var k = 0; k < 8; k++) {
        final nx = x + dxs[k];
        final ny = y + dys[k];
        if (nx < 0 || nx >= w || ny < 0 || ny >= h) continue;
        final ni = ny * w + nx;
        final w2 = (dxs[k] != 0 && dys[k] != 0) ? diag : 1.0;
        final step = w2 * (edgeDist[ni] + flatCost);
        final nd = c + step;
        if (nd < dist[ni]) {
          dist[ni] = nd;
          prev[ni] = idx;
          push(nd, ni);
        }
      }
    });
  }

  if (prev[goalIdx] == -1) return [seed, goal];

  final path = <MattePoint>[];
  var cur = goalIdx;
  while (cur != -1) {
    path.add(MattePoint((cur % w).toDouble(), (cur ~/ w).toDouble()));
    if (cur == startIdx) break;
    cur = prev[cur];
  }
  return path.reversed.toList();
}

/// 沿路径按最大间距重采样，避免点过密或过疏。
List<MattePoint> resamplePath(List<MattePoint> pts, double maxGap) {
  if (pts.length < 2) return pts;
  final out = <MattePoint>[pts.first];
  for (var i = 1; i < pts.length; i++) {
    final a = out.last;
    final b = pts[i];
    final dx = b.x - a.x;
    final dy = b.y - a.y;
    final d = math.sqrt(dx * dx + dy * dy);
    if (d <= maxGap || d <= 1e-6) {
      out.add(b);
      continue;
    }
    final n = (d / maxGap).ceil();
    for (var k = 1; k <= n; k++) {
      final t = k / n;
      out.add(MattePoint(a.x + dx * t, a.y + dy * t));
    }
  }
  return out;
}

/// 多边形面积（鞋带公式，像素坐标）。用于判断闭合圈是否够大。
double polygonArea(List<MattePoint> pts) {
  if (pts.length < 3) return 0;
  var sum = 0.0;
  for (var i = 0; i < pts.length; i++) {
    final a = pts[i];
    final b = pts[(i + 1) % pts.length];
    sum += a.x * b.y - b.x * a.y;
  }
  return sum.abs() / 2;
}

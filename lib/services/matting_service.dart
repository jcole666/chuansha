import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'matte_blend.dart';

/// 纯算法抠图服务：把衣服从照片背景中分离出来，背景填充白色。
///
/// 流程（洪水填充 + 后处理）：
/// 1. 采样照片四边带状区域，用「众数分桶」估计背景基准色
///    （比全边取平均稳健：衣服贴边或占据画面大半时也不会被拉偏）
/// 2. 从四边向内 BFS，把与基准色相近且连通的像素标记为背景
/// 3. 自适应容差：背景占比异常时自动收紧/放宽，
///    避免「整件衣服被抠掉」或「完全没抠动」
/// 4. 形态学闭运算填掉噪点 → 连通域分析丢掉小碎片
/// 5. 边缘收缩：把仍接近背景色的边缘前景并入背景
///    （判据是「像背景」而不是「接近白色」，浅色衣服边缘不会被吃掉）
/// 6. 合成白底图，边界像素按比例与白色混合做抗锯齿
///
/// 使用建议：纯色背景（白墙/床单/地板）效果最好。
/// 复杂背景建议直接用「手动抠图」（ManualMattePage）。
class MattingService {
  /// 颜色容差：与背景基准色的 RGB 距离小于该值视为背景（0~255）
  final int tolerance;

  /// 边缘收缩轮数（像素）
  final int featherRadius;

  MattingService({this.tolerance = 40, this.featherRadius = 2});

  /// 处理时的最长边上限
  static const int _maxDim = 1024;

  /// 把照片抠图成白底衣物图，返回新的图片文件（PNG）。
  Future<File> removeBackground(File imageFile) async {
    final original = img.decodeImage(imageFile.readAsBytesSync());
    if (original == null) throw Exception('无法解析图片');

    // 1. 缩放到最长边 1024，加快处理速度
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

    // 2. 背景基准色（众数分桶）
    final bg = _estimateBackground(bytes, w, h);

    // 3. 洪水填充 + 容差自适应
    var tol = tolerance;
    var isBg = _floodFill(bytes, w, h, bg, tol);
    var ratio = _bgRatio(isBg);

    // 背景占比过高 = 衣服几乎被吃光 → 收紧容差重试
    var guard = 0;
    while (ratio > 0.96 && tol > 8 && guard++ < 6) {
      tol = (tol * 0.6).round();
      if (tol < 8) tol = 8;
      isBg = _floodFill(bytes, w, h, bg, tol);
      ratio = _bgRatio(isBg);
    }
    // 背景占比过低 = 背景根本没被识别 → 放宽容差重试
    guard = 0;
    while (ratio < 0.02 && tol < 140 && guard++ < 6) {
      tol = (tol * 1.7).round();
      if (tol > 140) tol = 140;
      isBg = _floodFill(bytes, w, h, bg, tol);
      ratio = _bgRatio(isBg);
    }

    // 几乎整张图都被判成背景 = 四边采到的其实是衣服颜色，没有真正的背景可参照。
    // 与其把整件衣服抠没，不如明确失败、引导用户用手动抠图。
    if (ratio > 0.985) {
      throw const MattingException('没检测到背景（衣服可能占满了画面），请用「手动抠图」描出轮廓');
    }

    // 4. 闭运算（膨胀→腐蚀）：填掉背景里残留的孤立前景噪点
    isBg = _erode(_dilate(isBg, w, h), w, h);

    // 5. 丢掉远离主体的小前景碎片
    isBg = _dropSmallForeground(isBg, w, h);

    // 6. 边缘收缩
    isBg = _shrinkEdge(bytes, w, h, isBg, bg, featherRadius, tol);

    // 7. 合成白底图
    final outBytes = compositeOnWhite(bytes, w, h, isBg);

    final outDir = imageFile.parent;
    final outPath =
        '${outDir.path}${Platform.pathSeparator}matte_${DateTime.now().millisecondsSinceEpoch}.png';
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

  /// 计算缩放比例：最长边不超过 [_maxDim]
  double _computeScale(int w, int h) {
    final longest = math.max(w, h);
    if (longest <= _maxDim) return 1.0;
    return _maxDim / longest;
  }

  /// 估计背景基准色。
  ///
  /// 采样四边一圈带状区域，颜色量化到 32 级后分桶，取像素最多的桶求平均。
  _Rgb _estimateBackground(Uint8List bytes, int w, int h) {
    final band = math.max(2, math.min(w, h) ~/ 40); // 带状厚度
    final buckets = <int, _Bucket>{};

    void sample(int x, int y) {
      final base = (y * w + x) * 4;
      final r = bytes[base], g = bytes[base + 1], b = bytes[base + 2];
      // 每通道量化到 32 级，打包成 int key
      final key = ((r >> 3) << 10) | ((g >> 3) << 5) | (b >> 3);
      (buckets[key] ??= _Bucket()).add(r, g, b);
    }

    for (var t = 0; t < band; t++) {
      for (var x = 0; x < w; x++) {
        sample(x, t);
        sample(x, h - 1 - t);
      }
      for (var y = 0; y < h; y++) {
        sample(t, y);
        sample(w - 1 - t, y);
      }
    }

    if (buckets.isEmpty) return const _Rgb(r: 255, g: 255, b: 255);

    var best = buckets.values.first;
    for (final b in buckets.values) {
      if (b.count > best.count) best = b;
    }
    return best.average;
  }

  /// 从四边向内洪水填充，标记「与基准色相近且四边连通」的像素为背景。
  ///
  /// 比较对象是背景基准色而不是邻居像素 —— 深色衣服与背景色差很大，
  /// 不会被一点点渗进去吞掉。
  Uint8List _floodFill(Uint8List bytes, int w, int h, _Rgb bg, int tol) {
    final isBg = Uint8List(w * h);
    final queue = Int32List(w * h * 2); // 每个像素最多入队一次，每次存 x,y
    var head = 0;
    var tail = 0;
    final tol2 = tol * tol;

    void seed(int x, int y) {
      final idx = y * w + x;
      if (isBg[idx] != 0) return;
      isBg[idx] = 1;
      queue[tail++] = x;
      queue[tail++] = y;
    }

    for (var x = 0; x < w; x++) {
      seed(x, 0);
      seed(x, h - 1);
    }
    for (var y = 0; y < h; y++) {
      seed(0, y);
      seed(w - 1, y);
    }

    while (head < tail) {
      final x = queue[head++];
      final y = queue[head++];

      // 左
      if (x > 0) {
        final n = y * w + x - 1;
        if (isBg[n] == 0 && _nearBg(bytes, n * 4, bg, tol2)) {
          isBg[n] = 1;
          queue[tail++] = x - 1;
          queue[tail++] = y;
        }
      }
      // 右
      if (x < w - 1) {
        final n = y * w + x + 1;
        if (isBg[n] == 0 && _nearBg(bytes, n * 4, bg, tol2)) {
          isBg[n] = 1;
          queue[tail++] = x + 1;
          queue[tail++] = y;
        }
      }
      // 上
      if (y > 0) {
        final n = (y - 1) * w + x;
        if (isBg[n] == 0 && _nearBg(bytes, n * 4, bg, tol2)) {
          isBg[n] = 1;
          queue[tail++] = x;
          queue[tail++] = y - 1;
        }
      }
      // 下
      if (y < h - 1) {
        final n = (y + 1) * w + x;
        if (isBg[n] == 0 && _nearBg(bytes, n * 4, bg, tol2)) {
          isBg[n] = 1;
          queue[tail++] = x;
          queue[tail++] = y + 1;
        }
      }
    }
    return isBg;
  }

  /// 某像素是否接近背景基准色（平方距离 <= tol2）
  bool _nearBg(Uint8List bytes, int base, _Rgb bg, int tol2) {
    final dr = bytes[base] - bg.r;
    final dg = bytes[base + 1] - bg.g;
    final db = bytes[base + 2] - bg.b;
    return dr * dr + dg * dg + db * db <= tol2;
  }

  /// 背景像素占比
  double _bgRatio(Uint8List isBg) {
    var n = 0;
    for (var i = 0; i < isBg.length; i++) {
      if (isBg[i] != 0) n++;
    }
    return n / isBg.length;
  }

  /// 膨胀（4-邻域十字结构元）：背景向外扩张一圈
  Uint8List _dilate(Uint8List src, int w, int h) {
    // 水平方向
    final tmp = Uint8List(w * h);
    for (var y = 0; y < h; y++) {
      final row = y * w;
      for (var x = 0; x < w; x++) {
        if (src[row + x] != 0) {
          tmp[row + x] = 1;
          continue;
        }
        final l = x > 0 ? src[row + x - 1] : 0;
        final r = x < w - 1 ? src[row + x + 1] : 0;
        tmp[row + x] = l | r;
      }
    }
    // 垂直方向
    final out = Uint8List(w * h);
    for (var y = 0; y < h; y++) {
      final row = y * w;
      final up = y > 0 ? (y - 1) * w : row;
      final dn = y < h - 1 ? (y + 1) * w : row;
      for (var x = 0; x < w; x++) {
        if (tmp[row + x] != 0) {
          out[row + x] = 1;
          continue;
        }
        out[row + x] = tmp[up + x] | tmp[dn + x];
      }
    }
    return out;
  }

  /// 腐蚀（4-邻域）：背景向内收缩一圈
  Uint8List _erode(Uint8List src, int w, int h) {
    // 水平方向
    final tmp = Uint8List(w * h);
    for (var y = 0; y < h; y++) {
      final row = y * w;
      for (var x = 0; x < w; x++) {
        if (src[row + x] == 0) {
          tmp[row + x] = 0;
          continue;
        }
        final l = x > 0 ? src[row + x - 1] : 0;
        final r = x < w - 1 ? src[row + x + 1] : 0;
        tmp[row + x] = l & r;
      }
    }
    // 垂直方向
    final out = Uint8List(w * h);
    for (var y = 0; y < h; y++) {
      final row = y * w;
      final up = y > 0 ? (y - 1) * w : row;
      final dn = y < h - 1 ? (y + 1) * w : row;
      for (var x = 0; x < w; x++) {
        if (tmp[row + x] == 0) {
          out[row + x] = 0;
          continue;
        }
        out[row + x] = tmp[up + x] & tmp[dn + x];
      }
    }
    return out;
  }

  /// 丢掉面积过小的前景连通域（背景里的碎屑 / 被切断的小块）
  Uint8List _dropSmallForeground(Uint8List isBg, int w, int h) {
    final total = w * h;
    final minArea = math.max(40, (total * 0.0015).round());

    final visited = Uint8List(total);
    final queue = Int32List(total); // 每个像素最多入队一次
    final out = Uint8List.fromList(isBg);

    for (var start = 0; start < total; start++) {
      if (isBg[start] != 0 || visited[start] != 0) continue;

      var head = 0;
      var tail = 0;
      visited[start] = 1;
      queue[tail++] = start;
      final members = <int>[];

      while (head < tail) {
        final idx = queue[head++];
        members.add(idx);
        final x = idx % w;
        final y = idx ~/ w;

        if (x > 0) {
          final n = idx - 1;
          if (isBg[n] == 0 && visited[n] == 0) {
            visited[n] = 1;
            queue[tail++] = n;
          }
        }
        if (x < w - 1) {
          final n = idx + 1;
          if (isBg[n] == 0 && visited[n] == 0) {
            visited[n] = 1;
            queue[tail++] = n;
          }
        }
        if (y > 0) {
          final n = idx - w;
          if (isBg[n] == 0 && visited[n] == 0) {
            visited[n] = 1;
            queue[tail++] = n;
          }
        }
        if (y < h - 1) {
          final n = idx + w;
          if (isBg[n] == 0 && visited[n] == 0) {
            visited[n] = 1;
            queue[tail++] = n;
          }
        }
      }

      if (members.length < minArea) {
        for (final idx in members) {
          out[idx] = 1; // 碎片 → 背景
        }
      }
    }
    return out;
  }

  /// 边缘收缩：把「紧邻背景、且颜色仍接近背景色」的前景像素并入背景。
  ///
  /// 判据是与背景基准色的距离，不是「接近白色」，
  /// 所以米白 / 浅灰的衣物边缘不会被误吃掉。
  Uint8List _shrinkEdge(
    Uint8List bytes,
    int w,
    int h,
    Uint8List isBg,
    _Rgb bg,
    int rounds,
    int tol,
  ) {
    if (rounds <= 0) return isBg;

    final thr = (tol * 1.4).round();
    final thr2 = thr * thr;
    var cur = isBg;

    for (var pass = 0; pass < rounds; pass++) {
      final next = Uint8List.fromList(cur);
      for (var y = 1; y < h - 1; y++) {
        final row = y * w;
        for (var x = 1; x < w - 1; x++) {
          final idx = row + x;
          if (cur[idx] != 0) continue; // 只处理前景
          // 必须紧邻背景才可能是"边缘残留"
          if (cur[idx - 1] == 0 &&
              cur[idx + 1] == 0 &&
              cur[idx - w] == 0 &&
              cur[idx + w] == 0) {
            continue;
          }
          if (_nearBg(bytes, idx * 4, bg, thr2)) next[idx] = 1;
        }
      }
      cur = next;
    }
    return cur;
  }
}

/// 自动抠图异常（用户可理解的错误，页面直接展示 message）
class MattingException implements Exception {
  final String message;
  const MattingException(this.message);

  @override
  String toString() => message;
}

/// 简单 RGB 颜色值
class _Rgb {
  final int r, g, b;
  const _Rgb({required this.r, required this.g, required this.b});
}

/// 颜色分桶统计（用于求背景色的众数）
class _Bucket {
  int count = 0;
  int r = 0, g = 0, b = 0;

  void add(int rr, int gg, int bb) {
    count++;
    r += rr;
    g += gg;
    b += bb;
  }

  _Rgb get average => _Rgb(r: r ~/ count, g: g ~/ count, b: b ~/ count);
}

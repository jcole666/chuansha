import 'dart:typed_data';

/// 把遮罩合成到白底图上（自动抠图 / 手动抠图共用）。
///
/// [bytes] 原图 RGBA 数据，[w]/[h] 尺寸。
/// [isBg] 长度 w*h 的遮罩，非 0 表示该像素是背景。
///
/// 背景直接填白；前景保留原色；**边界像素按 3x3 邻域的前景覆盖率与白色
/// 混合**，做一层轻量抗锯齿，避免硬边锯齿。
Uint8List compositeOnWhite(Uint8List bytes, int w, int h, Uint8List isBg) {
  final out = Uint8List(bytes.length);
  for (var y = 0; y < h; y++) {
    final row = y * w;
    final up = y > 0 ? (y - 1) * w : row;
    final dn = y < h - 1 ? (y + 1) * w : row;
    for (var x = 0; x < w; x++) {
      final idx = row + x;
      final base = idx * 4;

      if (isBg[idx] != 0) {
        out[base] = 255;
        out[base + 1] = 255;
        out[base + 2] = 255;
        out[base + 3] = 255;
        continue;
      }

      // 统计 3x3 邻域里的前景数量 → 覆盖率
      var fg = 0, cnt = 0;
      for (var dy = -1; dy <= 1; dy++) {
        final yy = y + dy;
        if (yy < 0 || yy >= h) continue;
        final r2 = dy == -1 ? up : (dy == 0 ? row : dn);
        for (var dx = -1; dx <= 1; dx++) {
          final xx = x + dx;
          if (xx < 0 || xx >= w) continue;
          cnt++;
          if (isBg[r2 + xx] == 0) fg++;
        }
      }
      final cov = cnt == 0 ? 1.0 : fg / cnt;

      if (cov >= 1.0) {
        out[base] = bytes[base];
        out[base + 1] = bytes[base + 1];
        out[base + 2] = bytes[base + 2];
      } else {
        out[base] = (bytes[base] * cov + 255 * (1 - cov)).round();
        out[base + 1] = (bytes[base + 1] * cov + 255 * (1 - cov)).round();
        out[base + 2] = (bytes[base + 2] * cov + 255 * (1 - cov)).round();
      }
      out[base + 3] = 255;
    }
  }
  return out;
}

/// 按 **连续 alpha** 把前景合成到白底图上（AI 抠图用）。
///
/// 与 [compositeOnWhite] 的区别：那个吃的是二值遮罩（是/否背景），
/// 这个是模型输出的连续 alpha（0 = 全背景，1 = 全前景，中间值 = 半透明边缘），
/// 因此边缘过渡更自然，不需要再靠 3x3 覆盖率近似。
///
/// [alpha] 长度必须是 `w*h`，值域约定 [0,1]（超出会 clamp）。
Uint8List compositeOnWhiteWithAlpha(
  Uint8List bytes,
  int w,
  int h,
  List<double> alpha,
) {
  final out = Uint8List(bytes.length);
  for (var i = 0; i < w * h; i++) {
    final base = i * 4;
    var a = alpha.length > i ? alpha[i] : 1.0;
    if (a < 0) a = 0;
    if (a > 1) a = 1;
    final inv = 1.0 - a;
    out[base] = (bytes[base] * a + 255 * inv).round();
    out[base + 1] = (bytes[base + 1] * a + 255 * inv).round();
    out[base + 2] = (bytes[base + 2] * a + 255 * inv).round();
    out[base + 3] = 255;
  }
  return out;
}

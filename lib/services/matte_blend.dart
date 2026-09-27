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

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:chuansha/core/utils/color_utils.dart';
import 'package:chuansha/data/models/clothing_item.dart';
import 'package:chuansha/data/models/color_info.dart';
import 'package:chuansha/services/matte_blend.dart';
import 'package:chuansha/services/matte_geometry.dart';

/// 手动抠图的几何算法、颜色工具、模型 copyWith 的单元测试
///
/// 这些模块都是纯 Dart（不依赖 Flutter），所以能直接单测。
int _filled(Uint8List m) => m.where((v) => v != 0).length;
int _at(Uint8List m, int w, int x, int y) => m[y * w + x];

/// 左半黑右半白，竖直边缘在 x=4
///
/// 注意是 RGBA（每像素 4 字节），sobelGradient 要求这个格式。
Uint8List _verticalEdge(int w, int h) {
  final b = Uint8List(w * h * 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final v = x < 4 ? 0 : 255;
      final i = (y * w + x) * 4;
      b[i] = v;
      b[i + 1] = v;
      b[i + 2] = v;
      b[i + 3] = 255;
    }
  }
  return b;
}

ClothingItem _item() => ClothingItem(
  id: 'i1',
  userId: 'u1',
  name: '衬衫',
  category: '上衣',
  subCategory: '衬衫',
  brand: '优衣库',
  price: 199,
  imageUrl: 'https://example.com/1.png',
  colors: const [ColorInfo(name: '白', hex: '#FFFFFF')],
  createdAt: DateTime.now(),
);

void main() {
  group('rasterizePolygon 扫描线填充', () {
    test('矩形：内部填充、外部不填充', () {
      const w = 10, h = 10;
      final m = Uint8List(w * h);
      rasterizePolygon(m, w, h, const [
        MattePoint(2, 2),
        MattePoint(7, 2),
        MattePoint(7, 7),
        MattePoint(2, 7),
      ]);
      expect(_at(m, w, 5, 5), isNot(0));
      expect(_at(m, w, 0, 0), 0);
      expect(_at(m, w, 9, 9), 0);
      expect(_filled(m), inInclusiveRange(16, 36));
    });

    test('L 形：凹口不被误填', () {
      const w = 10, h = 10;
      final m = Uint8List(w * h);
      rasterizePolygon(m, w, h, const [
        MattePoint(1, 1),
        MattePoint(8, 1),
        MattePoint(8, 4),
        MattePoint(4, 4),
        MattePoint(4, 8),
        MattePoint(1, 8),
      ]);
      expect(_at(m, w, 2, 2), isNot(0), reason: '横条内部');
      expect(_at(m, w, 2, 6), isNot(0), reason: '竖条内部');
      expect(_at(m, w, 6, 6), 0, reason: '凹口应留空');
    });

    test('点数不足 3 时不写入', () {
      const w = 5, h = 5;
      final m = Uint8List(w * h);
      rasterizePolygon(m, w, h, const [MattePoint(1, 1), MattePoint(3, 3)]);
      expect(_filled(m), 0);
    });
  });

  group('smoothPath 平滑', () {
    test('点数不变且不过度变形', () {
      const jagged = [
        MattePoint(0, 0),
        MattePoint(10, 0),
        MattePoint(10, 1),
        MattePoint(0, 1),
        MattePoint(0, 2),
        MattePoint(10, 2),
      ];
      final s = smoothPath(jagged);
      expect(s.length, jagged.length);
      expect(
        s.every((p) => p.x >= -2 && p.x <= 12 && p.y >= -2 && p.y <= 4),
        isTrue,
      );
    });
  });

  group('sobelGradient 边缘检测', () {
    test('输出长度等于 w*h', () {
      const w = 8, h = 8;
      final g = sobelGradient(_verticalEdge(w, h), w, h);
      expect(g.length, w * h);
    });

    test('边缘处梯度显著高于平坦区', () {
      const w = 8, h = 8;
      final g = sobelGradient(_verticalEdge(w, h), w, h);
      var edgeMax = 0.0;
      for (var y = 1; y < h - 1; y++) {
        for (var x = 3; x <= 4; x++) {
          if (g[y * w + x] > edgeMax) edgeMax = g[y * w + x];
        }
      }
      final flat = g[1 * w + 1].abs();
      expect(edgeMax, greaterThan(flat + 1));
      expect(edgeMax, greaterThan(100));
    });
  });

  group('snapPointToEdge 边缘吸附', () {
    test('靠近边缘的点被拉回边缘', () {
      const w = 8, h = 8;
      final g = sobelGradient(_verticalEdge(w, h), w, h);
      final snapped = snapPointToEdge(const MattePoint(4.8, 4), g, w, h, 3, 10);
      expect((snapped.x - 4).abs(), lessThan(0.8));
      expect((snapped.y - 4).abs(), lessThanOrEqualTo(1.0));
    });

    test('平坦区域保持原位（不乱跑）', () {
      const w = 8, h = 8;
      final flat = Uint8List(w * h * 4)..fillRange(0, w * h * 4, 128);
      final g = sobelGradient(flat, w, h);
      final p = snapPointToEdge(const MattePoint(3, 3), g, w, h, 3, 10);
      expect(p.x, 3);
      expect(p.y, 3);
    });
  });

  group('ColorUtils', () {
    test('hexToRgb 解析', () {
      expect(ColorUtils.hexToRgb('#FF8000'), [255, 128, 0]);
      expect(ColorUtils.hexToRgb('00FF00'), [0, 255, 0]);
    });

    test('hueDifference 取值合理', () {
      expect(ColorUtils.hueDifference('#FF0000', '#FF0000'), 0);
      expect(ColorUtils.hueDifference('#FF0000', '#00FFFF'), greaterThan(150));
      for (final pair in [('#FF0000', '#0000FF'), ('#00FF00', '#FF00FF')]) {
        final d = ColorUtils.hueDifference(pair.$1, pair.$2);
        expect(d, inInclusiveRange(0, 180));
      }
    });
  });

  group('ClothingItem.copyWith 置空', () {
    test('clearXxx 把可空字段置为 null', () {
      final item = _item();
      expect(item.copyWith(clearBrand: true).brand, isNull);
      expect(item.copyWith(clearPrice: true).price, isNull);
      expect(item.copyWith(clearSubCategory: true).subCategory, isNull);
    });

    test('不传 clear 时保留原值（回归）', () {
      final item = _item();
      final renamed = item.copyWith(name: '新名字');
      expect(renamed.brand, '优衣库');
      expect(renamed.price, 199);
      expect(renamed.name, '新名字');
      expect(renamed.category, '上衣');
      expect(renamed.id, 'i1');
    });

    test('显式传 null 不等于清空（这正是引入 clearXxx 的原因）', () {
      final item = _item();
      expect(item.copyWith(brand: null).brand, '优衣库');
    });

    test('clear 优先于同时传入的值', () {
      final item = _item();
      expect(item.copyWith(brand: 'ZARA', clearBrand: true).brand, isNull);
    });
  });

  group('strongEdges 强边缘掩码', () {
    test('梯度超阈值标 1，其余标 0', () {
      final grad = Float32List.fromList([0, 5, 10, 50, 100]);
      final mask = strongEdges(grad, 20);
      expect(mask.length, 5);
      expect(mask[0], 0);
      expect(mask[1], 0);
      expect(mask[2], 0);
      expect(mask[3], 1);
      expect(mask[4], 1);
    });

    test('阈值大于所有梯度时全 0', () {
      final grad = Float32List.fromList([1, 2, 3]);
      expect(_filled(strongEdges(grad, 100)), 0);
    });
  });

  group('distanceToFeature 距离场', () {
    test('边缘点距离为 0，相邻点距离为 1', () {
      const w = 5, h = 5;
      final feature = Uint8List(w * h);
      feature[2 * w + 2] = 1; // 正中心是边缘
      final dist = distanceToFeature(feature, w, h, 10);
      expect(dist[2 * w + 2], 0);
      expect(dist[2 * w + 3], 1); // 右边一格
      expect(dist[2 * w + 1], 1); // 左边一格
      expect(dist[1 * w + 2], 1); // 上一格
    });

    test('曼哈顿距离：对角线方向 = 2', () {
      const w = 5, h = 5;
      final feature = Uint8List(w * h);
      feature[0] = 1; // 左上角
      final dist = distanceToFeature(feature, w, h, 10);
      expect(dist[1 * w + 1], 2); // (1,1) 需两步（4-邻域）
    });

    test('超出 maxRounds 的像素被记为上限值', () {
      const w = 20, h = 20;
      final feature = Uint8List(w * h);
      feature[0] = 1;
      final dist = distanceToFeature(feature, w, h, 3);
      // (19,19) 曼哈顿距离 38 > 3 → 记上限 3
      expect(dist[19 * w + 19], 3);
    });

    test('没有边缘时全部为上限', () {
      const w = 4, h = 4;
      final dist = distanceToFeature(Uint8List(w * h), w, h, 5);
      expect(dist.every((v) => v == 5), isTrue);
    });
  });

  group('livewirePath 磁性套索最短路', () {
    // 造一个水平强边缘带：y = 5 那一行是边缘
    Float32List _horizontalEdgeDist(int w, int h) {
      final feature = Uint8List(w * h);
      for (var x = 0; x < w; x++) {
        feature[5 * w + x] = 1;
      }
      return distanceToFeature(feature, w, h, 20);
    }

    test('起终点同点：直接返回两点', () {
      final ed = _horizontalEdgeDist(20, 12);
      final path = livewirePath(
        seed: const MattePoint(3, 5),
        goal: const MattePoint(3, 5),
        edgeDist: ed,
        w: 20,
        h: 12,
      );
      expect(path.length, 2);
    });

    test('沿边缘走：路径绝大部分点都在边缘行附近', () {
      const w = 24, h = 12;
      final ed = _horizontalEdgeDist(w, h);
      final path = livewirePath(
        seed: const MattePoint(2, 5),
        goal: const MattePoint(21, 5),
        edgeDist: ed,
        w: w,
        h: h,
      );
      expect(path.length, greaterThan(2));
      // 至少 80% 的点 y 坐标落在 4..6 区间
      final onEdge = path.where((p) => p.y >= 4 && p.y <= 6).length;
      expect(onEdge / path.length, greaterThan(0.8));
    });

    test('平坦区走直线：水平直线路径的 y 不应乱飘', () {
      const w = 30, h = 30;
      // 全平坦：没有任何强边缘
      final ed = distanceToFeature(Uint8List(w * h), w, h, 45);
      final path = livewirePath(
        seed: const MattePoint(2, 15),
        goal: const MattePoint(27, 15),
        edgeDist: ed,
        w: w,
        h: h,
      );
      expect(path.length, greaterThan(2));
      // 端点精确
      expect(path.first.x, closeTo(2, 1));
      expect(path.first.y, closeTo(15, 1));
      expect(path.last.x, closeTo(27, 1));
      expect(path.last.y, closeTo(15, 1));
      // 所有点都应贴近 y=15（允许 1px 抖动）
      final maxDev = path
          .map((p) => (p.y - 15).abs())
          .reduce((a, b) => a > b ? a : b);
      expect(maxDev, lessThanOrEqualTo(1.0));
    });

    test('路径首尾与请求的点一致', () {
      const w = 20, h = 20;
      final ed = _horizontalEdgeDist(w, 20);
      final path = livewirePath(
        seed: const MattePoint(1, 1),
        goal: const MattePoint(18, 18),
        edgeDist: ed,
        w: w,
        h: h,
      );
      expect(path.first.x, closeTo(1, 1.5));
      expect(path.first.y, closeTo(1, 1.5));
      expect(path.last.x, closeTo(18, 1.5));
      expect(path.last.y, closeTo(18, 1.5));
    });

    test('越界的起终点被钳制而不崩', () {
      const w = 10, h = 10;
      final ed = _horizontalEdgeDist(w, h);
      final path = livewirePath(
        seed: const MattePoint(-5, -5),
        goal: const MattePoint(99, 99),
        edgeDist: ed,
        w: w,
        h: h,
      );
      expect(path, isNotEmpty);
    });
  });

  group('resamplePath 重采样', () {
    test('间距过大的路径被插入中间点', () {
      final pts = [const MattePoint(0, 0), const MattePoint(10, 0)];
      final out = resamplePath(pts, 2);
      expect(out.length, greaterThan(2));
      // 相邻点间距不应超过 2
      for (var i = 1; i < out.length; i++) {
        final d = (out[i].x - out[i - 1].x).abs();
        expect(d, lessThanOrEqualTo(2.0001));
      }
    });

    test('已经足够密的路径基本不变', () {
      final pts = [
        const MattePoint(0, 0),
        const MattePoint(1, 0),
        const MattePoint(2, 0),
      ];
      final out = resamplePath(pts, 5);
      expect(out.length, 3);
    });

    test('单点路径原样返回', () {
      final pts = [const MattePoint(1, 1)];
      expect(resamplePath(pts, 2).length, 1);
    });
  });

  group('polygonArea 多边形面积', () {
    test('矩形面积正确', () {
      final pts = [
        const MattePoint(0, 0),
        const MattePoint(4, 0),
        const MattePoint(4, 3),
        const MattePoint(0, 3),
      ];
      expect(polygonArea(pts), closeTo(12, 1e-9));
    });

    test('顶点顺序不影响面积（取绝对值）', () {
      final cw = [
        const MattePoint(0, 0),
        const MattePoint(4, 0),
        const MattePoint(4, 3),
        const MattePoint(0, 3),
      ];
      final ccw = cw.reversed.toList();
      expect(polygonArea(cw), closeTo(polygonArea(ccw), 1e-9));
    });

    test('点数不足 3 时为 0', () {
      expect(polygonArea([const MattePoint(0, 0)]), 0);
      expect(
        polygonArea([const MattePoint(0, 0), const MattePoint(1, 1)]),
        0,
      );
    });
  });

  group('maskBoundary 掩码边界', () {
    test('实心方块：边界是外圈，内部不是', () {
      const w = 5, h = 5;
      final mask = Uint8List(w * h);
      for (var y = 1; y <= 3; y++) {
        for (var x = 1; x <= 3; x++) {
          mask[y * w + x] = 1;
        }
      }
      final b = maskBoundary(mask, w, h);
      expect(_at(b, w, 1, 1), 1); // 角是边界
      expect(_at(b, w, 2, 1), 1); // 边是边界
      expect(_at(b, w, 2, 2), 0); // 中心不是边界
      expect(_at(b, w, 0, 0), 0); // 全空处不是边界
    });

    test('全空掩码没有边界', () {
      const w = 4, h = 4;
      expect(_filled(maskBoundary(Uint8List(w * h), w, h)), 0);
    });

    test('全满掩码没有边界（内部无 0 邻居）', () {
      const w = 4, h = 4;
      final mask = Uint8List(w * h)..fillRange(0, w * h, 1);
      expect(_filled(maskBoundary(mask, w, h)), 0);
    });
  });

  group('compositeOnWhiteWithAlpha 连续 alpha 白底合成', () {
    test('alpha=1 保留原色', () {
      final src = Uint8List.fromList([10, 20, 30, 255]);
      final out = compositeOnWhiteWithAlpha(src, 1, 1, [1.0]);
      expect(out[0], 10);
      expect(out[1], 20);
      expect(out[2], 30);
      expect(out[3], 255);
    });

    test('alpha=0 变纯白', () {
      final src = Uint8List.fromList([10, 20, 30, 255]);
      final out = compositeOnWhiteWithAlpha(src, 1, 1, [0.0]);
      expect(out[0], 255);
      expect(out[1], 255);
      expect(out[2], 255);
    });

    test('alpha=0.5 半透混合', () {
      final src = Uint8List.fromList([0, 0, 0, 255]);
      final out = compositeOnWhiteWithAlpha(src, 1, 1, [0.5]);
      expect(out[0], closeTo(128, 1));
    });

    test('alpha 超界被 clamp，不溢出', () {
      final src = Uint8List.fromList([0, 0, 0, 255]);
      final hi = compositeOnWhiteWithAlpha(src, 1, 1, [5.0]);
      expect(hi[0], 0);
      final lo = compositeOnWhiteWithAlpha(src, 1, 1, [-3.0]);
      expect(lo[0], 255);
    });

    test('alpha 长度不足时按前景处理，不崩', () {
      final src = Uint8List(2 * 2 * 4);
      final out = compositeOnWhiteWithAlpha(src, 2, 2, [0.5]);
      expect(out.length, 16);
      expect(out[3], 255);
    });
  });
}

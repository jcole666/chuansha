import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:chuansha/core/utils/color_utils.dart';
import 'package:chuansha/data/models/clothing_item.dart';
import 'package:chuansha/data/models/color_info.dart';
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
}

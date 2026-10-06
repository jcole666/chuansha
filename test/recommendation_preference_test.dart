import 'package:flutter_test/flutter_test.dart';

import 'package:chuansha/data/models/clothing_item.dart';
import 'package:chuansha/data/models/color_info.dart';
import 'package:chuansha/data/models/preference_feedback.dart';
import 'package:chuansha/data/models/weather_data.dart';
import 'package:chuansha/services/recommendation_service.dart';

/// 偏好反馈 → 推荐评分的链路测试
///
/// 覆盖：偏好画像聚合、归一化、评分参与、👎 组合剔除、空画像回归。
ClothingItem _item(
  String id,
  String category,
  String sub, {
  List<String> tags = const [],
}) {
  return ClothingItem(
    id: id,
    userId: 'u1',
    name: id,
    category: category,
    subCategory: sub,
    imageUrl: 'https://example.com/$id.png',
    colors: const [ColorInfo(name: '黑', hex: '#000000')],
    styleTags: tags,
    createdAt: DateTime.now(),
  );
}

PreferenceFeedback _fb(List<String> ids, bool liked, {String id = 'f'}) {
  return PreferenceFeedback(
    id: id,
    userId: 'u1',
    itemIds: ids,
    liked: liked,
    createdAt: DateTime.now(),
  );
}

/// 10°C：上衣只允许 卫衣/针织衫/衬衫，下装长裤，鞋运动鞋/靴子，连衣裙被排除
WeatherData _cold() => WeatherData(
  temperature: 10,
  feelsLike: 10,
  conditionCode: 800,
  description: '晴',
  humidity: 50,
  windSpeed: 2,
  cityName: '测试',
  timestamp: DateTime.now(),
);

void main() {
  group('PreferenceProfile 聚合', () {
    final items = [
      _item('t1', '上衣', '针织衫', tags: ['休闲', '简约']),
      _item('b1', '下装', '牛仔长裤', tags: ['休闲']),
      _item('s1', '鞋', '运动鞋', tags: ['休闲']),
      _item('d1', '连衣裙', '连衣裙', tags: ['甜美']),
      _item('d2', '连衣裙', '连衣裙', tags: ['甜美']),
    ];

    test('👍 累加到单品与风格标签', () {
      final p = PreferenceProfile.from(
        feedbacks: [
          _fb(['t1', 'b1', 's1'], true),
        ],
        items: items,
      );
      expect(p.itemScores['t1'], 1);
      expect(p.itemScores['b1'], 1);
      // 休闲：t1 + b1 + s1 各一次
      expect(p.tagScores['休闲'], 3);
      expect(p.tagScores['简约'], 1);
      expect(p.dislikedCombos, isEmpty);
      expect(p.isEmpty, isFalse);
    });

    test('👎 累加为负', () {
      final p = PreferenceProfile.from(
        feedbacks: [
          _fb(['t1'], false),
        ],
        items: items,
      );
      expect(p.itemScore('t1'), lessThan(0));
      expect(p.comboScore([items[0]]), lessThan(0));
      expect(p.dislikedCombos, hasLength(1));
    });

    test('归一化：单次反馈约 1/3，三次饱和', () {
      final once = PreferenceProfile.from(
        feedbacks: [
          _fb(['t1'], true),
        ],
        items: items,
      );
      expect(once.itemScore('t1'), closeTo(1 / 3, 1e-9));

      final thrice = PreferenceProfile.from(
        feedbacks: [
          _fb(['t1'], true, id: 'a'),
          _fb(['t1'], true, id: 'b'),
          _fb(['t1'], true, id: 'c'),
        ],
        items: items,
      );
      expect(thrice.itemScore('t1'), closeTo(1.0, 1e-9));
    });

    test('未反馈的单品偏好为 0', () {
      final p = PreferenceProfile.from(
        feedbacks: [
          _fb(['t1'], true),
        ],
        items: items,
      );
      expect(p.itemScore('d1'), 0);
      expect(p.comboScore([items[3], items[4]]), 0);
    });

    test('空反馈得到空画像', () {
      final p = PreferenceProfile.from(feedbacks: const [], items: items);
      expect(p.isEmpty, isTrue);
      expect(p, same(PreferenceProfile.empty));
    });
  });

  group('推荐评分中的偏好维度', () {
    final svc = RecommendationService();
    final items = [
      _item('t1', '上衣', '针织衫', tags: ['休闲', '简约']),
      _item('b1', '下装', '牛仔长裤', tags: ['休闲']),
      _item('s1', '鞋', '运动鞋', tags: ['休闲']),
      _item('d1', '连衣裙', '连衣裙', tags: ['甜美']),
      _item('d2', '连衣裙', '连衣裙', tags: ['甜美']),
    ];

    test('无反馈时「偏好」为中性 5 分（回归）', () {
      final recs = svc.recommend(items: items, weather: _cold());
      expect(recs, isNotEmpty);
      expect(recs.first.scoreDetails['偏好'], 5);
    });

    test('有反馈时「偏好」高于中性，且总分提升', () {
      final neutral = svc.recommend(items: items, weather: _cold());
      final liked = svc.recommend(
        items: items,
        weather: _cold(),
        preference: PreferenceProfile.from(
          feedbacks: [
            for (var i = 0; i < items.length; i++)
              _fb([items[i].id], true, id: 'f$i'),
          ],
          items: items,
        ),
      );
      expect(liked, isNotEmpty);
      final p = liked.first.scoreDetails['偏好']!;
      expect(p, greaterThan(5));
      expect(p, lessThanOrEqualTo(10));
      expect(liked.first.score, greaterThan(neutral.first.score));
    });

    test('👎 过的组合被剔除，其他组合仍在', () {
      final wardrobe = [
        _item('t1', '上衣', '针织衫', tags: ['休闲']),
        _item('t2', '上衣', '衬衫', tags: ['通勤']),
        _item('b1', '下装', '牛仔长裤', tags: ['休闲']),
        _item('s1', '鞋', '运动鞋', tags: ['休闲']),
        _item('d1', '连衣裙', '连衣裙', tags: ['甜美']),
      ];
      final recs = svc.recommend(
        items: wardrobe,
        weather: _cold(),
        preference: PreferenceProfile.from(
          feedbacks: [
            _fb(['t1', 'b1', 's1'], false),
          ],
          items: wardrobe,
        ),
      );
      expect(recs, isNotEmpty);
      expect(
        recs.every((r) => !r.itemIds.contains('t1')),
        isTrue,
        reason: '👎 过的组合不应再出现',
      );
      expect(recs.any((r) => r.itemIds.contains('t2')), isTrue);
    });

    test('全部组合都被 👎 时兜底返回非空（避免空页面）', () {
      final wardrobe = [
        _item('t1', '上衣', '针织衫'),
        _item('t2', '上衣', '衬衫'),
        _item('b1', '下装', '牛仔长裤'),
        _item('s1', '鞋', '运动鞋'),
        _item('d1', '连衣裙', '连衣裙'),
      ];
      final recs = svc.recommend(
        items: wardrobe,
        weather: _cold(),
        preference: PreferenceProfile.from(
          feedbacks: [
            _fb(['t1', 'b1', 's1'], false, id: 'g1'),
            _fb(['t2', 'b1', 's1'], false, id: 'g2'),
          ],
          items: wardrobe,
        ),
      );
      expect(recs, isNotEmpty);
    });

    test('衣物不足时返回空（不崩）', () {
      final recs = svc.recommend(
        items: items.take(2).toList(),
        weather: _cold(),
      );
      expect(recs, isEmpty);
    });
  });
}

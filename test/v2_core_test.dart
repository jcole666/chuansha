import 'package:flutter_test/flutter_test.dart';

import 'package:chuansha/data/models/wear_record.dart';
import 'package:chuansha/data/models/clothing_item.dart';
import 'package:chuansha/data/models/color_info.dart';
import 'package:chuansha/domain/enums/clothing_status.dart';
import 'package:chuansha/data/repositories/memory_wardrobe_repository.dart';
import 'package:chuansha/features/calendar/presentation/providers/wear_calendar_provider.dart';

ClothingItem _item(String id,
    {ClothingStatus status = ClothingStatus.clean, String? userId}) {
  return ClothingItem(
    id: id,
    userId: userId ?? 'test_user',
    name: '衣物$id',
    category: '上衣',
    subCategory: 'T恤',
    imageUrl: 'https://example.com/$id.png',
    colors: const [ColorInfo(name: '黑', hex: '#000000')],
    status: status,
    createdAt: DateTime(2026, 1, 1),
  );
}

WearRecord _record({
  required String id,
  required DateTime date,
  required List<String> itemIds,
  String? name,
}) {
  return WearRecord(
    id: id,
    userId: 'test_user',
    wearDate: DateTime(date.year, date.month, date.day),
    name: name,
    itemIds: itemIds,
    createdAt: DateTime(2026, 1, 1),
  );
}

void main() {
  group('InMemoryWardrobeRepository.updateStatusBatch', () {
    test('批量修改状态', () async {
      final repo = InMemoryWardrobeRepository();
      final uid = InMemoryWardrobeRepository.mockUserId;
      await repo.addItem(_item('a', userId: uid));
      await repo.addItem(_item('b', userId: uid));
      await repo.addItem(_item('c', userId: uid));

      await repo.updateStatusBatch(['a', 'b'], ClothingStatus.dirty);

      final items = await repo.getItems(uid);
      final byId = {for (final i in items) i.id: i};
      expect(byId['a']!.status, ClothingStatus.dirty);
      expect(byId['b']!.status, ClothingStatus.dirty);
      // 未选中的不受影响
      expect(byId['c']!.status, ClothingStatus.clean);
    });

    test('空列表不报错', () async {
      final repo = InMemoryWardrobeRepository();
      final uid = InMemoryWardrobeRepository.mockUserId;
      await repo.addItem(_item('a', userId: uid));
      await repo.updateStatusBatch([], ClothingStatus.dirty);
      final items = await repo.getItems(uid);
      expect(items.first.status, ClothingStatus.clean);
    });
  });

  group('computeWearStats（重算逻辑）', () {
    test('新增记录：count = 出现次数，last = max(date)', () {
      final records = [
        _record(id: 'r1', date: DateTime(2026, 8, 1), itemIds: ['A', 'B']),
        _record(id: 'r2', date: DateTime(2026, 8, 3), itemIds: ['A', 'C']),
      ];

      final result = computeWearStats(records, {'A', 'B', 'C'});

      expect(result.counts['A'], 2); // A 出现两次
      expect(result.counts['B'], 1);
      expect(result.counts['C'], 1);
      expect(result.lastDates['A'], DateTime(2026, 8, 3)); // 最大日期
      expect(result.lastDates['B'], DateTime(2026, 8, 1));
    });

    test('同日多条记录：count 累计但 last 不变', () {
      final records = [
        _record(id: 'r1', date: DateTime(2026, 8, 1), itemIds: ['A']),
        _record(id: 'r2', date: DateTime(2026, 8, 1), itemIds: ['A']),
      ];

      final result = computeWearStats(records, {'A'});

      expect(result.counts['A'], 2); // 一天穿两套，累计两次
      expect(result.lastDates['A'], DateTime(2026, 8, 1));
    });

    test('补历史记录：last 取最大日期，不回退', () {
      final records = [
        _record(id: 'r1', date: DateTime(2026, 8, 5), itemIds: ['A']),
        // 补一条昨天的历史记录
        _record(id: 'r2', date: DateTime(2026, 7, 30), itemIds: ['A']),
      ];

      final result = computeWearStats(records, {'A'});

      expect(result.counts['A'], 2);
      // 即便记录里有更早日期，last 仍是最新那天
      expect(result.lastDates['A'], DateTime(2026, 8, 5));
    });

    test('删除记录：count 减、last 取剩余记录最大值', () {
      // 场景：原本有 8/5 和 8/1 两条，删掉 8/5 那条
      final remaining = [
        _record(id: 'r1', date: DateTime(2026, 8, 1), itemIds: ['A']),
      ];

      final result = computeWearStats(remaining, {'A'});

      expect(result.counts['A'], 1); // 不再包含被删的那次
      expect(result.lastDates['A'], DateTime(2026, 8, 1)); // 回落到剩余的最大值
    });

    test('记录清空：count 归零、last 无值（不会残留旧值）', () {
      final result = computeWearStats(const [], {'A'});

      // map 里没有该衣物条目 = 计数 0（生产代码用 ?? 0 兜底）
      expect(result.counts.containsKey('A'), isFalse);
      expect(result.lastDates.containsKey('A'), isFalse);
    });
  });

  group('WearCalendarState.recordsForItem', () {
    test('过滤某衣物的记录并按日期倒序', () {
      final state = WearCalendarState(records: [
        _record(id: 'r1', date: DateTime(2026, 8, 1), itemIds: ['A', 'B']),
        _record(id: 'r2', date: DateTime(2026, 8, 3), itemIds: ['A']),
        _record(id: 'r3', date: DateTime(2026, 8, 2), itemIds: ['C']),
      ]);

      final forA = state.recordsForItem('A');
      expect(forA.length, 2);
      expect(forA[0].id, 'r2'); // 最新在前
      expect(forA[1].id, 'r1');
    });
  });

  group('WearCalendarState 月度统计', () {
    test('wearDaysThisMonth 按日期去重', () {
      final now = DateTime.now();
      final state = WearCalendarState(records: [
        _record(id: 'r1', date: DateTime(now.year, now.month, 1), itemIds: ['A']),
        _record(id: 'r2', date: DateTime(now.year, now.month, 1), itemIds: ['B']),
        _record(id: 'r3', date: DateTime(now.year, now.month, 2), itemIds: ['C']),
      ]);

      // 同一天两条只算 1 天
      expect(state.wearDaysThisMonth, 2);
      expect(state.outfitsThisMonth, 3);
    });

    test('mostWornItemsThisMonth 排序并限 Top N', () {
      final now = DateTime.now();
      final state = WearCalendarState(records: [
        _record(id: 'r1', date: DateTime(now.year, now.month, 1), itemIds: ['A', 'B']),
        _record(id: 'r2', date: DateTime(now.year, now.month, 2), itemIds: ['A']),
        _record(id: 'r3', date: DateTime(now.year, now.month, 3), itemIds: ['C', 'C', 'C']),
      ]);

      final top = state.mostWornItemsThisMonth(limit: 2);
      // C 出现 3 次最多，A 出现 2 次其次
      expect(top.length, 2);
      expect(top.first.key, 'C');
      expect(top.first.value, 3);
      expect(top[1].key, 'A');
      expect(top[1].value, 2);
    });
  });
}

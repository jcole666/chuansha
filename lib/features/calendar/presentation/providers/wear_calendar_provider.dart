import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../../../data/models/wear_record.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../wardrobe/presentation/providers/wardrobe_provider.dart';

/// 重算结果：每件衣物的累计穿着次数 + 最大穿着日期
class WearCountResult {
  final Map<String, int> counts;
  final Map<String, DateTime> lastDates;

  const WearCountResult({required this.counts, required this.lastDates});
}

/// 从穿搭记录集合重算指定衣物的穿着统计（纯函数，便于单元测试）。
///
/// 口径（用户确认）：
/// - count = 该衣物在所有穿搭记录里出现的累计次数
/// - last = 所有记录里的最大日期（天然不回退）
///
/// add/update/delete 三种变更路径最终都归结为"记录集合变化后重算"，
/// 所以这里只测这一个函数即可覆盖三条路径。
WearCountResult computeWearStats(
  List<WearRecord> records,
  Set<String> itemIds,
) {
  final counts = <String, int>{};
  final lastDates = <String, DateTime>{};
  for (final r in records) {
    for (final id in r.itemIds) {
      if (!itemIds.contains(id)) continue;
      counts[id] = (counts[id] ?? 0) + 1;
      final d = r.wearDate;
      final prev = lastDates[id];
      if (prev == null || d.isAfter(prev)) {
        lastDates[id] = d;
      }
    }
  }
  return WearCountResult(counts: counts, lastDates: lastDates);
}

/// 穿搭日历状态
class WearCalendarState {
  final List<WearRecord> records;
  final bool isLoading;

  const WearCalendarState({this.records = const [], this.isLoading = false});

  WearCalendarState copyWith({List<WearRecord>? records, bool? isLoading}) {
    return WearCalendarState(
      records: records ?? this.records,
      isLoading: isLoading ?? this.isLoading,
    );
  }

  /// 某天是否有穿搭记录
  bool hasRecord(DateTime day) {
    return recordsFor(day).isNotEmpty;
  }

  /// 某天所有的穿搭记录（一天可多条）
  List<WearRecord> recordsFor(DateTime day) {
    final normalized = DateTime(day.year, day.month, day.day);
    return records.where((r) => _sameDay(r.wearDate, normalized)).toList();
  }

  /// 某件衣物被穿过的所有记录（按日期倒序）
  List<WearRecord> recordsForItem(String itemId) {
    return records.where((r) => r.itemIds.contains(itemId)).toList()
      ..sort((a, b) => b.wearDate.compareTo(a.wearDate));
  }

  /// 本月穿搭天数（按日期去重）
  int get wearDaysThisMonth {
    final now = DateTime.now();
    return records
        .where(
          (r) => r.wearDate.year == now.year && r.wearDate.month == now.month,
        )
        .map((r) => DateTime(r.wearDate.year, r.wearDate.month, r.wearDate.day))
        .toSet()
        .length;
  }

  /// 本月记录套数
  int get outfitsThisMonth {
    final now = DateTime.now();
    return records
        .where(
          (r) => r.wearDate.year == now.year && r.wearDate.month == now.month,
        )
        .length;
  }

  /// 本月最常穿单品 Top N（按 itemIds 出现次数）
  List<MapEntry<String, int>> mostWornItemsThisMonth({int limit = 3}) {
    final now = DateTime.now();
    final counts = <String, int>{};
    for (final r in records) {
      if (r.wearDate.year != now.year || r.wearDate.month != now.month)
        continue;
      for (final id in r.itemIds) {
        counts[id] = (counts[id] ?? 0) + 1;
      }
    }
    final sorted = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(limit).toList();
  }

  static bool _sameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}

/// 穿搭日历 Notifier
class WearCalendarNotifier extends StateNotifier<WearCalendarState> {
  final Ref _ref;
  WearCalendarNotifier(this._ref) : super(const WearCalendarState());

  SupabaseClient get _client => Supabase.instance.client;
  final _uuid = const Uuid();

  /// 当前用户 ID
  String? get _userId => _ref.read(currentUserIdProvider);

  /// 加载所有穿搭记录
  Future<void> load() async {
    final userId = _userId;
    if (userId == null) return;

    state = state.copyWith(isLoading: true);
    try {
      final res = await _client
          .from('wear_records')
          .select()
          .eq('user_id', userId)
          .order('wear_date', ascending: false);
      final records = (res as List)
          .map((row) => WearRecord.fromJson(row as Map<String, dynamic>))
          .toList();
      state = WearCalendarState(records: records, isLoading: false);
    } catch (_) {
      state = state.copyWith(isLoading: false);
    }
  }

  /// 新增一条穿搭记录（某天穿的一套）
  ///
  /// 返回是否成功。以 insert 成功为成功；回写衣物计数失败不影响返回值
  /// （降级为警告，靠 loadItems 兜底）。
  Future<bool> addRecord({
    required DateTime date,
    String? name,
    required List<String> itemIds,
    String? note,
  }) async {
    final userId = _userId;
    if (userId == null) return false;

    final record = WearRecord(
      id: _uuid.v4(),
      userId: userId,
      wearDate: DateTime(date.year, date.month, date.day),
      name: name,
      itemIds: itemIds,
      note: note,
      createdAt: DateTime.now(),
    );
    try {
      await _client.from('wear_records').insert(record.toJson());
      state = state.copyWith(records: [...state.records, record]);
      // 回写受影响衣物的穿着次数/上次穿着日（失败不影响主流程）
      await _recomputeWearCounts(itemIds);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 更新一条穿搭记录
  Future<bool> updateRecord(WearRecord updated) async {
    // 受影响衣物 = 变更前后 itemIds 的并集
    final old = state.records.where((r) => r.id == updated.id).firstOrNull;
    final affected = <String>{...?old?.itemIds, ...updated.itemIds};

    try {
      final data = updated.toJson()..remove('id');
      await _client.from('wear_records').update(data).eq('id', updated.id);
      state = state.copyWith(
        records: state.records
            .map((r) => r.id == updated.id ? updated : r)
            .toList(),
      );
      await _recomputeWearCounts(affected.toList());
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 删除一条穿搭记录
  Future<bool> deleteRecord(String recordId) async {
    // 受影响衣物 = 被删记录里涉及的所有衣物
    final old = state.records.where((r) => r.id == recordId).firstOrNull;
    final affected = <String>{...?old?.itemIds};

    try {
      await _client.from('wear_records').delete().eq('id', recordId);
      state = state.copyWith(
        records: state.records.where((r) => r.id != recordId).toList(),
      );
      await _recomputeWearCounts(affected.toList());
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 重算受影响衣物的穿着次数和上次穿着日期。
  ///
  /// 口径（用户确认）：
  /// - wear_count = 该衣物在所有穿搭记录里出现的累计次数
  /// - last_worn_date = 所有记录里的最大日期（天然不回退）
  ///
  /// 覆盖 add/update/delete 三种变更路径，保证计数与日历记录始终一致。
  Future<void> _recomputeWearCounts(List<String> itemIds) async {
    if (itemIds.isEmpty) return;

    try {
      // 从当前内存记录重算（纯函数，见 computeWearStats）
      final result = computeWearStats(state.records, itemIds.toSet());

      // 逐件回写 Supabase（个人衣橱数据量小，逐件可接受）
      for (final id in itemIds) {
        final count = result.counts[id] ?? 0;
        final last = result.lastDates[id];
        await _client
            .from('clothing_items')
            .update({
              'wear_count': count,
              if (last != null) 'last_worn_date': last.toIso8601String(),
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('id', id);
      }

      // 刷新衣橱内存数据，让其它 Tab 读到最新计数
      await _ref.read(wardrobeListProvider.notifier).loadItems();
    } catch (_) {
      // 回写失败不阻断主流程，计数由下次 loadItems 兜底
    }
  }
}

/// 穿搭日历 Provider
final wearCalendarProvider =
    StateNotifierProvider<WearCalendarNotifier, WearCalendarState>((ref) {
      return WearCalendarNotifier(ref);
    });

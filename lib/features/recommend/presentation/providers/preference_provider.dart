import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../../data/models/preference_feedback.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

/// 偏好反馈 Notifier
///
/// 保存用户对推荐搭配的 👍/👎。
/// 此前这些反馈只存在内存里（`// TODO: V2`），退出应用就没了，
/// 推荐引擎的「偏好」维度也因此一直是硬编码的 5 分。
class PreferenceNotifier extends StateNotifier<List<PreferenceFeedback>> {
  final Ref _ref;
  PreferenceNotifier(this._ref) : super(const []);

  SupabaseClient get _client => Supabase.instance.client;
  final _uuid = const Uuid();

  String? get _userId => _ref.read(currentUserIdProvider);

  /// 加载该用户的全部反馈
  Future<void> load() async {
    final userId = _userId;
    if (userId == null) return;

    try {
      final res = await _client
          .from('preference_feedback')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false);
      state = (res as List)
          .map(
            (row) => PreferenceFeedback.fromJson(row as Map<String, dynamic>),
          )
          .toList();
    } catch (_) {
      // 表可能还没建（见 supabase/preference_feedback.sql）。
      // 静默降级：没有偏好数据时推荐退化为通用规则，不影响主流程。
      state = const [];
    }
  }

  /// 记录一条反馈
  ///
  /// 返回是否成功。失败时调用方据此提示 ——
  /// 不能像以前那样「点了赞、界面变了、其实没存上」。
  Future<bool> record({
    required List<String> itemIds,
    required bool liked,
  }) async {
    final userId = _userId;
    if (userId == null || itemIds.isEmpty) return false;

    final feedback = PreferenceFeedback(
      id: _uuid.v4(),
      userId: userId,
      itemIds: itemIds,
      liked: liked,
      createdAt: DateTime.now(),
    );

    try {
      await _client.from('preference_feedback').insert({
        'id': feedback.id,
        'user_id': userId,
        'item_ids': itemIds,
        'liked': liked,
      });
      state = [feedback, ...state];
      return true;
    } catch (_) {
      return false;
    }
  }
}

/// 偏好反馈 Provider
final preferenceProvider =
    StateNotifierProvider<PreferenceNotifier, List<PreferenceFeedback>>((ref) {
      return PreferenceNotifier(ref);
    });

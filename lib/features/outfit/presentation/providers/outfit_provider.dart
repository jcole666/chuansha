import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/local_store.dart';
import '../../../../data/models/outfit.dart';
import '../../../../data/models/clothing_item.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

/// Outfit 搭配列表状态
class OutfitListState {
  final List<Outfit> outfits;
  final bool isLoading;

  /// 当前展示的是本地缓存（网络请求失败后回退）
  final bool isOffline;

  const OutfitListState({
    this.outfits = const [],
    this.isLoading = false,
    this.isOffline = false,
  });

  OutfitListState copyWith({
    List<Outfit>? outfits,
    bool? isLoading,
    bool? isOffline,
  }) {
    return OutfitListState(
      outfits: outfits ?? this.outfits,
      isLoading: isLoading ?? this.isLoading,
      isOffline: isOffline ?? this.isOffline,
    );
  }

  /// 根据 Outfit 的 itemIds 查找对应 ClothingItem
  List<ClothingItem> getItemsForOutfit(
    Outfit outfit,
    List<ClothingItem> allItems,
  ) {
    return outfit.itemIds
        .map((id) => allItems.where((item) => item.id == id).firstOrNull)
        .whereType<ClothingItem>()
        .toList();
  }
}

/// Outfit Notifier（Supabase）
class OutfitListNotifier extends StateNotifier<OutfitListState> {
  final Ref _ref;
  OutfitListNotifier(this._ref) : super(const OutfitListState());

  SupabaseClient get _client => Supabase.instance.client;
  final _uuid = const Uuid();

  /// 当前用户 ID
  String? get _userId => _ref.read(currentUserIdProvider);

  /// 加载所有搭配
  ///
  /// 与衣橱列表一致：成功写缓存，失败回退缓存并标记离线。
  Future<void> load() async {
    final userId = _userId;
    if (userId == null) return;

    state = state.copyWith(isLoading: true);
    final cacheKey = CacheKeys.outfits(userId);

    try {
      final res = await _client
          .from('outfits')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false);
      final outfits = (res as List)
          .map((row) => Outfit.fromJson(row as Map<String, dynamic>))
          .toList();
      state = OutfitListState(
        outfits: outfits,
        isLoading: false,
        isOffline: false,
      );
      await LocalStore.writeCache(
        cacheKey,
        jsonEncode(outfits.map((e) => e.toJson()).toList()),
      );
    } catch (e) {
      final cached = LocalStore.readCache(cacheKey);
      if (cached != null) {
        try {
          final outfits = (jsonDecode(cached) as List)
              .map((row) => Outfit.fromJson(row as Map<String, dynamic>))
              .toList();
          state = OutfitListState(
            outfits: outfits,
            isLoading: false,
            isOffline: true,
          );
          return;
        } catch (_) {
          // 缓存坏了，走下面的降级分支
        }
      }
      state = state.copyWith(isLoading: false, isOffline: true);
    }
  }

  /// 添加搭配
  ///
  /// 返回是否真正落库成功。此前是 `catch (_) {}` 静默失败，
  /// 界面乐观更新后一刷新就消失，用户完全不知道保存失败了。
  Future<bool> addOutfit(Outfit outfit) async {
    final userId = _userId;
    if (userId == null) return false;

    final saved = outfit.copyWith(
      id: outfit.id.isNotEmpty ? outfit.id : _uuid.v4(),
      userId: userId,
      createdAt: DateTime.now(),
    );
    try {
      await _client.from('outfits').insert(saved.toJson());
      state = state.copyWith(outfits: [saved, ...state.outfits]);
      return true;
    } catch (_) {
      // 失败时不改动本地状态，交由调用方提示
      return false;
    }
  }

  /// 删除搭配
  Future<bool> deleteOutfit(String id) async {
    try {
      await _client.from('outfits').delete().eq('id', id);
      state = state.copyWith(
        outfits: state.outfits.where((o) => o.id != id).toList(),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 更新搭配
  Future<bool> updateOutfit(Outfit updated) async {
    try {
      final data = updated.copyWith(updatedAt: DateTime.now()).toJson()
        ..remove('id');
      await _client.from('outfits').update(data).eq('id', updated.id);
      state = state.copyWith(
        outfits: state.outfits
            .map((o) => o.id == updated.id ? updated : o)
            .toList(),
      );
      return true;
    } catch (_) {
      return false;
    }
  }
}

/// Outfit Provider
final outfitListProvider =
    StateNotifierProvider<OutfitListNotifier, OutfitListState>((ref) {
      return OutfitListNotifier(ref);
    });

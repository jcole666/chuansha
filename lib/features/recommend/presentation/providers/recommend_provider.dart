import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../data/models/weather_data.dart';
import '../../../../data/models/clothing_item.dart';
import '../../../../services/weather_service.dart';
import '../../../../services/recommendation_service.dart';
import '../../../../data/repositories/wardrobe_repository.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../wardrobe/presentation/providers/wardrobe_provider.dart';

/// 推荐页状态
class RecommendState {
  final WeatherData? weather;
  final bool isLoadingWeather;
  final String? weatherError;

  final List<RecommendationResult> recommendations;
  final bool isLoadingRecommendations;

  final List<List<String>> feedbackItemIds; // 本次已反馈的推荐

  const RecommendState({
    this.weather,
    this.isLoadingWeather = false,
    this.weatherError,
    this.recommendations = const [],
    this.isLoadingRecommendations = false,
    this.feedbackItemIds = const [],
  });

  RecommendState copyWith({
    WeatherData? weather,
    bool? isLoadingWeather,
    String? weatherError,
    List<RecommendationResult>? recommendations,
    bool? isLoadingRecommendations,
    List<List<String>>? feedbackItemIds,
    bool clearWeatherError = false,
  }) {
    return RecommendState(
      weather: weather ?? this.weather,
      isLoadingWeather: isLoadingWeather ?? this.isLoadingWeather,
      weatherError: clearWeatherError
          ? null
          : (weatherError ?? this.weatherError),
      recommendations: recommendations ?? this.recommendations,
      isLoadingRecommendations:
          isLoadingRecommendations ?? this.isLoadingRecommendations,
      feedbackItemIds: feedbackItemIds ?? this.feedbackItemIds,
    );
  }
}

/// 推荐页 Notifier
class RecommendNotifier extends StateNotifier<RecommendState> {
  final WeatherService _weatherService;
  final RecommendationService _recommendationService;
  final WardrobeRepository _repository;
  final Ref _ref;

  RecommendNotifier(
    this._weatherService,
    this._recommendationService,
    this._repository,
    this._ref,
  ) : super(const RecommendState());

  /// 当前用户 ID
  String? get _userId => _ref.read(currentUserIdProvider);

  /// 加载天气 + 生成推荐
  Future<void> load() async {
    final userId = _userId;
    if (userId == null) return;

    state = state.copyWith(
      isLoadingWeather: true,
      isLoadingRecommendations: true,
      weatherError: null,
    );

    // 并行：加载天气 + 衣物
    final results = await Future.wait([
      _loadWeather(),
      _repository.getItems(userId),
    ]);

    final weather = results[0] as WeatherData?;
    final items = results[1] as List<ClothingItem>;

    if (weather != null) {
      if (items.length >= 5) {
        final recs = _recommendationService.recommend(
          items: items,
          weather: weather,
        );
        state = state.copyWith(
          recommendations: recs,
          isLoadingRecommendations: false,
        );
      } else {
        state = state.copyWith(
          recommendations: [],
          isLoadingRecommendations: false,
        );
      }
    }
  }

  /// 加载天气
  ///
  /// 天气失败不再静默：WeatherService 现在会抛 WeatherException，
  /// 这里把 message 原样透出（文案已经在 service 里写好了），
  /// 页面据此显示「未配置密钥」「超时」等具体原因，而不是假装有数据。
  Future<WeatherData?> _loadWeather() async {
    try {
      final weather = await _weatherService.getWeather();
      state = state.copyWith(
        weather: weather,
        isLoadingWeather: false,
        clearWeatherError: true,
      );
      return weather;
    } on WeatherException catch (e) {
      state = state.copyWith(isLoadingWeather: false, weatherError: e.message);
      return state.weather;
    } catch (e) {
      state = state.copyWith(
        isLoadingWeather: false,
        weatherError: '天气数据获取失败：$e',
      );
      return state.weather;
    }
  }

  /// 换一批推荐
  Future<void> refresh() async {
    final userId = _userId;
    if (userId == null) return;

    state = state.copyWith(isLoadingRecommendations: true, feedbackItemIds: []);
    await Future.delayed(const Duration(milliseconds: 300));

    final items = await _repository.getItems(userId);
    if (state.weather != null && items.length >= 5) {
      final recs = _recommendationService.recommend(
        items: items,
        weather: state.weather!,
      );
      state = state.copyWith(
        recommendations: recs,
        isLoadingRecommendations: false,
      );
    } else {
      state = state.copyWith(isLoadingRecommendations: false);
    }
  }

  /// 喜欢 👍
  void like(RecommendationResult rec) {
    final ids = rec.itemIds;
    // TODO: V2 - 将喜欢记录存储到 Supabase preference_feedback
    state = state.copyWith(feedbackItemIds: [...state.feedbackItemIds, ids]);
  }

  /// 不喜欢 👎
  void dislike(RecommendationResult rec) {
    final ids = rec.itemIds;
    state = state.copyWith(feedbackItemIds: [...state.feedbackItemIds, ids]);
  }

  /// 该推荐是否已反馈
  bool hasFeedback(RecommendationResult rec) {
    return state.feedbackItemIds.any(
      (ids) => ids.toSet().intersection(rec.itemIds.toSet()).length >= 2,
    );
  }
}

/// 推荐页 Provider
final recommendProvider =
    StateNotifierProvider<RecommendNotifier, RecommendState>((ref) {
      // WeatherService 内部会自己定位（LocationService）
      final weatherService = WeatherService();
      final recommendationService = RecommendationService();
      final repository = ref.watch(wardrobeRepositoryProvider);
      return RecommendNotifier(
        weatherService,
        recommendationService,
        repository,
        ref,
      );
    });

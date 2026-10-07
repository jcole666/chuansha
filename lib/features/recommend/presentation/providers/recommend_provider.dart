import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/error_log.dart';
import '../../../../data/models/weather_data.dart';
import '../../../../data/models/clothing_item.dart';
import '../../../../data/models/preference_feedback.dart';
import '../../../../services/weather_service.dart';
import '../../../../services/recommendation_service.dart';
import '../../../../data/repositories/wardrobe_repository.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../wardrobe/presentation/providers/wardrobe_provider.dart';
import 'preference_provider.dart';

/// 推荐页状态
class RecommendState {
  final WeatherData? weather;
  final bool isLoadingWeather;
  final String? weatherError;

  final List<RecommendationResult> recommendations;
  final bool isLoadingRecommendations;

  /// 推荐生成失败时的用户可读提示（区别于 [weatherError]）。
  /// 之前 load() 抛异常时没有任何地方复位 isLoadingRecommendations，
  /// 导致弱网/RLS 报错时骨架屏永久转圈；现在失败会落到这里。
  final String? recommendError;

  final List<List<String>> feedbackItemIds; // 本次已反馈的推荐

  const RecommendState({
    this.weather,
    this.isLoadingWeather = false,
    this.weatherError,
    this.recommendations = const [],
    this.isLoadingRecommendations = false,
    this.recommendError,
    this.feedbackItemIds = const [],
  });

  RecommendState copyWith({
    WeatherData? weather,
    bool? isLoadingWeather,
    String? weatherError,
    List<RecommendationResult>? recommendations,
    bool? isLoadingRecommendations,
    String? recommendError,
    List<List<String>>? feedbackItemIds,
    bool clearWeatherError = false,
    bool clearRecommendError = false,
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
      recommendError: clearRecommendError
          ? null
          : (recommendError ?? this.recommendError),
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
      clearRecommendError: true,
    );

    // 并行：加载天气 + 衣物 + 偏好反馈
    //
    // 整段包 try/catch：以前 getItems 抛错（弱网 / RLS 报错）会让 load() 直接
    // 抛出，isLoadingRecommendations 永远停在 true —— 页面 3 个 shimmer 无限转。
    // 现在无论成功、失败还是异常，都会复位 loading 并给出可重试的错误态。
    try {
      final results = await Future.wait([
        _loadWeather(),
        _repository.getItems(userId),
        _ref.read(preferenceProvider.notifier).load(),
      ]);

      final weather = results[0] as WeatherData?;
      final items = results[1] as List<ClothingItem>;

      if (weather != null && items.length >= 5) {
        final recs = _recommendationService.recommend(
          items: items,
          weather: weather,
          preference: _buildProfile(items),
        );
        state = state.copyWith(
          recommendations: recs,
          isLoadingRecommendations: false,
        );
      } else {
        // 天气缺失时不出推荐（页面会给出天气不可用提示 + 重试）
        state = state.copyWith(
          recommendations: [],
          isLoadingRecommendations: false,
        );
      }
    } catch (e, s) {
      ErrorLog.record('推荐加载', e, s);
      state = state.copyWith(
        isLoadingWeather: false,
        isLoadingRecommendations: false,
        recommendError: '推荐加载失败，请检查网络后重试',
      );
    }
  }

  /// 加载天气
  ///
  /// 天气失败不再静默。技术细节（缺 OWM_API_KEY、超时、状态码…）记入 ErrorLog，
  /// 对用户只暴露一句人话，避免把「请用 --dart-define=OWM_API_KEY 启动」
  /// 这种开发者文案直接甩到界面上。
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
      ErrorLog.record('天气服务', e);
      state = state.copyWith(
        isLoadingWeather: false,
        weatherError: '天气服务暂时不可用，无法生成推荐',
      );
      return state.weather;
    } catch (e, s) {
      ErrorLog.record('天气服务', e, s);
      state = state.copyWith(
        isLoadingWeather: false,
        weatherError: '天气服务暂时不可用，无法生成推荐',
      );
      return state.weather;
    }
  }

  /// 换一批推荐
  Future<void> refresh() async {
    final userId = _userId;
    if (userId == null) return;

    state = state.copyWith(
      isLoadingRecommendations: true,
      feedbackItemIds: [],
      clearRecommendError: true,
    );
    await Future.delayed(const Duration(milliseconds: 300));

    try {
      final items = await _repository.getItems(userId);
      if (state.weather != null && items.length >= 5) {
        final recs = _recommendationService.recommend(
          items: items,
          weather: state.weather!,
          preference: _buildProfile(items),
        );
        state = state.copyWith(
          recommendations: recs,
          isLoadingRecommendations: false,
        );
      } else {
        state = state.copyWith(isLoadingRecommendations: false);
      }
    } catch (e, s) {
      ErrorLog.record('推荐换一批', e, s);
      state = state.copyWith(
        isLoadingRecommendations: false,
        recommendError: '推荐加载失败，请检查网络后重试',
      );
    }
  }

  /// 从当前反馈记录构建偏好画像
  PreferenceProfile _buildProfile(List<ClothingItem> items) {
    return PreferenceProfile.from(
      feedbacks: _ref.read(preferenceProvider),
      items: items,
    );
  }

  /// 喜欢 👍 —— 落库成功后才更新本地状态
  Future<bool> like(RecommendationResult rec) => _record(rec, liked: true);

  /// 不喜欢 👎
  Future<bool> dislike(RecommendationResult rec) => _record(rec, liked: false);

  /// 记录反馈
  ///
  /// 之前只改内存（`// TODO: V2`），退出应用就没了。
  /// 现在写库，失败返回 false 让页面如实提示。
  Future<bool> _record(RecommendationResult rec, {required bool liked}) async {
    final ok = await _ref
        .read(preferenceProvider.notifier)
        .record(itemIds: rec.itemIds, liked: liked);
    if (ok) {
      state = state.copyWith(
        feedbackItemIds: [...state.feedbackItemIds, rec.itemIds],
      );
    }
    return ok;
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

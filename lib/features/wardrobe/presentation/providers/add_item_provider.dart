import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/error_log.dart';
import '../../../../../data/models/clothing_item.dart';
import '../../../../../data/models/color_info.dart';
import '../../../../../data/repositories/wardrobe_repository.dart';
import '../../../../../domain/enums/clothing_status.dart';
import '../../../../../services/image_service.dart';
import '../../../../../services/image_upload_service.dart';
import '../../../../../services/matting_service.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import 'wardrobe_provider.dart';

/// 录入流程的步骤
enum AddItemStep {
  /// 选择来源（拍照/相册）
  selectSource,

  /// 裁剪中
  cropping,

  /// 填写信息
  fillInfo,

  /// 保存中
  saving,
}

/// 录入流程状态
class AddItemState {
  final AddItemStep step;
  final File? imageFile;
  final bool isLoading;

  // 表单字段
  final String name;
  final String category;
  final String? subCategory;
  final List<String> colors;
  final List<String> styleTags;
  final List<String> customStyleTags; // 用户自定义的标签
  final List<String> seasonTags;
  final List<String> occasionTags; // 场合
  final String? wearFrequency; // 穿着频率
  final String? brand;
  final double? price;
  final ClothingStatus status;
  final String? errorMessage;

  const AddItemState({
    this.step = AddItemStep.selectSource,
    this.imageFile,
    this.isLoading = false,
    this.name = '',
    this.category = '',
    this.subCategory,
    this.colors = const [],
    this.styleTags = const [],
    this.customStyleTags = const [],
    this.seasonTags = const [],
    this.occasionTags = const [],
    this.wearFrequency,
    this.brand,
    this.price,
    this.status = ClothingStatus.clean,
    this.errorMessage,
  });

  AddItemState copyWith({
    AddItemStep? step,
    File? imageFile,
    bool? isLoading,
    String? name,
    String? category,
    String? subCategory,
    List<String>? colors,
    List<String>? styleTags,
    List<String>? customStyleTags,
    List<String>? seasonTags,
    List<String>? occasionTags,
    String? wearFrequency,
    String? brand,
    double? price,
    ClothingStatus? status,
    String? errorMessage,
    bool clearImage = false,
    bool clearForm = false,
  }) {
    return AddItemState(
      step: step ?? this.step,
      imageFile: clearImage ? null : (imageFile ?? this.imageFile),
      isLoading: isLoading ?? this.isLoading,
      name: clearForm ? '' : (name ?? this.name),
      category: clearForm ? '' : (category ?? this.category),
      subCategory: clearForm ? null : (subCategory ?? this.subCategory),
      colors: clearForm ? [] : (colors ?? this.colors),
      styleTags: clearForm ? [] : (styleTags ?? this.styleTags),
      customStyleTags: clearForm
          ? []
          : (customStyleTags ?? this.customStyleTags),
      seasonTags: clearForm ? [] : (seasonTags ?? this.seasonTags),
      occasionTags: clearForm ? [] : (occasionTags ?? this.occasionTags),
      wearFrequency: clearForm ? null : (wearFrequency ?? this.wearFrequency),
      brand: clearForm ? null : (brand ?? this.brand),
      price: clearForm ? null : (price ?? this.price),
      status: status ?? this.status,
      errorMessage: errorMessage,
    );
  }

  /// 表单是否有效（可保存）
  bool get canSave {
    return imageFile != null && category.isNotEmpty && name.isNotEmpty;
  }
}

/// 录入流程 Notifier
class AddItemNotifier extends StateNotifier<AddItemState> {
  final ImageService _imageService;
  final MattingService _mattingService;
  final WardrobeRepository _repository;
  final Ref _ref;

  AddItemNotifier(
    this._imageService,
    this._mattingService,
    this._repository,
    this._ref,
  ) : super(const AddItemState());

  /// 从相册选择
  Future<void> pickFromGallery() async {
    final file = await _imageService.pickFromGallery();
    if (file == null) return;

    state = state.copyWith(imageFile: file, step: AddItemStep.cropping);
  }

  /// 拍照
  Future<void> takePhoto() async {
    final file = await _imageService.takePhoto();
    if (file == null) return;

    state = state.copyWith(imageFile: file, step: AddItemStep.cropping);
  }

  /// 用 MODNet 抠图，把背景填充成白色
  ///
  /// 替代原来的 1:1 正方形裁剪（image_cropper 在鸿蒙上闪退）。
  Future<void> matteImage() async {
    if (state.imageFile == null) return;

    state = state.copyWith(isLoading: true);
    try {
      final matted = await _mattingService.removeBackground(state.imageFile!);
      state = state.copyWith(
        imageFile: matted,
        step: AddItemStep.fillInfo,
        isLoading: false,
        errorMessage: null,
        name: _defaultName(),
      );
    } catch (e, s) {
      // 抠图失败：保留当前图片和界面，给用户人话引导；技术细节记日志
      ErrorLog.record('抠图', e, s);
      state = state.copyWith(
        isLoading: false,
        errorMessage: '抠图失败，请重试，或改用「手动抠图」',
      );
    }
  }

  /// 接管「手动抠图」页面返回的结果，直接进入填写信息
  ///
  /// 手动抠图的交互在 ManualMattePage 里完成，这里只负责收结果。
  void applyMatteResult(File file) {
    state = state.copyWith(
      imageFile: file,
      step: AddItemStep.fillInfo,
      isLoading: false,
      errorMessage: null,
      name: _defaultName(),
    );
  }

  /// 从填写信息退回抠图环节（保留已选图片，方便换一种抠法重试）
  void backToCropping() {
    state = state.copyWith(step: AddItemStep.cropping, errorMessage: null);
  }

  /// 跳过抠图，直接用当前图片（可能是旋转后的）进入填写信息
  ///
  /// 抠图不是必须的：用户可保留原图直接录入。
  void skipMatte() {
    if (state.imageFile == null) return;
    state = state.copyWith(
      step: AddItemStep.fillInfo,
      errorMessage: null,
      name: _defaultName(),
    );
  }

  /// 自动生成的默认名称
  ///
  /// 用户已经填过名字时保留原名 —— 否则从填写页退回重抠一次，名字就被冲掉了。
  String _defaultName() {
    if (state.name.trim().isNotEmpty) return state.name;
    final now = DateTime.now();
    return '新衣服 ${now.month}月${now.day}日';
  }

  /// 旋转图片（顺时针 90°），用于照片朝向不正时
  Future<void> rotateImage() async {
    if (state.imageFile == null) return;

    state = state.copyWith(isLoading: true);
    try {
      final rotated = await _imageService.rotateImage(state.imageFile!);
      state = state.copyWith(imageFile: rotated, isLoading: false);
    } catch (e, s) {
      ErrorLog.record('旋转图片', e, s);
      state = state.copyWith(isLoading: false, errorMessage: '旋转失败，请重试');
    }
  }

  /// 重新选择图片
  void backToSelectSource() {
    state = state.copyWith(
      step: AddItemStep.selectSource,
      clearImage: true,
      clearForm: true,
    );
  }

  /// 保存衣物
  Future<bool> save() async {
    if (!state.canSave) return false;

    state = state.copyWith(step: AddItemStep.saving, isLoading: true);

    try {
      final userId = _ref.read(currentUserIdProvider);
      if (userId == null) {
        throw Exception('未登录，无法保存');
      }

      // 1. 上传图片到云端
      final imageUploadService = ImageUploadService();
      final imageUrl = await imageUploadService.uploadItemImage(
        userId: userId,
        file: state.imageFile!,
      );

      // 2. 创建衣物记录
      final item = ClothingItem(
        id: '',
        userId: userId,
        name: state.name,
        category: state.category,
        subCategory: state.subCategory,
        imageUrl: imageUrl, // 云端 URL
        originalImageUrl: imageUrl,
        colors: state.colors
            .map((c) => ColorInfo(name: c, hex: fromName(c)))
            .toList(),
        styleTags: [...state.styleTags, ...state.customStyleTags],
        seasonTags: state.seasonTags,
        occasionTags: state.occasionTags,
        wearFrequency: state.wearFrequency,
        brand: state.brand,
        price: state.price,
        status: state.status,
        createdAt: DateTime.now(),
      );

      await _repository.addItem(item);

      // 刷新衣橱列表
      _ref.read(wardrobeListProvider.notifier).loadItems();

      return true;
    } catch (e, s) {
      ErrorLog.record('保存衣物', e, s);
      state = state.copyWith(isLoading: false, errorMessage: '保存失败，请检查网络后重试');
      return false;
    }
  }

  /// 更新分类
  void setCategory(String category) {
    state = state.copyWith(category: category, subCategory: null);
  }

  /// 更新子分类
  void setSubCategory(String? subCategory) {
    state = state.copyWith(subCategory: subCategory);
  }

  /// 更新名称
  void setName(String name) {
    state = state.copyWith(name: name);
  }

  /// 切换颜色选择
  void toggleColor(String colorName) {
    final colors = List<String>.from(state.colors);
    if (colors.contains(colorName)) {
      colors.remove(colorName);
    } else {
      colors.add(colorName);
    }
    state = state.copyWith(colors: colors);
  }

  /// 切换风格标签
  void toggleStyleTag(String tag) {
    final tags = List<String>.from(state.styleTags);
    if (tags.contains(tag)) {
      tags.remove(tag);
    } else {
      tags.add(tag);
    }
    state = state.copyWith(styleTags: tags);
  }

  /// 设置季节
  void setSeason(String season) {
    final tags = List<String>.from(state.seasonTags);
    if (tags.contains(season)) {
      tags.remove(season);
    } else {
      tags.add(season);
    }
    state = state.copyWith(seasonTags: tags);
  }

  /// 设置品牌
  void setBrand(String? brand) {
    state = state.copyWith(brand: brand);
  }

  /// 切换场合标签
  void toggleOccasion(String occasion) {
    final tags = List<String>.from(state.occasionTags);
    if (tags.contains(occasion)) {
      tags.remove(occasion);
    } else {
      tags.add(occasion);
    }
    state = state.copyWith(occasionTags: tags);
  }

  /// 设置穿着频率
  void setWearFrequency(String? frequency) {
    state = state.copyWith(
      wearFrequency: state.wearFrequency == frequency ? null : frequency,
    );
  }

  /// 设置价格
  void setPrice(double? price) {
    state = state.copyWith(price: price);
  }

  /// 新增自定义标签
  void addCustomTag(String tag) {
    state = state.copyWith(customStyleTags: [...state.customStyleTags, tag]);
  }
}

/// 从色系名称到代表色值的映射
String fromName(String name) {
  const map = {
    '黑色系': '#1A1A1A',
    '白色系': '#FFFFFF',
    '灰色系': '#9E9E9E',
    '红色系': '#D32F2F',
    '橙色系': '#F57C00',
    '黄色系': '#FBC02D',
    '绿色系': '#388E3C',
    '蓝色系': '#1976D2',
    '紫色系': '#7B1FA2',
    '粉色系': '#F48FB1',
    '棕色系': '#6D4C41',
    '米色系': '#F0E6D6',
    '牛仔蓝': '#5B7FA6',
    '卡其色系': '#C9B18B',
    '彩色': '#E91E63',
  };
  return map[name] ?? '#9E9E9E';
}

final addItemProvider =
    StateNotifierProvider.autoDispose<AddItemNotifier, AddItemState>((ref) {
      final imageService = ImageService();
      final mattingService = MattingService();
      final repository = ref.watch(wardrobeRepositoryProvider);
      return AddItemNotifier(imageService, mattingService, repository, ref);
    });

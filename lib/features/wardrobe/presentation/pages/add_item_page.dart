import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/constants/category_data.dart';
import '../../../../../core/constants/style_data.dart';
import '../../../../../core/constants/color_data.dart';
import '../../../../../core/theme/app_theme.dart';
import '../../../../../shared/widgets/tag_chip.dart';
import '../../../../../shared/widgets/color_swatch.dart' as widgets;
import '../../../../../shared/widgets/loading_overlay.dart';
import '../../../../../shared/widgets/customizable_tag_selector.dart';
import '../../../auth/presentation/providers/gender_provider.dart'
    show isMaleProvider;
import '../providers/add_item_provider.dart';
import 'manual_matte_page.dart';

/// 添加衣物页面
///
/// 流程：拍照/相册 → 裁剪 → 填写信息 → 保存
/// 分类：大标签 → 点开选小标签
class AddItemPage extends ConsumerStatefulWidget {
  const AddItemPage({super.key});

  @override
  ConsumerState<AddItemPage> createState() => _AddItemPageState();
}

class _AddItemPageState extends ConsumerState<AddItemPage> {
  final _nameController = TextEditingController();
  final _brandController = TextEditingController();
  final _priceController = TextEditingController();

  /// 缓存性别和分类列表
  bool _isMale = true;
  List<String> _categories = CategoryData.mainCategories;

  @override
  void dispose() {
    _nameController.dispose();
    _brandController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(addItemProvider);
    final notifier = ref.read(addItemProvider.notifier);

    // 统一口径：与编辑页一致，unknown 时显示全部分类
    _isMale = ref.watch(isMaleProvider);
    _categories = CategoryData.getMainCategoriesForGender(isMale: _isMale);

    if (_nameController.text.isEmpty && state.name.isNotEmpty) {
      _nameController.text = state.name;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('添加衣服'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () {
            if (state.step == AddItemStep.fillInfo) {
              // 退回抠图环节：保留图片，方便换一种抠法重试
              notifier.backToCropping();
            } else if (state.step == AddItemStep.cropping) {
              notifier.backToSelectSource();
            } else {
              Navigator.of(context).pop();
            }
          },
        ),
        actions: state.step == AddItemStep.fillInfo
            ? [
                TextButton(
                  onPressed: state.canSave ? () => _onSave(notifier) : null,
                  child: const Text('保存'),
                ),
              ]
            : null,
      ),
      body: _buildBody(state, notifier),
    );
  }

  Widget _buildBody(AddItemState state, AddItemNotifier notifier) {
    if (state.step == AddItemStep.saving) {
      return const LoadingOverlay(message: '正在保存...');
    }
    if (state.step == AddItemStep.selectSource) {
      return _buildSourceSelector(notifier);
    }
    if (state.step == AddItemStep.cropping && state.imageFile != null) {
      return _buildCropPreview(state, notifier);
    }
    if (state.step == AddItemStep.fillInfo && state.imageFile != null) {
      return _buildInfoForm(state, notifier);
    }
    return const SizedBox.shrink();
  }

  Widget _buildSourceSelector(AddItemNotifier notifier) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.add_a_photo_outlined,
            size: 80,
            color: AppTheme.primaryColor.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 24),
          Text('添加衣服照片', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 32),
          SizedBox(
            width: 220,
            child: ElevatedButton.icon(
              onPressed: () => notifier.takePhoto(),
              icon: const Icon(Icons.camera_alt),
              label: const Text('拍照'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: 220,
            child: OutlinedButton.icon(
              onPressed: () => notifier.pickFromGallery(),
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('从相册选择'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCropPreview(AddItemState state, AddItemNotifier notifier) {
    return SingleChildScrollView(
      child: Column(
        children: [
          Stack(
            children: [
              Container(
                width: double.infinity,
                height: 350,
                color: Colors.grey.shade100,
                child: Image.file(state.imageFile!, fit: BoxFit.contain),
              ),
              if (state.isLoading)
                Positioned.fill(
                  child: Container(
                    color: Colors.black54,
                    child: const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(color: Colors.white),
                          SizedBox(height: 12),
                          Text(
                            '抠图中，请稍候...',
                            style: TextStyle(color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            '纯色背景用「智能抠图」；背景复杂就用「手动抠图」描一圈',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (state.errorMessage != null) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                state.errorMessage!,
                style: const TextStyle(color: Colors.red, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ),
          ],
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    OutlinedButton.icon(
                      onPressed: state.isLoading
                          ? null
                          : () => notifier.backToSelectSource(),
                      icon: const Icon(Icons.refresh),
                      label: const Text('重新选择'),
                    ),
                    OutlinedButton.icon(
                      onPressed: state.isLoading
                          ? null
                          : () => notifier.rotateImage(),
                      icon: const Icon(Icons.rotate_right),
                      label: const Text('旋转'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ElevatedButton.icon(
                      onPressed: state.isLoading
                          ? null
                          : () => notifier.matteImage(),
                      icon: const Icon(Icons.auto_fix_high, size: 18),
                      label: const Text('智能抠图'),
                    ),
                    ElevatedButton.icon(
                      onPressed: state.isLoading
                          ? null
                          : () => _openManualMatte(),
                      icon: const Icon(Icons.gesture, size: 18),
                      label: const Text('手动抠图'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: AppTheme.primaryColor,
                        side: BorderSide(color: AppTheme.primaryColor),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // 跳过抠图：抠图不是必须的，可直接用原图录入
          TextButton.icon(
            onPressed: state.isLoading ? null : notifier.skipMatte,
            icon: const Icon(Icons.skip_next, size: 18),
            label: const Text('跳过抠图，直接用原图'),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoForm(AddItemState state, AddItemNotifier notifier) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 保存失败等错误持久显示
          if (state.errorMessage != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Text(
                state.errorMessage!,
                style: const TextStyle(color: Colors.red, fontSize: 13),
              ),
            ),
            const SizedBox(height: 12),
          ],
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(
                state.imageFile!,
                width: 120,
                height: 120,
                fit: BoxFit.cover,
              ),
            ),
          ),
          const SizedBox(height: 24),

          // === 名称 ===
          TextFormField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: '名称',
              hintText: '给这件衣服起个名字',
            ),
            onChanged: notifier.setName,
          ),
          const SizedBox(height: 20),

          // === 分类：大标签 ===
          _buildSectionTitle('分类'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _categories.map((cat) {
              final isSelected = state.category == cat;
              return TagChip(
                label: cat,
                isSelected: isSelected,
                onSelected: (_) => notifier.setCategory(cat),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),

          // === 小标签（选中大标签后展开）===
          if (state.category.isNotEmpty) ...[
            _buildSectionTitle('${state.category} · 选具体款式'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children:
                  CategoryData.getSubCategoriesForGender(
                    mainCategory: state.category,
                    isMale: _isMale,
                  ).map((sub) {
                    return TagChip(
                      label: sub,
                      isSelected: state.subCategory == sub,
                      onSelected: (_) => notifier.setSubCategory(sub),
                    );
                  }).toList(),
            ),
            const SizedBox(height: 20),
          ],

          // === 颜色 / 色系 ===
          _buildSectionTitle('颜色'),
          const SizedBox(height: 8),
          widgets.ColorSwatch(
            colorMap: ColorData.presetColors,
            multiSelect: true,
            selectedColors: state.colors,
            onColorSelected: notifier.toggleColor,
          ),
          const SizedBox(height: 20),

          // === 季节 ===
          _buildSectionTitle('季节'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: CategoryData.seasonTags.map((season) {
              return TagChip(
                label: season,
                isSelected: state.seasonTags.contains(season),
                onSelected: (_) => notifier.setSeason(season),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),

          // === 场合 ===
          _buildSectionTitle('场合'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: CategoryData.occasionTags.map((occasion) {
              return TagChip(
                label: occasion,
                isSelected: state.occasionTags.contains(occasion),
                onSelected: (_) => notifier.toggleOccasion(occasion),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),

          // === 风格 ===
          _buildSectionTitle('风格'),
          const SizedBox(height: 8),
          CustomizableTagSelector(
            allTags: [...StyleData.presetStyles, ...state.customStyleTags],
            selectedTags: state.styleTags,
            onTagToggled: notifier.toggleStyleTag,
            onTagAdded: notifier.addCustomTag,
          ),
          const SizedBox(height: 20),

          // === 穿着频率 ===
          _buildSectionTitle('穿着频率'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: CategoryData.wearFrequency.map((freq) {
              return TagChip(
                label: freq,
                isSelected: state.wearFrequency == freq,
                onSelected: (_) => notifier.setWearFrequency(freq),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),

          // === 品牌 ===
          TextFormField(
            controller: _brandController,
            decoration: const InputDecoration(
              labelText: '品牌（可选）',
              hintText: '如优衣库、ZARA',
            ),
            onChanged: (v) => notifier.setBrand(v.isEmpty ? null : v),
          ),
          const SizedBox(height: 16),

          // === 价格 ===
          TextFormField(
            controller: _priceController,
            decoration: const InputDecoration(
              labelText: '价格（可选）',
              hintText: '购买时花了多少钱',
              suffixText: '元',
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (v) {
              final price = double.tryParse(v);
              notifier.setPrice(price);
            },
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: Theme.of(
        context,
      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    );
  }

  /// 打开手动抠图页，拿到结果后直接进入填写信息
  Future<void> _openManualMatte() async {
    final file = ref.read(addItemProvider).imageFile;
    if (file == null) return;

    final result = await Navigator.of(context).push<File>(
      MaterialPageRoute(builder: (_) => ManualMattePage(imageFile: file)),
    );
    if (!mounted || result == null) return;

    // 重新取 notifier：push 期间 provider 可能已经重建
    ref.read(addItemProvider.notifier).applyMatteResult(result);
  }

  Future<void> _onSave(AddItemNotifier notifier) async {
    final success = await notifier.save();
    if (success && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('保存成功！')));
      Navigator.of(context).pop();
    } else if (mounted) {
      final errMsg = ref.read(addItemProvider).errorMessage;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(errMsg ?? '保存失败')));
    }
  }
}

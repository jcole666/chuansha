import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/constants/category_data.dart';
import '../../../../../core/constants/style_data.dart';
import '../../../../../core/constants/color_data.dart';
import '../../../../../shared/widgets/tag_chip.dart';
import '../../../../../shared/widgets/color_swatch.dart' as widgets;
import '../../../../../shared/widgets/loading_overlay.dart';
import '../../../../../domain/enums/clothing_status.dart';
import '../../../../../data/models/color_info.dart';
import '../../../auth/presentation/providers/gender_provider.dart'
    show isMaleProvider;
import '../providers/wardrobe_provider.dart';

/// 衣物编辑页
///
/// 复用录入页的信息编辑区域，预填现有数据
class EditItemPage extends ConsumerStatefulWidget {
  final String itemId;

  const EditItemPage({super.key, required this.itemId});

  @override
  ConsumerState<EditItemPage> createState() => _EditItemPageState();
}

class _EditItemPageState extends ConsumerState<EditItemPage> {
  final _nameController = TextEditingController();
  final _brandController = TextEditingController();
  final _priceController = TextEditingController();

  // 本地编辑状态
  late String _category;
  late String? _subCategory;
  late List<String> _colors;
  late List<String> _styleTags;
  late List<String> _seasonTags;
  late List<String> _occasionTags;
  late String? _wearFrequency;
  late ClothingStatus _status;
  bool _isSaving = false;
  bool _initialized = false;

  @override
  void dispose() {
    _nameController.dispose();
    _brandController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  void _initForm() {
    if (_initialized) return;
    final notifier = ref.read(wardrobeListProvider.notifier);
    final item = notifier.getItemById(widget.itemId);
    if (item == null) return;

    _category = item.category;
    _subCategory = item.subCategory;
    _colors = item.colors.map((c) => c.name).toList();
    _styleTags = List.from(item.styleTags);
    _seasonTags = List.from(item.seasonTags);
    _occasionTags = List.from(item.occasionTags);
    _wearFrequency = item.wearFrequency;
    _status = item.status;

    _nameController.text = item.name;
    _brandController.text = item.brand ?? '';
    _priceController.text = item.price?.toString() ?? '';

    _initialized = true;
  }

  bool get _canSave => _category.isNotEmpty && _nameController.text.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final notifier = ref.read(wardrobeListProvider.notifier);
    final item = notifier.getItemById(widget.itemId);

    if (item == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('衣物不存在')),
      );
    }

    _initForm();

    return Scaffold(
      appBar: AppBar(
        title: const Text('编辑'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          TextButton(
            onPressed: _canSave && !_isSaving ? _save : null,
            child: const Text('保存'),
          ),
        ],
      ),
      body: _isSaving
          ? const LoadingOverlay(message: '正在保存...')
          : _buildForm(context, item),
    );
  }

  Widget _buildForm(BuildContext context, dynamic item) {
    // 统一口径：与录入页一致，unknown 时显示全部分类
    final isMale = ref.watch(isMaleProvider);
    final categories = CategoryData.getMainCategoriesForGender(isMale: isMale);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // === 名称 ===
          TextFormField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: '名称',
              hintText: '给这件衣服起个名字',
            ),
          ),
          const SizedBox(height: 16),

          // === 分类 ===
          _buildSectionTitle('主分类'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: categories.map((cat) {
              return TagChip(
                label: cat,
                isSelected: _category == cat,
                onSelected: (_) {
                  setState(() {
                    _category = cat;
                    _subCategory = null;
                  });
                },
              );
            }).toList(),
          ),
          if (_category.isNotEmpty) ...[
            const SizedBox(height: 12),
            _buildSectionTitle('子分类'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children:
                  CategoryData.getSubCategoriesForGender(
                    mainCategory: _category,
                    isMale: isMale,
                  ).map((sub) {
                    return TagChip(
                      label: sub,
                      isSelected: _subCategory == sub,
                      onSelected: (_) {
                        setState(() {
                          _subCategory = _subCategory == sub ? null : sub;
                        });
                      },
                    );
                  }).toList(),
            ),
          ],
          const SizedBox(height: 20),

          // === 颜色 ===
          _buildSectionTitle('颜色'),
          const SizedBox(height: 8),
          widgets.ColorSwatch(
            colorMap: ColorData.presetColors,
            multiSelect: true,
            selectedColors: _colors,
            onColorSelected: (color) {
              setState(() {
                if (_colors.contains(color)) {
                  _colors.remove(color);
                } else {
                  _colors.add(color);
                }
              });
            },
          ),
          const SizedBox(height: 20),

          // === 风格 ===
          _buildSectionTitle('风格标签'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: StyleData.presetStyles.map((style) {
              return TagChip(
                label: style,
                isSelected: _styleTags.contains(style),
                onSelected: (_) {
                  setState(() {
                    if (_styleTags.contains(style)) {
                      _styleTags.remove(style);
                    } else {
                      _styleTags.add(style);
                    }
                  });
                },
              );
            }).toList(),
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
                isSelected: _seasonTags.contains(season),
                onSelected: (_) {
                  setState(() {
                    if (_seasonTags.contains(season)) {
                      _seasonTags.remove(season);
                    } else {
                      _seasonTags.add(season);
                    }
                  });
                },
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
                isSelected: _occasionTags.contains(occasion),
                onSelected: (_) {
                  setState(() {
                    if (_occasionTags.contains(occasion)) {
                      _occasionTags.remove(occasion);
                    } else {
                      _occasionTags.add(occasion);
                    }
                  });
                },
              );
            }).toList(),
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
                isSelected: _wearFrequency == freq,
                onSelected: (_) {
                  setState(() {
                    _wearFrequency = _wearFrequency == freq ? null : freq;
                  });
                },
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
          ),
          const SizedBox(height: 20),

          // === 状态 ===
          _buildSectionTitle('衣物状态'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: ClothingStatus.values.map((status) {
              return TagChip(
                label: status.label,
                isSelected: _status == status,
                onSelected: (_) {
                  setState(() => _status = status);
                },
              );
            }).toList(),
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

  Future<void> _save() async {
    setState(() => _isSaving = true);

    try {
      final notifier = ref.read(wardrobeListProvider.notifier);
      final item = notifier.getItemById(widget.itemId);
      if (item == null) return;

      final updated = item.copyWith(
        name: _nameController.text,
        category: _category,
        subCategory: _subCategory,
        colors: _colors
            .map(
              (c) => ColorInfo(name: c, hex: ColorData.getHex(c) ?? '#808080'),
            )
            .toList(),
        styleTags: _styleTags,
        seasonTags: _seasonTags,
        occasionTags: _occasionTags,
        wearFrequency: _wearFrequency,
        brand: _brandController.text.trim().isEmpty
            ? null
            : _brandController.text.trim(),
        price: double.tryParse(_priceController.text.trim()),
        status: _status,
        updatedAt: DateTime.now(),
        // 用户清空输入框时要真的把字段置 null。
        // 光传 null 是不行的（copyWith 会当成"没传"而保留旧值），
        // 所以这里用显式 clear 开关 —— 这是之前「清不掉品牌/价格」的根因。
        clearBrand: _brandController.text.trim().isEmpty,
        clearPrice: double.tryParse(_priceController.text.trim()) == null,
        clearSubCategory: _subCategory == null,
        clearWearFrequency: _wearFrequency == null,
      );

      // 用返回值判断真实结果：失败时 notifier 会 rethrow，
      // 只有成功才提示「保存成功」并关闭页面。
      final ok = await notifier.updateItem(updated);
      if (!mounted) return;

      if (ok) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('保存成功')));
        Navigator.of(context).pop();
      } else {
        final msg = ref.read(wardrobeListProvider).errorMessage ?? '保存失败';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('保存失败：$e')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}

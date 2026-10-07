import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/constants/category_data.dart';
import '../../../../../core/constants/style_data.dart';
import '../../../../../core/constants/color_data.dart';
import '../../../../../shared/widgets/tag_chip.dart';
import '../../../../../shared/widgets/color_swatch.dart' as widgets;
import '../../../../../shared/widgets/empty_state.dart';
import '../../../../../shared/widgets/loading_overlay.dart';
import '../../../../../shared/widgets/item_image.dart';
import '../../../../../domain/enums/clothing_status.dart';
import '../../../../../data/models/clothing_item.dart';
import '../../../../../data/models/color_info.dart';
import '../../../../../services/image_upload_service.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../auth/presentation/providers/gender_provider.dart'
    show isMaleProvider;
import '../providers/wardrobe_provider.dart';
import 'change_item_image_page.dart';

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

  /// 用户新选的图片（还没上传）。
  /// 为 null 表示没换图，保存时沿用原图。
  File? _newImageFile;

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
        body: const EmptyState(
          icon: Icons.checkroom_outlined,
          title: '衣物不存在',
          subtitle: '它可能已被你移除',
        ),
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

  /// 打开换图流程，拿到结果后暂存，保存时统一上传
  Future<void> _pickNewImage() async {
    if (_isSaving) return;
    final file = await Navigator.of(context).push<File>(
      MaterialPageRoute(builder: (_) => const ChangeItemImagePage()),
    );
    if (file == null || !mounted) return;
    setState(() => _newImageFile = file);
  }

  /// 顶部图片区：显示当前图（或新选的图），点击可换图
  Widget _buildImageSection(ClothingItem item) {
    return Center(
      child: Column(
        children: [
          GestureDetector(
            onTap: _pickNewImage,
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 140,
                    height: 140,
                    child: _newImageFile != null
                        ? Image.file(_newImageFile!, fit: BoxFit.cover)
                        : ItemImage(
                            imageUrl: item.imageUrl,
                            fit: BoxFit.cover,
                            thumbnailWidth: 300,
                          ),
                  ),
                ),
                // 换图角标
                Positioned(
                  right: 6,
                  bottom: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.photo_camera, size: 13, color: Colors.white),
                        SizedBox(width: 4),
                        Text(
                          '换图',
                          style: TextStyle(color: Colors.white, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_newImageFile != null) ...[
            const SizedBox(height: 6),
            Text(
              '保存后生效',
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: Colors.orange.shade700),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildForm(BuildContext context, ClothingItem item) {
    // 统一口径：与录入页一致，unknown 时显示全部分类
    final isMale = ref.watch(isMaleProvider);
    final categories = CategoryData.getMainCategoriesForGender(isMale: isMale);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // === 图片（点击可换图 / 重新抠图）===
          _buildImageSection(item),
          const SizedBox(height: 24),

          // === 名称 ===
          TextFormField(
            controller: _nameController,
            // onChanged 里 setState 让「保存」按钮随输入刷新，
            // 否则名称从空变成有值时按钮仍是灰的。
            onChanged: (_) => setState(() {}),
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

    // 换过图时：记录旧图地址，等落库成功后再清理，避免存储里堆孤儿文件
    String? oldImageUrl;
    String? uploadedUrl;

    try {
      final notifier = ref.read(wardrobeListProvider.notifier);
      final item = notifier.getItemById(widget.itemId);
      if (item == null) return;

      // 先上传新图拿到 URL，再落库 —— 顺序反了会留下没被引用的图片
      final newFile = _newImageFile;
      if (newFile != null) {
        final userId = ref.read(currentUserIdProvider);
        if (userId == null) throw Exception('未登录，无法上传图片');
        uploadedUrl = await ImageUploadService().uploadItemImage(
          userId: userId,
          file: newFile,
        );
        oldImageUrl = item.imageUrl;
      }

      final updated = item.copyWith(
        // uploadedUrl 为 null 时（没换图）保留原图
        imageUrl: uploadedUrl,
        originalImageUrl: uploadedUrl,
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
        // 落库成功后再删旧图；删不掉不影响用户（只是留个孤儿文件）
        if (oldImageUrl != null && oldImageUrl.isNotEmpty) {
          await ImageUploadService().deleteItemImage(oldImageUrl);
        }
        if (!mounted) return;
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

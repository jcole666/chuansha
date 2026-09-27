import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../../../../core/theme/app_theme.dart';
import '../../../../../shared/widgets/item_image.dart';
import '../../../../../data/models/outfit.dart';
import '../../../../../data/models/clothing_item.dart';
import '../../../wardrobe/presentation/providers/wardrobe_provider.dart';
import '../providers/outfit_provider.dart';

/// Outfit 搭配列表页面
///
/// 作为搭配页的一个 Tab 使用（showAppBar=false 时不显示自己的标题栏）
class OutfitListPage extends ConsumerStatefulWidget {
  /// 是否显示自己的 AppBar（作为 Tab 嵌入时传 false）
  final bool showAppBar;

  const OutfitListPage({super.key, this.showAppBar = true});

  @override
  ConsumerState<OutfitListPage> createState() => _OutfitListPageState();
}

class _OutfitListPageState extends ConsumerState<OutfitListPage> {
  @override
  void initState() {
    super.initState();
    // 首次进入加载搭配列表（此前从未有人调用 load，导致列表永远为空）
    Future.microtask(() {
      ref.read(outfitListProvider.notifier).load();
      // 搭配卡片需要根据 itemIds 反查衣物，确保衣橱数据已就绪
      ref.read(wardrobeListProvider.notifier).loadItems();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(outfitListProvider);
    final wardrobeState = ref.watch(wardrobeListProvider);
    final notifier = ref.read(outfitListProvider.notifier);

    return Scaffold(
      appBar: widget.showAppBar ? AppBar(title: const Text('搭配组合')) : null,
      body: state.outfits.isEmpty
          ? _buildEmpty(context, ref)
          : RefreshIndicator(
              onRefresh: () => notifier.load(),
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                itemCount: state.outfits.length,
                itemBuilder: (_, index) {
                  final outfit = state.outfits[index];
                  return _OutfitCard(
                    outfit: outfit,
                    items: state.getItemsForOutfit(outfit, wardrobeState.allItems),
                    onDelete: () => _confirmDelete(outfit),
                  );
                },
              ),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showCreateDialog(context, ref),
        child: const Icon(Icons.add),
      ),
    );
  }

  /// 删除搭配（先二次确认，失败时明确提示）
  Future<void> _confirmDelete(Outfit outfit) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除这个搭配？'),
        content: Text('将删除「${outfit.name}」，删除后无法恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final ok = await ref.read(outfitListProvider.notifier).deleteOutfit(outfit.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? '已删除「${outfit.name}」' : '删除失败，请检查网络后重试')),
    );
  }

  Widget _buildEmpty(BuildContext context, WidgetRef ref) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.auto_awesome_mosaic, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text('来创建一个搭配组合吧', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text('把多件衣服搭配成一套', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => _showCreateDialog(context, ref),
            icon: const Icon(Icons.add),
            label: const Text('新建搭配'),
          ),
        ],
      ),
    );
  }

  Future<void> _showCreateDialog(BuildContext context, WidgetRef ref) async {
    final notifier = ref.read(outfitListProvider.notifier);
    final allItems = ref.read(wardrobeListProvider).allItems;

    if (allItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('衣橱里还没有衣服，先录入几件再搭配吧')),
      );
      return;
    }

    final outfit = await showDialog<Outfit>(
      context: context,
      builder: (ctx) => _CreateOutfitDialog(allItems: allItems),
    );
    if (outfit == null) return;

    final ok = await notifier.addOutfit(outfit);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? '搭配已保存' : '保存失败，请检查网络后重试')),
    );
  }
}

/// Outfit 卡片
class _OutfitCard extends StatelessWidget {
  final Outfit outfit;
  final List<ClothingItem> items;
  final VoidCallback onDelete;

  const _OutfitCard({required this.outfit, required this.items, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            SizedBox(
              width: 80, height: 80,
              child: Row(
                children: items.take(3).map((item) {
                  return Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: ItemImage(imageUrl: item.imageUrl,
                          fit: BoxFit.cover),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(outfit.name, style: Theme.of(context).textTheme.titleMedium),
                  if (outfit.description != null)
                    Text(outfit.description!, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 4),
                  Text('${outfit.itemIds.length} 件 · 穿过 ${outfit.wearCount} 次',
                      style: Theme.of(context).textTheme.labelSmall),
                ],
              ),
            ),
            IconButton(icon: const Icon(Icons.delete_outline, size: 20), onPressed: onDelete),
          ],
        ),
      ),
    );
  }
}

/// 创建搭配对话框
///
/// 保存时通过 `Navigator.pop` 把新建的 Outfit 交回调用方，
/// user_id 由 notifier 在落库时填充（这里不写死）。
class _CreateOutfitDialog extends StatefulWidget {
  final List<ClothingItem> allItems;

  const _CreateOutfitDialog({required this.allItems});

  @override
  State<_CreateOutfitDialog> createState() => _CreateOutfitDialogState();
}

class _CreateOutfitDialogState extends State<_CreateOutfitDialog> {
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  final _selectedIds = <String>{};
  final _uuid = const Uuid();

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('新建搭配'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(controller: _nameController,
                decoration: const InputDecoration(hintText: '搭配名称', isDense: true)),
            const SizedBox(height: 8),
            TextField(controller: _descController,
                decoration: const InputDecoration(hintText: '描述（可选）', isDense: true)),
            const SizedBox(height: 12),
            Text('选择衣服：', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            SizedBox(
              height: 60,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: widget.allItems.length,
                itemBuilder: (_, i) {
                  final item = widget.allItems[i];
                  final selected = _selectedIds.contains(item.id);
                  return GestureDetector(
                    onTap: () => setState(() {
                      selected ? _selectedIds.remove(item.id) : _selectedIds.add(item.id);
                    }),
                    child: Container(
                      width: 56, margin: const EdgeInsets.only(right: 6),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: selected ? AppTheme.primaryColor : Colors.grey.shade200,
                          width: selected ? 2 : 1,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(7),
                        child: ItemImage(imageUrl: item.imageUrl, fit: BoxFit.cover),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
        ElevatedButton(
          onPressed: _selectedIds.length >= 2 && _nameController.text.trim().isNotEmpty
              ? () => Navigator.of(context).pop(Outfit(
                    id: _uuid.v4(),
                    userId: '', // 落库时由 notifier 用当前登录用户覆盖
                    name: _nameController.text.trim(),
                    description: _descController.text.trim().isNotEmpty
                        ? _descController.text.trim()
                        : null,
                    itemIds: _selectedIds.toList(),
                    createdAt: DateTime.now(),
                  ))
              : null,
          child: const Text('保存'),
        ),
      ],
    );
  }
}

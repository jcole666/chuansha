import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

/// 可添加自定义标签的标签选择器
///
/// 预设标签 + 底部输入框可添加自定义标签
class CustomizableTagSelector extends StatefulWidget {
  /// 全部可选标签（预设 + 已自定义的）
  final List<String> allTags;

  /// 当前已选中的标签
  final List<String> selectedTags;

  /// 选中/取消回调
  final ValueChanged<String> onTagToggled;

  /// 新增自定义标签回调
  final ValueChanged<String>? onTagAdded;

  const CustomizableTagSelector({
    super.key,
    required this.allTags,
    required this.selectedTags,
    required this.onTagToggled,
    this.onTagAdded,
  });

  @override
  State<CustomizableTagSelector> createState() =>
      _CustomizableTagSelectorState();
}

class _CustomizableTagSelectorState extends State<CustomizableTagSelector> {
  final _customController = TextEditingController();
  bool _showInput = false;

  @override
  void dispose() {
    _customController.dispose();
    super.dispose();
  }

  void _addCustomTag() {
    final text = _customController.text.trim();
    if (text.isEmpty) return;

    // 去重
    if (widget.allTags.contains(text)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('标签「$text」已存在')));
      return;
    }

    widget.onTagAdded?.call(text);
    _customController.clear();
    setState(() => _showInput = false);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标签列表
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            ...widget.allTags.map((tag) {
              final isSelected = widget.selectedTags.contains(tag);
              return GestureDetector(
                onTap: () => widget.onTagToggled(tag),
                child: Chip(
                  label: Text(
                    tag,
                    style: TextStyle(
                      fontSize: 12,
                      color: isSelected ? Colors.white : null,
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                  ),
                  backgroundColor: isSelected
                      ? Theme.of(context).colorScheme.primary
                      : Colors.grey.shade100,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
              );
            }),
            // 添加按钮
            GestureDetector(
              onTap: () => setState(() => _showInput = !_showInput),
              child: Chip(
                label: Icon(
                  _showInput ? Icons.close : Icons.add,
                  size: 16,
                  color: AppTheme.primaryColor,
                ),
                backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.08),
                padding: EdgeInsets.zero,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ),

        // 自定义标签输入框
        if (_showInput) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _customController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: '输入新标签名称',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                  onSubmitted: (_) => _addCustomTag(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: _addCustomTag,
                icon: const Icon(Icons.check, size: 18),
                style: IconButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(36, 36),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

// 标签 Chip 列表组件
// 支持只读展示模式和编辑模式（添加/删除标签）
// 最多 10 个标签

import 'package:flutter/material.dart';

// 预定义标签列表（北美门店常用标签）
const kPredefinedTags = [
  'WiFi',
  'Free WiFi',
  'Parking',
  'Wheelchair Accessible',
  'Pet Friendly',
  'Outdoor Seating',
  'Takeout',
  'Delivery',
  'Reservations',
];

const int kMaxTags = 10;

// ============================================================
// TagChipList — 标签 Chip 列表
// readOnly=true 时只展示，不允许编辑
// readOnly=false 时允许点击删除，并显示"Add Tag"按钮
// ============================================================
class TagChipList extends StatelessWidget {
  const TagChipList({
    super.key,
    required this.tags,
    this.readOnly = false,
    this.onTagRemoved,
    this.onTagAdded,
  });

  final List<String> tags;
  final bool readOnly;

  /// 删除标签回调（readOnly=false 时有效）
  final void Function(String tag)? onTagRemoved;

  /// 添加标签回调（readOnly=false 时有效）
  final void Function(String tag)? onTagAdded;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        // 已有标签
        ...tags.map(
          (tag) => _TagChip(
            label: tag,
            readOnly: readOnly,
            onRemove: readOnly ? null : () => onTagRemoved?.call(tag),
          ),
        ),

        // 编辑模式下的"Add Tag"按钮（未达到上限时显示）
        if (!readOnly && tags.length < kMaxTags)
          _AddTagButton(
            existingTags: tags,
            onTagAdded: onTagAdded,
          ),
      ],
    );
  }
}

// ============================================================
// 单个标签 Chip
// ============================================================
class _TagChip extends StatelessWidget {
  const _TagChip({
    required this.label,
    required this.readOnly,
    this.onRemove,
  });

  final String label;
  final bool readOnly;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 10,
        right: readOnly ? 10 : 6,
        top: 6,
        bottom: 6,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3EE),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFFFCCB3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFFFF6B35),
              fontWeight: FontWeight.w500,
            ),
          ),
          // 删除按钮（编辑模式）
          if (!readOnly) ...[
            const SizedBox(width: 4),
            GestureDetector(
              onTap: onRemove,
              child: const Icon(
                Icons.close_rounded,
                size: 16,
                color: Color(0xFFFF6B35),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ============================================================
// "Add Tag" 按钮 — 弹出底部选择器选择预定义标签
// ============================================================
class _AddTagButton extends StatelessWidget {
  const _AddTagButton({
    required this.existingTags,
    this.onTagAdded,
  });

  final List<String> existingTags;
  final void Function(String tag)? onTagAdded;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showTagPicker(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: const Color(0xFFFF6B35),
            style: BorderStyle.solid,
          ),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.add_rounded,
              size: 16,
              color: Color(0xFFFF6B35),
            ),
            SizedBox(width: 4),
            Text(
              'Add Tag',
              style: TextStyle(
                fontSize: 13,
                color: Color(0xFFFF6B35),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 弹出底部标签选择器
  void _showTagPicker(BuildContext context) {
    // 过滤掉已选中的标签
    final availableTags = kPredefinedTags
        .where((t) => !existingTags.contains(t))
        .toList();

    if (availableTags.isEmpty) return;

    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _TagPickerSheet(
        availableTags: availableTags,
        onTagSelected: (tag) {
          Navigator.of(ctx).pop();
          onTagAdded?.call(tag);
        },
      ),
    );
  }
}

// ============================================================
// 标签选择底部弹窗
// ============================================================
class _TagPickerSheet extends StatelessWidget {
  const _TagPickerSheet({
    required this.availableTags,
    required this.onTagSelected,
  });

  final List<String> availableTags;
  final void Function(String tag) onTagSelected;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题栏
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Select a Tag',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                  color: const Color(0xFF666666),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // 可选标签网格
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: availableTags.map((tag) {
                return GestureDetector(
                  onTap: () => onTagSelected(tag),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8F9FA),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFEEEEEE)),
                    ),
                    child: Text(
                      tag,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF333333),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

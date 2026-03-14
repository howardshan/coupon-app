import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';

/// 商家特色标签组件
/// 使用 Wrap 布局展示商家特色（停车、WiFi、包厢等）
/// 每个标签自动映射对应图标
class StoreFeatureTags extends StatelessWidget {
  final List<String> tags;

  const StoreFeatureTags({
    super.key,
    required this.tags,
  });

  /// 根据标签名映射对应的 Material 图标
  IconData _iconForTag(String tag) {
    final lower = tag.toLowerCase();
    if (lower.contains('parking')) return Icons.local_parking;
    if (lower.contains('wifi')) return Icons.wifi;
    if (lower.contains('private room')) return Icons.meeting_room;
    if (lower.contains('large table')) return Icons.table_restaurant;
    if (lower.contains('reservation')) return Icons.event_available;
    if (lower.contains('baby chair')) return Icons.child_care;
    if (lower.contains('no smoking') || lower.contains('smoke')) {
      return Icons.smoke_free;
    }
    if (lower.contains('bar')) return Icons.local_bar;
    return Icons.label_outline;
  }

  @override
  Widget build(BuildContext context) {
    // 无标签时不占空间
    if (tags.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: tags.map((tag) => _TagChip(tag: tag, icon: _iconForTag(tag))).toList(),
      ),
    );
  }
}

/// 单个特色标签 Chip 子组件（私有）
class _TagChip extends StatelessWidget {
  final String tag;
  final IconData icon;

  const _TagChip({required this.tag, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppColors.textHint),
          const SizedBox(width: 3),
          Text(
            tag,
            style: const TextStyle(
              fontSize: 10,
              color: AppColors.textHint,
            ),
          ),
        ],
      ),
    );
  }
}

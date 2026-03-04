// 设置行组件
// 通用设置项：图标 + 标题 + 可选副标题 + 可选右侧 Widget（默认箭头）

import 'package:flutter/material.dart';

// ============================================================
// SettingsTile — 单条设置项
// ============================================================
class SettingsTile extends StatelessWidget {
  const SettingsTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.iconColor,
    this.iconBackgroundColor,
    this.showDivider = true,
    this.enabled = true,
  });

  /// 左侧图标
  final IconData icon;

  /// 标题文案
  final String title;

  /// 副标题（可选）
  final String? subtitle;

  /// 右侧自定义 Widget（不传则默认显示箭头）
  final Widget? trailing;

  /// 点击回调（null 时禁用点击效果）
  final VoidCallback? onTap;

  /// 图标颜色（默认 primary orange）
  final Color? iconColor;

  /// 图标背景颜色（默认橙色浅背景）
  final Color? iconBackgroundColor;

  /// 是否显示底部分隔线
  final bool showDivider;

  /// 是否可交互（false 时显示灰色）
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // 图标颜色：禁用时用灰色
    final effectiveIconColor = enabled
        ? (iconColor ?? const Color(0xFFFF6B35))
        : theme.disabledColor;

    // 图标背景色
    final effectiveBgColor = enabled
        ? (iconBackgroundColor ?? const Color(0xFFFF6B35).withValues(alpha: 0.1))
        : Colors.grey.withValues(alpha: 0.08);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                // --------------------------------------------------
                // 左侧图标容器
                // --------------------------------------------------
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: effectiveBgColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    icon,
                    size: 20,
                    color: effectiveIconColor,
                  ),
                ),
                const SizedBox(width: 12),

                // --------------------------------------------------
                // 标题 + 副标题（占满剩余空间）
                // --------------------------------------------------
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w500,
                          color: enabled
                              ? colorScheme.onSurface
                              : theme.disabledColor,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: enabled
                                ? colorScheme.onSurfaceVariant
                                : theme.disabledColor,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // --------------------------------------------------
                // 右侧：自定义 trailing 或默认箭头
                // --------------------------------------------------
                if (trailing != null)
                  trailing!
                else if (onTap != null)
                  Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: enabled
                        ? colorScheme.onSurfaceVariant
                        : theme.disabledColor,
                  ),
              ],
            ),
          ),
        ),
        // 分隔线（最后一项通常不显示，由父级控制）
        if (showDivider)
          Divider(
            height: 1,
            indent: 64, // 与标题对齐
            endIndent: 0,
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
      ],
    );
  }
}

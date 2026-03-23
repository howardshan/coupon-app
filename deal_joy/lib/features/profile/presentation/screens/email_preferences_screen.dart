import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/providers/email_preferences_provider.dart';
import '../../data/repositories/email_preferences_repository.dart';

class EmailPreferencesScreen extends ConsumerWidget {
  const EmailPreferencesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefsAsync = ref.watch(emailPreferencesProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Email Notifications'),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: prefsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 12),
              Text(
                'Failed to load preferences',
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () =>
                    ref.invalidate(emailPreferencesProvider),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (items) => items.isEmpty
            ? _EmptyState()
            : _PreferenceList(items: items),
      ),
    );
  }
}

// ── 列表 ────────────────────────────────────────────────────────────────────

class _PreferenceList extends ConsumerWidget {
  final List<EmailPreferenceItem> items;

  const _PreferenceList({required this.items});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 说明文案
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Text(
            "Choose which email notifications you'd like to receive. "
            'Changes are saved automatically.',
            style: TextStyle(
              fontSize: 14,
              color: AppColors.textSecondary,
              height: 1.5,
            ),
          ),
        ),

        // 开关卡片
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.surfaceVariant),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: [
              for (int i = 0; i < items.length; i++)
                _SwitchTile(
                  item: items[i],
                  isLast: i == items.length - 1,
                  onChanged: (val) => ref
                      .read(emailPreferencesProvider.notifier)
                      .toggle(items[i].code, val),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── 单行 ────────────────────────────────────────────────────────────────────

class _SwitchTile extends StatelessWidget {
  final EmailPreferenceItem item;
  final bool isLast;
  final ValueChanged<bool> onChanged;

  const _SwitchTile({
    required this.item,
    required this.isLast,
    required this.onChanged,
  });

  IconData _iconFor(String code) {
    switch (code) {
      case 'C3':
        return Icons.qr_code_scanner_outlined;
      case 'C4':
        return Icons.schedule_outlined;
      case 'C13':
        return Icons.chat_bubble_outline;
      default:
        return Icons.mail_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEnabled = item.enabled;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              // 图标
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: isEnabled
                      ? AppColors.primary.withValues(alpha: 0.1)
                      : AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  _iconFor(item.code),
                  size: 20,
                  color: isEnabled
                      ? AppColors.primary
                      : AppColors.textHint,
                ),
              ),
              const SizedBox(width: 12),

              // 文案
              Expanded(
                child: Text(
                  item.name,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: isEnabled
                        ? AppColors.textPrimary
                        : AppColors.textSecondary,
                  ),
                ),
              ),

              // Switch
              Switch.adaptive(
                value: isEnabled,
                activeColor: AppColors.primary,
                onChanged: onChanged,
              ),
            ],
          ),
        ),
        if (!isLast)
          Divider(
            height: 1,
            indent: 66,
            color: AppColors.surfaceVariant,
          ),
      ],
    );
  }
}

// ── 空状态（所有邮件类型均被全局关闭时）────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.mail_outline, size: 56, color: AppColors.textHint),
          const SizedBox(height: 12),
          Text(
            'No configurable email preferences',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 15),
          ),
        ],
      ),
    );
  }
}

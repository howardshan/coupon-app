import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../auth/domain/providers/auth_provider.dart';
import '../widgets/callback_sheet.dart';

/// 客服支持入口页 — 三个联系方式选项
class CustomerSupportScreen extends ConsumerWidget {
  const CustomerSupportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(currentUserProvider);
    final phone = userAsync.valueOrNull?.phone;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Customer Support'),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 1,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 头部说明
          const Padding(
            padding: EdgeInsets.only(bottom: 20),
            child: Text(
              'How would you like to reach us?',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
          ),

          // Email Us（打开系统邮件 或 复制 support 地址）
          _SupportOptionCard(
            icon: Icons.email_outlined,
            iconColor: AppColors.info,
            title: 'Email Us',
            subtitle: 'Send us an email and we\'ll respond within 24 hours',
            onTap: () => _showEmailOptions(context),
          ),
          const SizedBox(height: 12),

          // Call Back Later
          _SupportOptionCard(
            icon: Icons.phone_callback_outlined,
            iconColor: AppColors.success,
            title: 'Call Back Later',
            subtitle: 'Leave your number and preferred time, we\'ll call you',
            onTap: () => _showCallbackSheet(context, phone),
          ),
          const SizedBox(height: 12),

          // Chat with Us
          _SupportOptionCard(
            icon: Icons.chat_outlined,
            iconColor: AppColors.primary,
            title: 'Chat with Us',
            subtitle: 'Get instant answers to common questions',
            onTap: () => context.push('/support/chat'),
          ),
        ],
      ),
    );
  }

  /// 发邮件：系统邮件应用 与 复制地址 二选一（无邮件客户端时仍可联系）
  void _showEmailOptions(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: Text(
                    'How would you like to email us?',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                ListTile(
                  leading: Icon(Icons.open_in_new, color: AppColors.info),
                  title: const Text('Open in Mail app'),
                  subtitle: const Text(
                    'Use your default email app',
                    style: TextStyle(fontSize: 12, color: AppColors.textHint),
                  ),
                  onTap: () async {
                    Navigator.of(sheetContext).pop();
                    final uri = Uri(
                      scheme: 'mailto',
                      path: AppConstants.supportEmail,
                      query: 'subject=DealJoy Support Request',
                    );
                    final canOpen = await canLaunchUrl(uri);
                    if (canOpen) {
                      await launchUrl(
                        uri,
                        mode: LaunchMode.externalApplication,
                      );
                    } else if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Could not open a mail app. Try “Copy email address” instead.',
                          ),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  },
                ),
                ListTile(
                  leading: Icon(Icons.copy, color: AppColors.textSecondary),
                  title: const Text('Copy email address'),
                  subtitle: Text(
                    AppConstants.supportEmail,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textHint,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () async {
                    await Clipboard.setData(
                      ClipboardData(text: AppConstants.supportEmail),
                    );
                    if (sheetContext.mounted) {
                      Navigator.of(sheetContext).pop();
                    }
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Email address copied to clipboard'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showCallbackSheet(BuildContext context, String? phone) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => CallbackSheet(initialPhone: phone),
    );
  }
}

/// 客服选项卡片
class _SupportOptionCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SupportOptionCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.surfaceVariant),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right,
                color: AppColors.textHint,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

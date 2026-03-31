import 'package:flutter/material.dart';
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

          // Email Us
          _SupportOptionCard(
            icon: Icons.email_outlined,
            iconColor: AppColors.info,
            title: 'Email Us',
            subtitle: 'Send us an email and we\'ll respond within 24 hours',
            onTap: () => _launchEmail(),
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

  Future<void> _launchEmail() async {
    final uri = Uri(
      scheme: 'mailto',
      path: AppConstants.supportEmail,
      query: 'subject=DealJoy Support Request',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
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

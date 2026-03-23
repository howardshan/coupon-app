import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../auth/domain/providers/auth_provider.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(currentUserProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: userAsync.when(
        data: (user) => _ProfileBody(
          name: user?.fullName ?? 'User',
          email: user?.email ?? '',
          avatarUrl: user?.avatarUrl,
          showMerchantDashboard: user?.role == 'merchant',
          onSignOut: () => ref.read(authNotifierProvider.notifier).signOut(),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }
}

class _ProfileBody extends StatelessWidget {
  final String name;
  final String email;
  final String? avatarUrl;
  final bool showMerchantDashboard;
  final VoidCallback onSignOut;

  const _ProfileBody({
    required this.name,
    required this.email,
    this.avatarUrl,
    this.showMerchantDashboard = false,
    required this.onSignOut,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          // ── Header ──────────────────────────────────────────
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              children: [
                // Avatar + name row
                Row(
                  children: [
                    GestureDetector(
                      onTap: () => context.push('/profile/edit'),
                      child: Stack(
                        children: [
                          CircleAvatar(
                            radius: 32,
                            backgroundColor: AppColors.primary.withValues(
                              alpha: 0.1,
                            ),
                            backgroundImage: avatarUrl != null
                                ? CachedNetworkImageProvider(avatarUrl!)
                                : null,
                            child: avatarUrl == null
                                ? Text(
                                    name[0].toUpperCase(),
                                    style: const TextStyle(
                                      fontSize: 24,
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  )
                                : null,
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white,
                                  width: 2,
                                ),
                              ),
                              child: const Icon(
                                Icons.edit,
                                color: Colors.white,
                                size: 10,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => context.push('/profile/edit'),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            Row(
                              children: [
                                const Text(
                                  'My Home Page',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                                const Icon(
                                  Icons.chevron_right,
                                  size: 14,
                                  color: AppColors.textHint,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // ── Quick links ──────────────────────────────────────
          _SectionCard(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _IconGridItem(
                  icon: Icons.star_border_outlined,
                  label: 'Collection',
                  onTap: () => context.push('/collection'),
                ),
                _IconGridItem(
                  icon: Icons.history,
                  label: 'History',
                  onTap: () => context.push('/history'),
                ),
                _IconGridItem(
                  icon: Icons.confirmation_number_outlined,
                  label: 'Coupons',
                  onTap: () => context.push('/coupons'),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // ── Orders section ───────────────────────────────────
          _SectionCard(
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Orders',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    GestureDetector(
                      onTap: () => context.push('/orders'),
                      child: const Row(
                        children: [
                          Text(
                            'View All',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textHint,
                            ),
                          ),
                          Icon(
                            Icons.chevron_right,
                            size: 14,
                            color: AppColors.textHint,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _IconGridItem(
                      icon: Icons.receipt_long_outlined,
                      label: 'All Orders',
                      onTap: () => context.push('/orders'),
                    ),
                    _IconGridItem(
                      icon: Icons.schedule_outlined,
                      label: 'To Use',
                      onTap: () => context.push('/coupons'),
                    ),
                    _IconGridItem(
                      icon: Icons.chat_bubble_outline,
                      label: 'To Review',
                      onTap: () => context.push('/to-review'),
                    ),
                    _IconGridItem(
                      icon: Icons.assignment_return_outlined,
                      label: 'Refunds',
                      onTap: () => context.push('/coupons'),
                    ),
                  ],
                ),
              ],
            ),
          ),


          const SizedBox(height: 12),

          // ── Payment Methods 入口 ──────────────────────────────
          _SectionCard(
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.credit_card_outlined,
                  color: AppColors.textSecondary,
                  size: 20,
                ),
              ),
              title: const Text(
                'Payment Methods',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              subtitle: const Text(
                'Manage saved cards',
                style: TextStyle(fontSize: 12, color: AppColors.textHint),
              ),
              trailing: const Icon(
                Icons.chevron_right,
                color: AppColors.textHint,
              ),
              onTap: () => context.push('/profile/payment-methods'),
            ),
          ),

          const SizedBox(height: 12),

          // ── Email Notifications 入口 ──────────────────────────
          _SectionCard(
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.mail_outline,
                  color: AppColors.textSecondary,
                  size: 20,
                ),
              ),
              title: const Text(
                'Email Notifications',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              subtitle: const Text(
                'Manage email preferences',
                style: TextStyle(fontSize: 12, color: AppColors.textHint),
              ),
              trailing: const Icon(
                Icons.chevron_right,
                color: AppColors.textHint,
              ),
              onTap: () => context.push('/profile/email-notifications'),
            ),
          ),

          if (showMerchantDashboard) ...[
            const SizedBox(height: 12),
            // ── Merchant dashboard link（仅 merchant 角色可见）──
            _SectionCard(
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.store_outlined,
                    color: AppColors.textSecondary,
                    size: 20,
                  ),
                ),
                title: const Text(
                  'Merchant Dashboard',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
                trailing: const Icon(
                  Icons.chevron_right,
                  color: AppColors.textHint,
                ),
                onTap: () => context.push('/merchant/dashboard'),
              ),
            ),
          ] else ...[
            const SizedBox(height: 12),
            // ── Become a merchant：联系方式（方案 A，仅非 merchant 可见）──
            _BecomeMerchantCard(),
          ],

          const SizedBox(height: 12),

          // ── Sign Out ─────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: OutlinedButton.icon(
              onPressed: onSignOut,
              icon: const Icon(Icons.logout, size: 16),
              label: const Text('Log Out'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textSecondary,
                side: const BorderSide(color: AppColors.surfaceVariant),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                minimumSize: const Size(double.infinity, 0),
              ),
            ),
          ),

          const SizedBox(height: 16),
          const Center(
            child: Text(
              'DealJoy Version 2.4.1',
              style: TextStyle(fontSize: 10, color: AppColors.textHint),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ── Become a merchant：展示联系方式（方案 A）────────────────────────────────────
class _BecomeMerchantCard extends StatelessWidget {
  const _BecomeMerchantCard();

  Future<void> _launchPhone(BuildContext context) async {
    final uri = Uri(scheme: 'tel', path: AppConstants.merchantPartnerPhone);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _launchEmail(BuildContext context) async {
    final uri = Uri(
      scheme: 'mailto',
      path: AppConstants.merchantPartnerEmail,
      query: 'subject=Become a DealJoy Merchant',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.store_outlined,
                  color: AppColors.textSecondary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Become a merchant',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Want to partner with us? Contact us:',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          InkWell(
            onTap: () => _launchPhone(context),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(Icons.phone_outlined, size: 16, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Text(
                    AppConstants.merchantPartnerPhone,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ],
              ),
            ),
          ),
          InkWell(
            onTap: () => _launchEmail(context),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(Icons.email_outlined, size: 16, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      AppConstants.merchantPartnerEmail,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        decoration: TextDecoration.underline,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Shared card wrapper ──────────────────────────────────────────────────────
class _SectionCard extends StatelessWidget {
  final Widget child;
  const _SectionCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
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
      child: child,
    );
  }
}

// ── Plain icon + label (for quick links & orders) ────────────────────────────
class _IconGridItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _IconGridItem({
    required this.icon,
    required this.label,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Icon(icon, color: AppColors.textSecondary, size: 24),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}


import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../auth/domain/providers/auth_provider.dart';
import '../../../../shared/widgets/legal_document_screen.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(currentUserProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: userAsync.when(
        data: (user) {
          // 未登录 → 显示登录/注册入口
          if (user == null) {
            return _GuestProfileBody(
              onLogin: () => context.push('/auth/login'),
            );
          }
          return _ProfileBody(
            name: user.fullName ?? 'User',
            username: user.username,
            email: user.email,
            avatarUrl: user.avatarUrl,
            phone: user.phone,
            isMerchant: user.role == 'merchant',
            onSignOut: () => ref.read(authNotifierProvider.notifier).signOut(),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }
}

class _ProfileBody extends StatelessWidget {
  final String name;
  final String? username;
  final String email;
  final String? avatarUrl;
  final String? phone;
  /// 已注册为商家：不再展示「成为商家」卡片（产品已移除客户端 Merchant Dashboard 入口）
  final bool isMerchant;
  final VoidCallback onSignOut;

  const _ProfileBody({
    required this.name,
    this.username,
    required this.email,
    this.avatarUrl,
    this.phone,
    this.isMerchant = false,
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
                            if (username != null && username!.isNotEmpty)
                              Text(
                                '@$username',
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppColors.textSecondary,
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
                  icon: Icons.account_balance_wallet_outlined,
                  label: 'Credit',
                  onTap: () => context.push('/profile/store-credit'),
                ),
                _IconGridItem(
                  icon: Icons.card_giftcard_outlined,
                  label: 'Gift',
                  onTap: () => context.push('/coupons?tab=gifted'),
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
                      onTap: () => context.push('/coupons?tab=unused'),
                    ),
                    _IconGridItem(
                      icon: Icons.rate_review_outlined,
                      label: 'Reviews',
                      onTap: () =>
                          context.push('/coupons?tab=reviews&sub=pending'),
                    ),
                    _IconGridItem(
                      icon: Icons.support_agent_outlined,
                      label: 'After-Sales',
                      onTap: () => context.push('/my-after-sales'),
                    ),
                  ],
                ),
              ],
            ),
          ),


          const SizedBox(height: 12),

          // ── Account Settings ──────────────────────────────────
          _SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Account Settings',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                _SettingsTile(
                  icon: Icons.phone_outlined,
                  title: 'Phone Number',
                  subtitle: phone != null && phone!.isNotEmpty && phone != 'skipped'
                      ? phone!
                      : 'Not set',
                  onTap: () => context.push('/profile/change-phone'),
                ),
                const Divider(height: 1),
                // 产品策略：不在客户端提供自助改邮箱，避免与 Auth/对账/通知错发等问题
                _SettingsTile(
                  icon: Icons.email_outlined,
                  title: 'Email',
                  subtitle: email,
                  showChevron: false,
                ),
                const Divider(height: 1),
                _SettingsTile(
                  icon: Icons.lock_outline,
                  title: 'Change Password',
                  onTap: () => context.push('/profile/change-password'),
                ),
                const Divider(height: 1),
                _SettingsTile(
                  icon: Icons.credit_card_outlined,
                  title: 'Payment Methods',
                  subtitle: 'Manage saved cards',
                  onTap: () => context.push('/profile/payment-methods'),
                ),
              ],
            ),
          ),

          if (!isMerchant) ...[
            const SizedBox(height: 12),
            // ── Become a merchant：联系方式（方案 A，仅非商家账号可见）──
            _BecomeMerchantCard(),
          ],

          const SizedBox(height: 12),

          // ── Customer Support ─────────────────────────────────
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
                  Icons.support_agent_outlined,
                  color: AppColors.textSecondary,
                  size: 20,
                ),
              ),
              title: const Text(
                'Customer Support',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              subtitle: const Text(
                'Email, call back, or chat with us',
                style: TextStyle(fontSize: 12, color: AppColors.textHint),
              ),
              trailing: const Icon(
                Icons.chevron_right,
                color: AppColors.textHint,
              ),
              onTap: () => context.push('/support'),
            ),
          ),

          const SizedBox(height: 12),

          // ── Legal ─────────────────────────────────────────────
          _SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Legal',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                // 服务条款
                _SettingsTile(
                  icon: Icons.description_outlined,
                  title: 'Terms of Service',
                  onTap: () {
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const LegalDocumentScreen(
                        slug: 'terms-of-service',
                        title: 'Terms of Service',
                      ),
                    ));
                  },
                ),
                const Divider(height: 1),
                // 隐私政策
                _SettingsTile(
                  icon: Icons.privacy_tip_outlined,
                  title: 'Privacy Policy',
                  onTap: () {
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const LegalDocumentScreen(
                        slug: 'privacy-policy',
                        title: 'Privacy Policy',
                      ),
                    ));
                  },
                ),
                const Divider(height: 1),
                // 退款政策
                _SettingsTile(
                  icon: Icons.shield_outlined,
                  title: 'Refund Policy',
                  onTap: () {
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const LegalDocumentScreen(
                        slug: 'refund-policy',
                        title: 'Refund Policy',
                      ),
                    ));
                  },
                ),
              ],
            ),
          ),

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
              'Crunchy Plum Version 2.4.1',
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
      query: 'subject=Become a Crunchy Plum Merchant',
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

// ── Account Settings 列表项 ───────────────────────────────────────────────────
class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final bool showChevron;

  const _SettingsTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.showChevron = true,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: AppColors.textSecondary, size: 20),
      ),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle!,
              style: const TextStyle(fontSize: 12, color: AppColors.textHint),
              overflow: TextOverflow.ellipsis,
            )
          : null,
      trailing: showChevron
          ? const Icon(
              Icons.chevron_right,
              color: AppColors.textHint,
              size: 18,
            )
          : null,
      onTap: onTap,
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

// 未登录时的 Profile 页面 — 显示登录/注册入口
class _GuestProfileBody extends StatelessWidget {
  final VoidCallback onLogin;

  const _GuestProfileBody({required this.onLogin});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: const BoxDecoration(
                  color: AppColors.surfaceVariant,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.person_outline,
                  size: 40,
                  color: AppColors.textHint,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Welcome to Crunchy Plum',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Sign in to manage orders, save deals,\nand access your coupons.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton(
                  onPressed: onLogin,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: const StadiumBorder(),
                  ),
                  child: const Text(
                    'Sign In / Register',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


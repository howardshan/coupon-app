import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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
  final VoidCallback onSignOut;

  const _ProfileBody({
    required this.name,
    required this.email,
    this.avatarUrl,
    required this.onSignOut,
  });

  static const _quickLinks = [
    (Icons.star_border_outlined, 'Collection'),
    (Icons.history, 'History'),
    (Icons.confirmation_number_outlined, 'Coupons'),
    (Icons.toll_outlined, 'Joy Coins'),
  ];

  static const _orderLinks = [
    (Icons.receipt_long_outlined, 'All Orders'),
    (Icons.schedule_outlined, 'To Use'),
    (Icons.chat_bubble_outline, 'To Review'),
    (Icons.assignment_return_outlined, 'Refunds'),
  ];

  static const _utilities = [
    (Icons.phone_android_outlined, 'Recharge'),
    (Icons.receipt_outlined, 'Invoice'),
    (Icons.rate_review_outlined, 'Review Team'),
    (Icons.volunteer_activism_outlined, 'Charity'),
  ];

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
                    Stack(
                      children: [
                        CircleAvatar(
                          radius: 32,
                          backgroundColor: AppColors.primary.withValues(alpha: 0.1),
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
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                            child: const Icon(Icons.edit,
                                color: Colors.white, size: 10),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 16),
                    Expanded(
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
                              Text(
                                'My Home Page',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              const Icon(Icons.chevron_right,
                                  size: 14, color: AppColors.textHint),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // ── Gold Member card ────────────────────────────
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFEF3C7), Color(0xFFFDE68A)],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.card_membership,
                                    color: Color(0xFF92400E), size: 18),
                                const SizedBox(width: 6),
                                const Text(
                                  'GOLD MEMBER',
                                  style: TextStyle(
                                    color: Color(0xFF78350F),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Row(
                                  children: List.generate(
                                    5,
                                    (i) => Icon(
                                      i == 0 ? Icons.star : Icons.star_border,
                                      size: 10,
                                      color: const Color(0xFFD97706),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'GROWTH VALUE 0 / 500',
                              style: TextStyle(
                                fontSize: 10,
                                color: Color(0xFF92400E),
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        height: 36,
                        width: 1,
                        color: const Color(0xFF92400E).withValues(alpha: 0.2),
                        margin: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                      GestureDetector(
                        child: const Row(
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Member Center',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF78350F),
                                  ),
                                ),
                                Text(
                                  '7 Benefits',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Color(0xFF92400E),
                                  ),
                                ),
                              ],
                            ),
                            Icon(Icons.chevron_right,
                                size: 16, color: Color(0xFF78350F)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // ── Quick links ──────────────────────────────────────
          _SectionCard(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: _quickLinks
                  .map((item) => _IconGridItem(
                        icon: item.$1,
                        label: item.$2,
                      ))
                  .toList(),
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
                          color: AppColors.textPrimary),
                    ),
                    GestureDetector(
                      onTap: () {},
                      child: Row(
                        children: [
                          const Text(
                            'View All',
                            style: TextStyle(
                                fontSize: 11,
                                color: AppColors.textHint),
                          ),
                          const Icon(Icons.chevron_right,
                              size: 14, color: AppColors.textHint),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: _orderLinks
                      .map((item) => _IconGridItem(
                            icon: item.$1,
                            label: item.$2,
                          ))
                      .toList(),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // ── Utilities ────────────────────────────────────────
          _SectionCard(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: _utilities
                  .map((item) => _BoxedIconItem(
                        icon: item.$1,
                        label: item.$2,
                      ))
                  .toList(),
            ),
          ),

          const SizedBox(height: 12),

          // ── Merchant dashboard link ──────────────────────────
          _SectionCard(
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.store_outlined,
                    color: AppColors.textSecondary, size: 20),
              ),
              title: const Text('Merchant Dashboard',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              trailing: const Icon(Icons.chevron_right, color: AppColors.textHint),
              onTap: () => context.push('/merchant/dashboard'),
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
                    borderRadius: BorderRadius.circular(14)),
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

  const _IconGridItem({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
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

// ── Boxed icon + label (for utilities) ──────────────────────────────────────
class _BoxedIconItem extends StatelessWidget {
  final IconData icon;
  final String label;

  const _BoxedIconItem({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      child: Column(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.surfaceVariant),
            ),
            child: Icon(icon, color: AppColors.textSecondary, size: 20),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

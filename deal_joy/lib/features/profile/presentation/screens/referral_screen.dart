import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/models/referral_model.dart';
import '../../domain/providers/referral_provider.dart';
import '../../../../shared/services/referral_link_service.dart';

// 黄色系配色常量
const _yellow = Color(0xFFFFD700);
const _amber = Color(0xFFFFB300);
const _yellowLight = Color(0xFFFFF8DC);
const _yellowMid = Color(0xFFFFF3B0);

class ReferralScreen extends ConsumerWidget {
  const ReferralScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configAsync = ref.watch(referralConfigProvider);
    final infoAsync = ref.watch(myReferralInfoProvider);
    final referralsAsync = ref.watch(myReferralsProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F7F4),
      body: RefreshIndicator(
        color: _amber,
        onRefresh: () async {
          ref.invalidate(referralConfigProvider);
          ref.invalidate(myReferralInfoProvider);
          ref.invalidate(myReferralsProvider);
        },
        child: CustomScrollView(
          slivers: [
            // ── App Bar ──────────────────────────────────────────────
            SliverAppBar(
              pinned: true,
              backgroundColor: Colors.white,
              foregroundColor: AppColors.textPrimary,
              elevation: 0,
              title: const Text(
                'Invite Friends',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
              ),
            ),

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                child: Column(
                  children: [
                    // ── Hero 卡片 ────────────────────────────────────
                    configAsync.when(
                      data: (config) => _HeroCard(config: config),
                      loading: () => const _Skeleton(height: 200),
                      error: (_, __) => const _HeroCard(config: ReferralConfig.disabled),
                    ),

                    const SizedBox(height: 16),

                    // ── 分享区域 ─────────────────────────────────────
                    infoAsync.when(
                      data: (info) => _ShareCard(
                        referralCode: info.code,
                        hasReferrer: info.hasReferrer,
                      ),
                      loading: () => const _Skeleton(height: 120),
                      error: (_, __) => const SizedBox.shrink(),
                    ),

                    const SizedBox(height: 16),

                    // ── How It Works ─────────────────────────────────
                    configAsync.when(
                      data: (config) => _HowItWorksCard(bonusAmount: config.bonusAmount),
                      loading: () => const SizedBox.shrink(),
                      error: (_, __) => const _HowItWorksCard(bonusAmount: 5.0),
                    ),

                    const SizedBox(height: 16),

                    // ── 我的推荐记录 ─────────────────────────────────
                    referralsAsync.when(
                      data: (records) => _ReferralsCard(records: records),
                      loading: () => const _Skeleton(height: 160),
                      error: (_, __) => const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Hero 卡片 ────────────────────────────────────────────────────────────────

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.config});
  final ReferralConfig config;

  @override
  Widget build(BuildContext context) {
    if (!config.enabled) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F3F5),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Column(
          children: [
            Text('🍑', style: TextStyle(fontSize: 40)),
            SizedBox(height: 12),
            Text(
              'Referral Program',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 17,
                color: AppColors.textSecondary,
              ),
            ),
            SizedBox(height: 4),
            Text(
              'Coming soon — stay tuned!',
              style: TextStyle(fontSize: 13, color: AppColors.textHint),
            ),
          ],
        ),
      );
    }

    final amtStr = '\$${config.bonusAmount.toStringAsFixed(config.bonusAmount.truncateToDouble() == config.bonusAmount ? 0 : 2)}';

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFD000), Color(0xFFFFB300)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: _amber.withValues(alpha: 0.35),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'Referral Program',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Invite friends,\nearn $amtStr each',
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: Colors.black87,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Share your link. You both get\n$amtStr after their first redeem.',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.black.withValues(alpha: 0.6),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          const Text('🍑', style: TextStyle(fontSize: 64)),
        ],
      ),
    );
  }
}

// ── 分享卡片 ─────────────────────────────────────────────────────────────────

class _ShareCard extends StatelessWidget {
  const _ShareCard({required this.referralCode, required this.hasReferrer});
  final String referralCode;
  final bool hasReferrer;

  @override
  Widget build(BuildContext context) {
    if (referralCode.isEmpty) return const SizedBox.shrink();

    final shareUrl = ReferralLinkService.instance.buildShareUrl(referralCode);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasReferrer) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle_rounded, size: 14, color: AppColors.success),
                  SizedBox(width: 6),
                  Text(
                    'You joined via a friend\'s invite ✓',
                    style: TextStyle(fontSize: 12, color: AppColors.success, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          const Text(
            'Your invite link',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 10),

          // 链接展示框
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: _yellowLight,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _yellow.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                const Icon(Icons.link_rounded, size: 16, color: _amber),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    shareUrl,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                      fontFamily: 'monospace',
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          Row(
            children: [
              // Share 主按钮
              Expanded(
                flex: 3,
                child: GestureDetector(
                  onTap: () {
                    Share.share(
                      'Join me on CrunchyPlum! Download the app and use my invite link to get started:\n$shareUrl',
                      subject: 'Join CrunchyPlum with my invite link!',
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFFD000), Color(0xFFFFB300)],
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: _amber.withValues(alpha: 0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.ios_share_rounded, size: 17, color: Colors.black87),
                        SizedBox(width: 6),
                        Text(
                          'Share Link',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // Copy 次按钮
              Expanded(
                flex: 2,
                child: GestureDetector(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: shareUrl));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text('Link copied!'),
                        duration: const Duration(seconds: 2),
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        backgroundColor: AppColors.textPrimary,
                      ),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F3F5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.copy_rounded, size: 16, color: AppColors.textSecondary),
                        SizedBox(width: 6),
                        Text(
                          'Copy',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── How It Works 卡片 ─────────────────────────────────────────────────────────

class _HowItWorksCard extends StatefulWidget {
  const _HowItWorksCard({required this.bonusAmount});
  final double bonusAmount;

  @override
  State<_HowItWorksCard> createState() => _HowItWorksCardState();
}

class _HowItWorksCardState extends State<_HowItWorksCard> {
  bool _tcExpanded = false;

  @override
  Widget build(BuildContext context) {
    final amt = '\$${widget.bonusAmount.toStringAsFixed(widget.bonusAmount.truncateToDouble() == widget.bonusAmount ? 0 : 2)}';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'How It Works',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 20),

          _StepRow(
            number: 1,
            icon: Icons.ios_share_rounded,
            title: 'Share your link',
            subtitle: 'Send your invite link to friends.',
          ),
          _StepConnector(),
          _StepRow(
            number: 2,
            icon: Icons.person_add_rounded,
            title: 'Friend signs up',
            subtitle: 'They download CrunchyPlum and create an account via your link.',
          ),
          _StepConnector(),
          _StepRow(
            number: 3,
            icon: Icons.qr_code_scanner_rounded,
            title: 'Both earn $amt',
            subtitle: 'After their first voucher redeem, you both get $amt store credit!',
          ),

          const SizedBox(height: 20),
          const Divider(height: 1, color: Color(0xFFF1F3F5)),
          const SizedBox(height: 12),

          // T&C 折叠
          GestureDetector(
            onTap: () => setState(() => _tcExpanded = !_tcExpanded),
            child: Row(
              children: [
                const Text(
                  'Terms & Conditions',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textHint,
                  ),
                ),
                const Spacer(),
                Icon(
                  _tcExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                  size: 18,
                  color: AppColors.textHint,
                ),
              ],
            ),
          ),

          if (_tcExpanded) ...[
            const SizedBox(height: 10),
            const Text(
              '• Store credit has no cash value and cannot be transferred or exchanged for cash.\n'
              '• Your friend must sign up using your invite link before creating an account.\n'
              '• Referral code must be applied before the referred user\'s first voucher redemption.\n'
              '• Each person may only be referred once. Duplicate referrals will not be credited.\n'
              '• Self-referral is not permitted.\n'
              '• CrunchyPlum reserves the right to modify, suspend, or terminate this program at any time without prior notice.\n'
              '• Credits obtained through fraudulent activity may be revoked without notice.\n'
              '• This offer is void where prohibited by applicable law.\n'
              '• Store credit may constitute taxable income. You are solely responsible for any applicable tax obligations. Consult a tax advisor if you have questions.\n'
              '• By participating, you agree to CrunchyPlum\'s Terms of Service and Privacy Policy.',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textHint,
                height: 1.7,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.number,
    required this.icon,
    required this.title,
    required this.subtitle,
  });
  final int number;
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 序号圆圈
        Container(
          width: 36,
          height: 36,
          decoration: const BoxDecoration(
            color: _yellowLight,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              '$number',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: _amber,
              ),
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 15, color: _amber),
                  const SizedBox(width: 5),
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StepConnector extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 17, top: 4, bottom: 4),
      child: Container(
        width: 2,
        height: 18,
        decoration: BoxDecoration(
          color: _yellow.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(1),
        ),
      ),
    );
  }
}

// ── 推荐记录卡片 ──────────────────────────────────────────────────────────────

class _ReferralsCard extends StatelessWidget {
  const _ReferralsCard({required this.records});
  final List<ReferralRecord> records;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'My Referrals',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              if (records.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: _yellowLight,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${records.length} friend${records.length == 1 ? '' : 's'}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _amber,
                    ),
                  ),
                ),
            ],
          ),

          if (records.isEmpty) ...[
            const SizedBox(height: 28),
            Center(
              child: Column(
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: _yellowLight,
                      shape: BoxShape.circle,
                    ),
                    child: const Center(
                      child: Text('🍑', style: TextStyle(fontSize: 28)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'No referrals yet',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Share your invite link to start earning!',
                    style: TextStyle(fontSize: 12, color: AppColors.textHint),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ] else ...[
            const SizedBox(height: 16),
            ...records.map((r) => _ReferralTile(record: r)),
          ],
        ],
      ),
    );
  }
}

class _ReferralTile extends StatelessWidget {
  const _ReferralTile({required this.record});
  final ReferralRecord record;

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('MMM d');
    final name = record.refereeFirstName ?? 'Friend';
    final amtStr = '\$${record.bonusAmount.toStringAsFixed(2)}';

    final (chipBg, chipText, chipLabel) = record.isCredited
        ? (AppColors.success.withValues(alpha: 0.1), AppColors.success, 'Earned $amtStr')
        : record.status == 'cancelled'
            ? (const Color(0xFFF1F3F5), AppColors.textHint, 'Cancelled')
            : (_yellowLight, _amber, 'Awaiting first redeem');

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          // 头像
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: _yellowMid,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                name[0].toUpperCase(),
                style: const TextStyle(
                  color: _amber,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  record.isCredited
                      ? 'Joined ${fmt.format(record.createdAt)} · Credited ${fmt.format(record.creditedAt!)}'
                      : 'Joined ${fmt.format(record.createdAt)}',
                  style: const TextStyle(fontSize: 11, color: AppColors.textHint),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: chipBg,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              chipLabel,
              style: TextStyle(
                fontSize: 11,
                color: chipText,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Profile 页横幅（被 profile_screen.dart 引用） ─────────────────────────────

class ReferralBanner extends StatelessWidget {
  const ReferralBanner({super.key, required this.bonusAmount, required this.onTap});
  final double bonusAmount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final amt = '\$${bonusAmount.toStringAsFixed(bonusAmount.truncateToDouble() == bonusAmount ? 0 : 2)}';
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFFFD000), Color(0xFFFFB300)],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: _amber.withValues(alpha: 0.25),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            const Text('🍑', style: TextStyle(fontSize: 22)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Invite friends, earn $amt each →',
                style: const TextStyle(
                  color: Colors.black87,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 骨架屏 ────────────────────────────────────────────────────────────────────

class _Skeleton extends StatelessWidget {
  const _Skeleton({required this.height});
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFFF1F3F5),
        borderRadius: BorderRadius.circular(20),
      ),
    );
  }
}

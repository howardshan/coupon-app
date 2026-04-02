// Promotions 主页面
// 顶部：余额卡片 + Recharge 按钮
// 中部：Campaign 列表（支持右滑操作）
// 底部 FAB：新建 Campaign
// 空状态：引导用户创建第一个 Campaign

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/promotions_provider.dart';
import '../widgets/balance_card.dart';
import '../widgets/campaign_card.dart';

// =============================================================
// PromotionsPage — Promotions 主页（ConsumerWidget）
// =============================================================
class PromotionsPage extends ConsumerWidget {
  const PromotionsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountAsync   = ref.watch(adAccountProvider);
    final campaignsAsync = ref.watch(campaignsProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: _buildAppBar(context),
      // 下拉刷新同时刷新账户和 Campaign
      body: RefreshIndicator(
        color: const Color(0xFFFF6B35),
        onRefresh: () async {
          await Future.wait([
            ref.read(adAccountProvider.notifier).refresh(),
            ref.read(campaignsProvider.notifier).refresh(),
          ]);
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ------------------------------------------------
              // 区块 1: 余额卡片
              // ------------------------------------------------
              accountAsync.when(
                loading: () => _BalanceCardSkeleton(),
                error: (err, _) => _ErrorCard(
                  message: 'Failed to load balance',
                  onRetry: () =>
                      ref.read(adAccountProvider.notifier).refresh(),
                ),
                data: (account) => BalanceCard(
                  account: account,
                  onRecharge: () => context.push('/promotions/recharge'),
                ),
              ),
              const SizedBox(height: 24),

              // ------------------------------------------------
              // 区块 2: Campaign 列表标题
              // ------------------------------------------------
              _SectionHeader(
                title: 'My Campaigns',
                subtitle: campaignsAsync.maybeWhen(
                  data: (list) => '${list.length} campaign(s)',
                  orElse: () => null,
                ),
              ),
              const SizedBox(height: 12),

              // ------------------------------------------------
              // 区块 3: Campaign 列表
              // ------------------------------------------------
              campaignsAsync.when(
                loading: () => _CampaignsListSkeleton(),
                error: (err, _) => _ErrorCard(
                  message: 'Failed to load campaigns',
                  onRetry: () =>
                      ref.read(campaignsProvider.notifier).refresh(),
                ),
                data: (campaigns) => campaigns.isEmpty
                    ? _EmptyState(
                        onCreateTap: () =>
                            context.push('/promotions/create'),
                      )
                    : _CampaignsList(
                        campaigns: campaigns,
                        ref: ref,
                        context: context,
                      ),
              ),

              // 底部留空，避免 FAB 遮挡最后一项
              const SizedBox(height: 80),
            ],
          ),
        ),
      ),

      // --------------------------------------------------------
      // FAB：新建 Campaign
      // --------------------------------------------------------
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/promotions/create'),
        backgroundColor: const Color(0xFFFF6B35),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text(
          'New Campaign',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  // ----------------------------------------------------------
  // AppBar
  // ----------------------------------------------------------
  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new, size: 18),
        color: const Color(0xFF1A1A2E),
        onPressed: () => Navigator.of(context).pop(),
      ),
      title: const Text(
        'Promotions',
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: Color(0xFF1A1A2E),
        ),
      ),
      actions: [
        // 刷新按钮（辅助操作）
        IconButton(
          icon: const Icon(Icons.refresh_outlined, size: 20),
          color: const Color(0xFF1A1A2E),
          onPressed: () {},
          tooltip: 'Refresh',
        ),
        const SizedBox(width: 4),
      ],
    );
  }
}

// =============================================================
// _CampaignsList — Campaign 列表区域（私有组件）
// =============================================================
class _CampaignsList extends StatelessWidget {
  final List campaigns;
  final WidgetRef ref;
  final BuildContext context;

  const _CampaignsList({
    required this.campaigns,
    required this.ref,
    required this.context,
  });

  @override
  Widget build(BuildContext ctx) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: campaigns.length,
      itemBuilder: (_, index) {
        final campaign = campaigns[index];
        return CampaignCard(
          campaign: campaign,
          onTap: () => context.push('/promotions/${campaign.id}'),
          onPause: campaign.status == 'active' && !campaign.adminPaused
              ? () => ref
                  .read(campaignsProvider.notifier)
                  .pauseCampaign(campaign.id)
              : null,
          onResume: campaign.status == 'paused' && !campaign.adminPaused
              ? () => ref
                  .read(campaignsProvider.notifier)
                  .resumeCampaign(campaign.id)
              : null,
          onDelete: () =>
              ref.read(campaignsProvider.notifier).deleteCampaign(campaign.id),
        );
      },
    );
  }
}

// =============================================================
// _SectionHeader — 区块标题（私有组件）
// =============================================================
class _SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;

  const _SectionHeader({required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1A1A2E),
          ),
        ),
        if (subtitle != null)
          Text(
            subtitle!,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade500,
            ),
          ),
      ],
    );
  }
}

// =============================================================
// _EmptyState — 无 Campaign 时的引导状态（私有组件）
// =============================================================
class _EmptyState extends StatelessWidget {
  final VoidCallback onCreateTap;

  const _EmptyState({required this.onCreateTap});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: const Color(0xFFFF6B35).withAlpha(26),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.campaign_outlined,
                size: 40,
                color: Color(0xFFFF6B35),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'No campaigns yet',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1A1A2E),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Create your first campaign to start\n'
              'promoting your deals to more customers.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade500,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: onCreateTap,
              icon: const Icon(Icons.add, size: 18),
              label: const Text(
                'Create Campaign',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6B35),
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                elevation: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================
// _ErrorCard — 错误提示卡片（私有组件）
// =============================================================
class _ErrorCard extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorCard({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFFFEBEE),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFCDD2)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFE53935), size: 32),
          const SizedBox(height: 8),
          Text(
            message,
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFFB71C1C),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: onRetry,
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFE53935),
              side: const BorderSide(color: Color(0xFFE53935)),
            ),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

// =============================================================
// _BalanceCardSkeleton — 余额卡片骨架屏（私有组件）
// =============================================================
class _BalanceCardSkeleton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 200,
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(16),
      ),
    );
  }
}

// =============================================================
// _CampaignsListSkeleton — Campaign 列表骨架屏（私有组件）
// =============================================================
class _CampaignsListSkeleton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(
        3,
        (i) => Container(
          margin: const EdgeInsets.only(bottom: 12),
          height: 130,
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}

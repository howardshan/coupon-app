// Promotions 主页面（重构版）
// 顶部：余额卡片 + Recharge 按钮
// 中部："New Campaign" 水平滚动卡片区域
// 下方：Active Campaigns 列表 + Expired Campaigns 可折叠区
// 移除底部 FloatingActionButton

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/promotions_provider.dart';
import '../widgets/balance_card.dart';
import '../widgets/campaign_card.dart';
import '../models/promotions_models.dart';

// =============================================================
// PromotionsPage — Promotions 主页（ConsumerStatefulWidget）
// 使用 ConsumerStatefulWidget 以便 initState 中触发刷新
// =============================================================
class PromotionsPage extends ConsumerStatefulWidget {
  const PromotionsPage({super.key});

  @override
  ConsumerState<PromotionsPage> createState() => _PromotionsPageState();
}

class _PromotionsPageState extends ConsumerState<PromotionsPage> {
  @override
  void initState() {
    super.initState();
    // 进入页面时强制刷新广告位配置，确保 splash isEnabled 状态最新
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.invalidate(placementConfigsProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    final accountAsync   = ref.watch(adAccountProvider);
    final campaignsAsync = ref.watch(campaignsProvider);
    // 从派生 Provider 获取分类后的列表
    final activeCampaigns  = ref.watch(activeCampaignsProvider);
    final expiredCampaigns = ref.watch(expiredCampaignsProvider);
    // 广告位配置（用于判断 splash 是否可用）
    final placementConfigsAsync = ref.watch(placementConfigsProvider);

    // 查找 splash 广告位的 isEnabled 状态
    final splashEnabled = placementConfigsAsync.maybeWhen(
      data: (configs) {
        final splash = configs.where((c) => c.placement == 'splash').firstOrNull;
        return splash?.isEnabled ?? false;
      },
      orElse: () => false,
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: _buildAppBar(context, ref),
      // 下拉刷新同时刷新账户和 Campaign
      body: RefreshIndicator(
        color: const Color(0xFFFF6B35),
        onRefresh: () async {
          await Future.wait([
            ref.read(adAccountProvider.notifier).refresh(),
            ref.read(campaignsProvider.notifier).refresh(),
          ]);
          ref.invalidate(placementConfigsProvider);
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
              // 区块 2: New Campaign 水平滚动卡片
              // ------------------------------------------------
              const _SectionHeader(title: 'New Campaign'),
              const SizedBox(height: 12),
              _NewCampaignRow(splashEnabled: splashEnabled),
              const SizedBox(height: 24),

              // ------------------------------------------------
              // 区块 3: Active Campaigns 列表
              // ------------------------------------------------
              const _SectionHeader(title: 'Active Campaigns'),
              const SizedBox(height: 12),
              campaignsAsync.when(
                loading: () => _CampaignsListSkeleton(),
                error: (err, _) => _ErrorCard(
                  message: 'Failed to load campaigns',
                  onRetry: () =>
                      ref.read(campaignsProvider.notifier).refresh(),
                ),
                data: (_) => activeCampaigns.isEmpty
                    ? _EmptyActiveCampaigns()
                    : _CampaignsList(
                        campaigns: activeCampaigns,
                        ref: ref,
                        context: context,
                      ),
              ),
              const SizedBox(height: 16),

              // ------------------------------------------------
              // 区块 4: Expired Campaigns 可折叠区（只有数据时才显示）
              // ------------------------------------------------
              if (expiredCampaigns.isNotEmpty)
                _ExpiredCampaignsSection(
                  campaigns: expiredCampaigns,
                  ref: ref,
                  context: context,
                ),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  // ----------------------------------------------------------
  // AppBar（保留刷新按钮）
  // ----------------------------------------------------------
  PreferredSizeWidget _buildAppBar(BuildContext context, WidgetRef ref) {
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
        // 刷新按钮
        IconButton(
          icon: const Icon(Icons.refresh_outlined, size: 20),
          color: const Color(0xFF1A1A2E),
          tooltip: 'Refresh',
          onPressed: () async {
            await Future.wait([
              ref.read(adAccountProvider.notifier).refresh(),
              ref.read(campaignsProvider.notifier).refresh(),
            ]);
            ref.invalidate(placementConfigsProvider);
          },
        ),
        const SizedBox(width: 4),
      ],
    );
  }
}

// =============================================================
// _NewCampaignRow — New Campaign 水平滚动卡片行（私有组件）
// =============================================================
class _NewCampaignRow extends StatelessWidget {
  final bool splashEnabled;

  const _NewCampaignRow({required this.splashEnabled});

  @override
  Widget build(BuildContext context) {
    // 根据 splashEnabled 决定是否显示 Splash Screen 卡片
    final cards = <_NewCampaignCardData>[
      if (splashEnabled)
        const _NewCampaignCardData(
          icon: Icons.fullscreen,
          title: 'Splash Screen',
          description: 'Full-screen ad when app opens',
          campaignType: 'splash',
        ),
      const _NewCampaignCardData(
        icon: Icons.store,
        title: 'Store Booster',
        description: 'Promote your store in search & browse',
        campaignType: 'store_booster',
      ),
      const _NewCampaignCardData(
        icon: Icons.local_offer,
        title: 'Deal Booster',
        description: 'Feature your deals on home & category',
        campaignType: 'deal_booster',
      ),
    ];

    return SizedBox(
      height: 130,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: cards.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final card = cards[index];
          return _NewCampaignCard(data: card);
        },
      ),
    );
  }
}

// 新建 Campaign 卡片的数据结构
class _NewCampaignCardData {
  final IconData icon;
  final String title;
  final String description;
  final String campaignType;

  const _NewCampaignCardData({
    required this.icon,
    required this.title,
    required this.description,
    required this.campaignType,
  });
}

// 单个新建 Campaign 卡片
class _NewCampaignCard extends StatelessWidget {
  final _NewCampaignCardData data;

  const _NewCampaignCard({required this.data});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('/promotions/create', extra: data.campaignType),
      child: Container(
        width: 155,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(10),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 图标圆形背景
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: const Color(0xFFFF6B35).withAlpha(26),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                data.icon,
                size: 20,
                color: const Color(0xFFFF6B35),
              ),
            ),
            const SizedBox(height: 10),
            // 标题
            Text(
              data.title,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1A1A2E),
              ),
            ),
            const SizedBox(height: 4),
            // 描述（最多2行）
            Text(
              data.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade500,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================
// _CampaignsList — Campaign 列表区域（私有组件）
// =============================================================
class _CampaignsList extends StatelessWidget {
  final List<AdCampaign> campaigns;
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
          // adminPaused 状态下不允许商家自行暂停或恢复
          onPause: campaign.status == CampaignStatus.active
              ? () => ref
                  .read(campaignsProvider.notifier)
                  .pauseCampaign(campaign.id)
              : null,
          onResume: campaign.status == CampaignStatus.paused
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
// _ExpiredCampaignsSection — 可折叠的过期 Campaign 区域
// =============================================================
class _ExpiredCampaignsSection extends StatelessWidget {
  final List<AdCampaign> campaigns;
  final WidgetRef ref;
  final BuildContext context;

  const _ExpiredCampaignsSection({
    required this.campaigns,
    required this.ref,
    required this.context,
  });

  @override
  Widget build(BuildContext ctx) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(8),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Theme(
        // 去掉 ExpansionTile 默认分割线
        data: Theme.of(ctx).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          // 默认收起
          initiallyExpanded: false,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          leading: const Icon(
            Icons.history_outlined,
            color: Color(0xFF9E9E9E),
            size: 20,
          ),
          title: Text(
            'Expired Campaigns',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade600,
            ),
          ),
          subtitle: Text(
            '${campaigns.length} campaign(s)',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade400,
            ),
          ),
          children: campaigns.map((campaign) {
            return CampaignCard(
              campaign: campaign,
              onTap: () => context.push('/promotions/${campaign.id}'),
              // 过期的 campaign 不提供 pause/resume 操作
              onPause: null,
              onResume: null,
              onDelete: () =>
                  ref.read(campaignsProvider.notifier).deleteCampaign(campaign.id),
            );
          }).toList(),
        ),
      ),
    );
  }
}

// =============================================================
// _SectionHeader — 区块标题（私有组件）
// =============================================================
class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: Color(0xFF1A1A2E),
      ),
    );
  }
}

// =============================================================
// _EmptyActiveCampaigns — Active 区域空状态（私有组件）
// =============================================================
class _EmptyActiveCampaigns extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        'No active campaigns',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 14,
          color: Colors.grey.shade400,
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

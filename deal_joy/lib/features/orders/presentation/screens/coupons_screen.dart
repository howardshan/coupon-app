// 我的团购券列表页 — 带四个状态 Tab 和下拉刷新

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../reviews/domain/providers/my_reviews_provider.dart';
import '../../../reviews/presentation/widgets/submitted_reviews_list.dart';
import '../../data/models/coupon_model.dart';
import '../../domain/providers/coupons_provider.dart';
import '../widgets/coupon_card.dart';
import '../widgets/pending_reviews_list.dart';

/// Tab 配置
const _tabs = [
  (label: 'Unused', status: 'unused'),
  (label: 'Used', status: 'used'),
  (label: 'Reviews', status: 'reviews'),
  (label: 'Expired', status: 'expired'),
  (label: 'Refunded', status: 'refunded'),
  (label: 'Gifted', status: 'gifted'),
];

class CouponsScreen extends ConsumerStatefulWidget {
  /// 顶层 Tab 初始索引（0=Unused … 2=Reviews）
  final int initialTabIndex;

  /// Reviews 内子 Tab：0=Pending，1=Submitted
  final int initialReviewsSubIndex;

  const CouponsScreen({
    super.key,
    this.initialTabIndex = 0,
    this.initialReviewsSubIndex = 0,
  });

  @override
  ConsumerState<CouponsScreen> createState() => _CouponsScreenState();
}

class _CouponsScreenState extends ConsumerState<CouponsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    final idx = widget.initialTabIndex.clamp(0, _tabs.length - 1);
    _tabController = TabController(
      length: _tabs.length,
      vsync: this,
      initialIndex: idx,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Coupons'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          indicatorColor: AppColors.primary,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textSecondary,
          tabs: _tabs.map((t) => Tab(text: t.label)).toList(),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: _tabs.map((t) {
          if (t.status == 'reviews') {
            return _ReviewsHubBody(
              key: ValueKey('reviews-hub-${widget.initialReviewsSubIndex}'),
              initialSubIndex: widget.initialReviewsSubIndex,
            );
          }
          return _CouponTabView(status: t.status);
        }).toList(),
      ),
    );
  }
}

/// Reviews 顶层 Tab：Pending（按 deal 去重）| Submitted（已发布）
class _ReviewsHubBody extends ConsumerStatefulWidget {
  final int initialSubIndex;

  const _ReviewsHubBody({super.key, required this.initialSubIndex});

  @override
  ConsumerState<_ReviewsHubBody> createState() => _ReviewsHubBodyState();
}

class _ReviewsHubBodyState extends ConsumerState<_ReviewsHubBody>
    with SingleTickerProviderStateMixin {
  late TabController _subController;

  @override
  void initState() {
    super.initState();
    final sub = widget.initialSubIndex.clamp(0, 1);
    _subController = TabController(length: 2, vsync: this, initialIndex: sub);
  }

  @override
  void dispose() {
    _subController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: Theme.of(context).colorScheme.surface,
          child: TabBar(
            controller: _subController,
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.textSecondary,
            indicatorColor: AppColors.primary,
            tabs: const [
              Tab(text: 'Pending'),
              Tab(text: 'Submitted'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _subController,
            physics: const NeverScrollableScrollPhysics(),
            children: const [
              PendingReviewsList(),
              SubmittedReviewsList(),
            ],
          ),
        ),
      ],
    );
  }
}

/// 单个 Tab 的内容视图 — 按状态过滤、显示列表或空状态
class _CouponTabView extends ConsumerWidget {
  final String status;

  const _CouponTabView({required this.status});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final couponsAsync = ref.watch(couponsByStatusProvider(status));

    return couponsAsync.when(
      data: (coupons) => _CouponList(coupons: coupons, status: status, ref: ref),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline,
                  size: 48, color: AppColors.textHint),
              const SizedBox(height: 12),
              Text(
                'Failed to load coupons',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                e.toString(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                key: const ValueKey('coupons_retry_btn'),
                onPressed: () => ref.invalidate(userCouponsProvider),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CouponList extends StatelessWidget {
  final List<CouponModel> coupons;
  final String status;
  final WidgetRef ref;

  const _CouponList({
    required this.coupons,
    required this.status,
    required this.ref,
  });

  @override
  Widget build(BuildContext context) {
    if (coupons.isEmpty) {
      return _EmptyState(status: status);
    }

    // Unused tab：按商家分组 → 同名券合并
    if (status == 'unused') {
      return _buildGroupedView(context);
    }

    // Used tab：结合「我的评价」列表展示已评/待写提示
    if (status == 'used') {
      final reviewsAsync = ref.watch(myWrittenReviewsProvider);
      return reviewsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 48, color: AppColors.textHint),
                const SizedBox(height: 12),
                Text(
                  'Failed to load review status',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  e.toString(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => ref.invalidate(myWrittenReviewsProvider),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
        data: (myReviews) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(userCouponsProvider);
            ref.invalidate(myWrittenReviewsProvider);
          },
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: coupons.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (_, i) {
              final c = coupons[i];
              final matched = matchWrittenReviewForCoupon(c, myReviews);
              return CouponCard(
                coupon: c,
                writtenReview: matched,
                showWriteReviewHint: matched == null,
                onTap: () => context.push('/coupon/${c.id}'),
              );
            },
          ),
        ),
      );
    }

    // 其他 tab 保持原来的平铺列表
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(userCouponsProvider),
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: coupons.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, i) => CouponCard(
          coupon: coupons[i],
          onTap: () => context.push('/coupon/${coupons[i].id}'),
        ),
      ),
    );
  }

  /// Unused tab：即将过期板块 + 两级归类（商家 → 券名合并）
  Widget _buildGroupedView(BuildContext context) {
    final now = DateTime.now();
    final sevenDaysLater = now.add(const Duration(days: 7));

    // 分离即将过期（7天内）和正常的券
    final expiringSoon = <CouponModel>[];
    final normal = <CouponModel>[];
    for (final c in coupons) {
      if (c.expiresAt != null && c.expiresAt!.isBefore(sevenDaysLater)) {
        expiringSoon.add(c);
      } else {
        normal.add(c);
      }
    }

    // 正常券按商家分组
    final merchantMap = <String, List<CouponModel>>{};
    for (final c in normal) {
      final merchant = c.merchantName ?? 'Merchant';
      merchantMap.putIfAbsent(merchant, () => []).add(c);
    }

    // 排序：最新购买的商家排前面；同时购买的按券多排前面
    final sortedMerchants = merchantMap.entries.toList()
      ..sort((a, b) {
        final aLatest = a.value.map((c) => c.createdAt).reduce(
            (v, e) => e.isAfter(v) ? e : v);
        final bLatest = b.value.map((c) => c.createdAt).reduce(
            (v, e) => e.isAfter(v) ? e : v);
        final timeCmp = bLatest.compareTo(aLatest);
        if (timeCmp != 0) return timeCmp;
        return b.value.length.compareTo(a.value.length);
      });

    // 构建列表项：即将过期板块 + 商家分组
    final widgets = <Widget>[];

    // 即将过期板块（如果有）
    if (expiringSoon.isNotEmpty) {
      widgets.add(_ExpiringSoonSection(coupons: expiringSoon));
    }

    // 正常商家分组
    for (final entry in sortedMerchants) {
      widgets.add(_MerchantCouponGroup(
        merchantName: entry.key,
        coupons: entry.value,
      ));
    }

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(userCouponsProvider),
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: widgets.length,
        separatorBuilder: (_, __) => const SizedBox(height: 16),
        itemBuilder: (_, i) => widgets[i],
      ),
    );
  }
}

/// 单个商家的券分组卡片
class _MerchantCouponGroup extends StatelessWidget {
  final String merchantName;
  final List<CouponModel> coupons;

  const _MerchantCouponGroup({
    required this.merchantName,
    required this.coupons,
  });

  @override
  Widget build(BuildContext context) {
    // 按券名（deal title）合并，统计数量
    final dealMap = <String, List<CouponModel>>{};
    for (final c in coupons) {
      final title = c.dealTitle ?? 'Coupon';
      dealMap.putIfAbsent(title, () => []).add(c);
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 商家抬头
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
            child: Row(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: const Icon(Icons.store, size: 13, color: AppColors.primary),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    merchantName,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '${coupons.length} voucher${coupons.length > 1 ? 's' : ''}',
                  style: const TextStyle(fontSize: 11, color: AppColors.textHint),
                ),
              ],
            ),
          ),
          const Divider(height: 16, indent: 14, endIndent: 14),

          // 按券名合并后的列表 — 点击跳转到 order deal detail 页
          ...dealMap.entries.map((entry) {
            final dealCoupons = entry.value;
            final first = dealCoupons.first;
            return _CouponRow(
              dealTitle: entry.key,
              imageUrl: first.dealImageUrl,
              quantity: dealCoupons.length,
              expiresAt: first.expiresAt,
              onTap: () => context.push('/voucher/${first.orderId}?dealId=${first.dealId}'),
            );
          }),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// 单行券（同名合并后）
class _CouponRow extends StatelessWidget {
  final String dealTitle;
  final String? imageUrl;
  final int quantity;
  final DateTime? expiresAt;
  final bool showUrgent;
  final VoidCallback onTap;

  const _CouponRow({
    required this.dealTitle,
    this.imageUrl,
    required this.quantity,
    this.expiresAt,
    this.showUrgent = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
        child: Row(
          children: [
            // 券图标
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: imageUrl != null
                  ? Image.network(
                      imageUrl!,
                      width: 48,
                      height: 48,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _placeholder(),
                    )
                  : _placeholder(),
            ),
            const SizedBox(width: 10),
            // 券名
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    dealTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Qty: $quantity',
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                  if (expiresAt != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Expires ${DateFormat('MMM d, yyyy').format(expiresAt!.toLocal())}',
                      style: TextStyle(
                        fontSize: 11,
                        color: showUrgent ? AppColors.error : AppColors.textHint,
                        fontWeight: showUrgent ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 18, color: AppColors.textHint),
          ],
        ),
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(Icons.confirmation_number_outlined, size: 20, color: AppColors.textHint),
    );
  }
}

/// 空状态组件
class _EmptyState extends StatelessWidget {
  final String status;

  const _EmptyState({required this.status});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _emptyIcon(status),
              size: 72,
              color: AppColors.textHint,
            ),
            const SizedBox(height: 16),
            Text(
              'No $status coupons',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Your coupons will appear here once you make a purchase.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textHint, fontSize: 13),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => context.go('/home'),
              icon: const Icon(Icons.storefront_outlined),
              label: const Text('Browse Deals'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 根据状态返回对应图标
  IconData _emptyIcon(String status) => switch (status) {
        'unused' => Icons.confirmation_number_outlined,
        'used' => Icons.check_circle_outline,
        'reviews' => Icons.rate_review_outlined,
        'expired' => Icons.timer_off_outlined,
        'refunded' => Icons.currency_exchange,
        'gifted' => Icons.card_giftcard_outlined,
        _ => Icons.confirmation_number_outlined,
      };
}

// ── 即将过期板块（7天内）────────────────────────────────────
class _ExpiringSoonSection extends StatelessWidget {
  final List<CouponModel> coupons;

  const _ExpiringSoonSection({required this.coupons});

  @override
  Widget build(BuildContext context) {
    // 按券名合并
    final dealMap = <String, List<CouponModel>>{};
    for (final c in coupons) {
      final title = c.dealTitle ?? 'Coupon';
      dealMap.putIfAbsent(title, () => []).add(c);
    }

    final now = DateTime.now();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: AppColors.error.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 警告标题
          Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.08),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                const Icon(Icons.timer_outlined, size: 18, color: AppColors.error),
                const SizedBox(width: 8),
                const Text(
                  'Expiring Soon',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: AppColors.error,
                  ),
                ),
                const Spacer(),
                Text(
                  '${coupons.length} voucher${coupons.length > 1 ? 's' : ''}',
                  style: TextStyle(fontSize: 11, color: AppColors.error.withValues(alpha: 0.7)),
                ),
              ],
            ),
          ),

          // 券列表
          ...dealMap.entries.map((entry) {
            final dealCoupons = entry.value;
            final first = dealCoupons.first;
            // 计算剩余天数
            final daysLeft = first.expiresAt != null
                ? first.expiresAt!.difference(now).inDays
                : 0;

            return _CouponRow(
              dealTitle: entry.key,
              imageUrl: first.dealImageUrl,
              quantity: dealCoupons.length,
              expiresAt: first.expiresAt,
              showUrgent: true,
              onTap: () => context.push('/voucher/${first.orderId}?dealId=${first.dealId}'),
            );
          }),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

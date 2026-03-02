// 我的团购券列表页 — 带四个状态 Tab 和下拉刷新

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/models/coupon_model.dart';
import '../../domain/providers/coupons_provider.dart';
import '../widgets/coupon_card.dart';

/// 四个状态 Tab 的配置
const _tabs = [
  (label: 'Unused', status: 'unused'),
  (label: 'Used', status: 'used'),
  (label: 'Expired', status: 'expired'),
  (label: 'Refunded', status: 'refunded'),
];

class CouponsScreen extends ConsumerWidget {
  const CouponsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: _tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('My Coupons'),
          bottom: TabBar(
            isScrollable: false,
            indicatorColor: AppColors.primary,
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.textSecondary,
            tabs: _tabs.map((t) => Tab(text: t.label)).toList(),
          ),
        ),
        body: TabBarView(
          children: _tabs
              .map((t) => _CouponTabView(status: t.status))
              .toList(),
        ),
      ),
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

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(userCouponsProvider),
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: coupons.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (_, i) => CouponCard(
          coupon: coupons[i],
          onTap: () => context.push('/coupon/${coupons[i].id}'),
        ),
      ),
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
        'expired' => Icons.timer_off_outlined,
        'refunded' => Icons.currency_exchange,
        _ => Icons.confirmation_number_outlined,
      };
}

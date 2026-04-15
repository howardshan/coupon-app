import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../data/models/after_sales_request_model.dart';
import '../../domain/providers/after_sales_provider.dart';

/// 个人中心入口：当前用户全部售后申请列表
class MyAfterSalesListPage extends ConsumerWidget {
  const MyAfterSalesListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(afterSalesListProvider(null));

    return Scaffold(
      appBar: AppBar(
        title: const Text('After-Sales'),
      ),
      body: async.when(
        data: (requests) {
          if (requests.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.support_agent_outlined, size: 64, color: AppColors.textHint),
                    const SizedBox(height: 16),
                    const Text(
                      'No after-sales requests yet',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'After you redeem a voucher, you can request help from the order or coupon screen within 7 days.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 24),
                    OutlinedButton.icon(
                      onPressed: () => context.push('/orders'),
                      icon: const Icon(Icons.receipt_long_outlined, size: 18),
                      label: const Text('My Orders'),
                    ),
                  ],
                ),
              ),
            );
          }
          final sorted = [...requests]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
          final dateFmt = DateFormat.yMMMd();

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(afterSalesListProvider(null));
              await ref.read(afterSalesListProvider(null).future);
            },
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: sorted.length,
              separatorBuilder: (context, index) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final r = sorted[i];
                final bucket = AfterSalesOrderCardBucket.fromStatus(r.status);
                return Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => context.push('/after-sales/${r.orderId}'),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  r.reason?.label ?? 'After-sales request',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Submitted ${dateFmt.format(r.createdAt.toLocal())}',
                                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                                ),
                              ],
                            ),
                          ),
                          _StatusChip(bucket: bucket),
                          const SizedBox(width: 4),
                          const Icon(Icons.chevron_right, size: 20, color: AppColors.textHint),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        },
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
                  e.toString(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => ref.invalidate(afterSalesListProvider(null)),
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.bucket});

  final AfterSalesOrderCardBucket bucket;

  @override
  Widget build(BuildContext context) {
    final color = switch (bucket) {
      AfterSalesOrderCardBucket.pending => AppColors.warning,
      AfterSalesOrderCardBucket.rejected => AppColors.textSecondary,
      AfterSalesOrderCardBucket.approved => AppColors.success,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        bucket.shortLabel,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }
}

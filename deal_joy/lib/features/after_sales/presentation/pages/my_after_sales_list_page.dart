import 'package:cached_network_image/cached_network_image.dart';
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
              itemBuilder: (context, i) {
                final r = sorted[i];
                final bucket = AfterSalesOrderCardBucket.fromStatus(r.status);
                final title = (r.dealTitle != null && r.dealTitle!.trim().isNotEmpty)
                    ? r.dealTitle!.trim()
                    : 'After-sales request';
                final orderLabel = r.orderNumber != null && r.orderNumber!.trim().isNotEmpty
                    ? '#${r.orderNumber!.trim().toUpperCase()}'
                    : 'Order ${r.orderId.length >= 8 ? r.orderId.substring(0, 8).toUpperCase() : r.orderId}';

                return Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 主区域：进入该订单下的售后时间线
                      InkWell(
                        onTap: () => context.push('/after-sales/${r.orderId}'),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: r.dealImageUrl != null && r.dealImageUrl!.trim().isNotEmpty
                                    ? CachedNetworkImage(
                                        imageUrl: r.dealImageUrl!.trim(),
                                        width: 56,
                                        height: 56,
                                        fit: BoxFit.cover,
                                        placeholder: (context, url) => _dealThumbPlaceholder(),
                                        errorWidget: (context, url, err) => _dealThumbPlaceholder(),
                                      )
                                    : _dealThumbPlaceholder(),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      title,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    if (r.merchantName != null && r.merchantName!.trim().isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        r.merchantName!.trim(),
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: AppColors.textSecondary,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                    const SizedBox(height: 4),
                                    Text(
                                      orderLabel,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: AppColors.primary,
                                        fontWeight: FontWeight.w600,
                                        fontFamily: 'monospace',
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${r.reason?.label ?? 'Request'} · Submitted ${dateFmt.format(r.createdAt.toLocal())}',
                                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Refund amount \$${r.refundAmount.toStringAsFixed(2)}',
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 6),
                              Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _StatusChip(bucket: bucket),
                                  const SizedBox(height: 4),
                                  const Icon(Icons.chevron_right, size: 20, color: AppColors.textHint),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      // 独立入口：订单详情（不与主区域手势冲突）
                      InkWell(
                        onTap: () => context.push('/order/${r.orderId}'),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceVariant.withValues(alpha: 0.35),
                            border: Border(
                              top: BorderSide(color: AppColors.surfaceVariant.withValues(alpha: 0.8)),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.receipt_long_outlined, size: 18, color: AppColors.primary),
                              const SizedBox(width: 8),
                              const Expanded(
                                child: Text(
                                  'View order detail',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ),
                              const Icon(Icons.chevron_right, size: 20, color: AppColors.textHint),
                            ],
                          ),
                        ),
                      ),
                    ],
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

Widget _dealThumbPlaceholder() {
  return Container(
    width: 56,
    height: 56,
    decoration: BoxDecoration(
      color: AppColors.surfaceVariant,
      borderRadius: BorderRadius.circular(8),
    ),
    child: const Icon(Icons.restaurant_outlined, size: 26, color: AppColors.textHint),
  );
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

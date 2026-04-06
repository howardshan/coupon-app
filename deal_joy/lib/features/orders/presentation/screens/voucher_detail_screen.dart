// Voucher Detail 页 — 从 Coupons 列表或 Orders 列表点击单个 deal 进入
// 布局：Deal 摘要卡片（含券状态行）→ Usage Notes 区块

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../cart/domain/providers/cart_provider.dart';
import '../../../deals/domain/providers/deals_provider.dart';
import '../../data/models/order_detail_model.dart';
import '../../data/models/order_item_model.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../domain/providers/aggregated_deal_voucher_detail_provider.dart';
import '../../domain/providers/orders_provider.dart';
import '../../domain/providers/coupons_provider.dart';
import 'order_detail_screen.dart' show showUnusedQrSheet;
import '../widgets/gift_bottom_sheet.dart';

// ── 主屏幕 ────────────────────────────────────────

class VoucherDetailScreen extends ConsumerWidget {
  final String orderId;
  final String dealId;
  final bool aggregateByDeal;
  final Set<String> aggregatedOrderItemIds;

  const VoucherDetailScreen({
    super.key,
    required this.orderId,
    required this.dealId,
    this.aggregateByDeal = false,
    this.aggregatedOrderItemIds = const <String>{},
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final useAggregate = aggregateByDeal &&
        dealId.isNotEmpty &&
        aggregatedOrderItemIds.isNotEmpty;
    final aggKey = useAggregate
        ? aggregatedDealVoucherCacheKey(dealId, aggregatedOrderItemIds)
        : '';

    final detailAsync = useAggregate
        ? ref.watch(aggregatedDealVoucherDetailProvider(aggKey))
        : ref.watch(userOrderDetailProvider(orderId));

    void refreshDetail() {
      if (useAggregate) {
        ref.invalidate(aggregatedDealVoucherDetailProvider(aggKey));
        ref.invalidate(userCouponsProvider);
      } else {
        ref.invalidate(userOrderDetailProvider(orderId));
      }
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: detailAsync.when(
        data: (detail) => _VoucherDetailBody(
          detail: detail,
          dealId: dealId,
          onRefreshDetail: refreshDetail,
        ),
        loading: () => const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => Scaffold(
          appBar: AppBar(title: const Text('Voucher Detail')),
          body: _ErrorBody(
            onRetry: refreshDetail,
            error: e,
          ),
        ),
      ),
    );
  }
}

// ── 错误占位 ──────────────────────────────────────

class _ErrorBody extends StatelessWidget {
  final VoidCallback onRetry;
  final Object error;

  const _ErrorBody({required this.onRetry, required this.error});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: AppColors.textHint),
            const SizedBox(height: 16),
            Text(
              'Failed to load voucher',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              error.toString(),
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 主体 Widget（带展开状态管理） ──────────────────

class _VoucherDetailBody extends ConsumerStatefulWidget {
  final OrderDetailModel detail;
  final String dealId;
  final VoidCallback onRefreshDetail;

  const _VoucherDetailBody({
    required this.detail,
    required this.dealId,
    required this.onRefreshDetail,
  });

  @override
  ConsumerState<_VoucherDetailBody> createState() => _VoucherDetailBodyState();
}

class _VoucherDetailBodyState extends ConsumerState<_VoucherDetailBody> {
  // 券状态行展开状态
  bool _isExpanded = false;

  OrderDetailModel get detail => widget.detail;

  @override
  Widget build(BuildContext context) {
    // 按 dealId 过滤 items
    final dealItems = detail.items
        .where((i) => i.dealId == widget.dealId)
        .toList();

    // 如果没找到对应 deal 的 items，显示空状态
    if (dealItems.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Voucher Detail'),
          backgroundColor: Colors.white,
          foregroundColor: AppColors.textPrimary,
          elevation: 0.5,
        ),
        body: const Center(
          child: Text(
            'No voucher found',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
      );
    }

    // 判断主要状态并路由到对应展示页
    final dominantStatus = _getDominantStatus(dealItems);

    return switch (dominantStatus) {
      CustomerItemStatus.used => _UsedVoucherBody(
          detail: detail,
          dealItems: dealItems,
          dealId: widget.dealId,
        ),
      CustomerItemStatus.refundSuccess ||
      CustomerItemStatus.refundPending ||
      CustomerItemStatus.refundProcessing ||
      CustomerItemStatus.refundReview => _RefundedVoucherBody(
          detail: detail,
          dealItems: dealItems,
          dealId: widget.dealId,
          onRefreshOrderDetail: widget.onRefreshDetail,
        ),
      CustomerItemStatus.expired => _ExpiredVoucherBody(
          detail: detail,
          dealItems: dealItems,
          dealId: widget.dealId,
          onRefreshOrderDetail: widget.onRefreshDetail,
        ),
      _ => _buildUnusedBody(context, dealItems),
    };
  }

  // 判断所有 items 是否属于同一状态类别
  CustomerItemStatus? _getDominantStatus(List<OrderItemModel> items) {
    if (items.isEmpty) return null;
    final first = items.first.customerStatus;
    if (items.every((i) => i.customerStatus == first)) return first;
    // 退款相关状态统一归类
    if (items.every((i) =>
        i.customerStatus == CustomerItemStatus.refundSuccess ||
        i.customerStatus == CustomerItemStatus.refundPending ||
        i.customerStatus == CustomerItemStatus.refundProcessing ||
        i.customerStatus == CustomerItemStatus.refundReview)) {
      return CustomerItemStatus.refundSuccess;
    }
    return null; // 混合状态 → 使用现有多状态布局
  }

  // ── 现有 unused 布局（保持不变） ──────────────────
  Widget _buildUnusedBody(BuildContext context, List<OrderItemModel> dealItems) {
    final usageRules = dealItems.first.usageRules;

    return Stack(
      children: [
        // 主滚动区域
        CustomScrollView(
          slivers: [
            // 顶部 AppBar
            SliverAppBar(
              pinned: true,
              title: const Text(
                'Voucher Detail',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              ),
              backgroundColor: Colors.white,
              foregroundColor: AppColors.textPrimary,
              elevation: 0.5,
            ),

            // Deal 摘要卡片（含券状态行）
            SliverToBoxAdapter(
              child: _VoucherDealCard(
                dealItems: dealItems,
                isExpanded: _isExpanded,
                paymentIntentId: detail.paymentIntentIdMasked,
                storeCreditUsed: detail.storeCreditUsed,
                orderTotalAmount: detail.totalAmount,
                onToggleExpand: () {
                  setState(() {
                    _isExpanded = !_isExpanded;
                  });
                },
                onRefreshOrder: widget.onRefreshDetail,
              ),
            ),

            // 操作按钮：导航、电话、转赠
            SliverToBoxAdapter(
              child: _VoucherQuickActions(
                merchantId: dealItems.first.purchasedMerchantId,
                couponId: dealItems.first.couponId,
                dealTitle: dealItems.first.dealTitle,
                orderItemId: dealItems.first.id,
                merchantName: dealItems.first.merchantName,
                expiresAt: dealItems.first.couponExpiresAt,
                // 所有 unused item IDs，供 Gift 选择数量
                unusedOrderItemIds: dealItems
                    .where((i) => i.customerStatus == CustomerItemStatus.unused)
                    .map((i) => i.id)
                    .toList(),
              ),
            ),

            // Usage Notes 区块（仅在有规则时显示）
            if (usageRules.isNotEmpty)
              SliverToBoxAdapter(
                child: _UsageNotesSection(usageRules: usageRules),
              ),

            // 底部留白（为固定底部按钮留空间）
            const SliverToBoxAdapter(
              child: SizedBox(height: 100),
            ),
          ],
        ),

        // 固定底部操作栏
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _VoucherBottomActionBar(
            detail: detail,
            dealId: widget.dealId,
            onRefreshOrderDetail: widget.onRefreshDetail,
          ),
        ),
      ],
    );
  }
}

// ── Deal 摘要卡片（含券状态展开行） ───────────────

class _VoucherDealCard extends ConsumerWidget {
  final List<OrderItemModel> dealItems;
  final bool isExpanded;
  final VoidCallback onToggleExpand;
  final VoidCallback onRefreshOrder;
  final String? paymentIntentId;
  final double storeCreditUsed;
  final double orderTotalAmount;

  const _VoucherDealCard({
    required this.dealItems,
    required this.isExpanded,
    required this.onToggleExpand,
    required this.onRefreshOrder,
    this.paymentIntentId,
    this.storeCreditUsed = 0.0,
    this.orderTotalAmount = 0.0,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final first = dealItems.first;
    final amountFmt = NumberFormat.currency(symbol: '\$', decimalDigits: 2);

    // 计算实际有效金额（排除已退款的 items）
    final activeItems = dealItems.where((i) =>
        i.customerStatus != CustomerItemStatus.refundSuccess &&
        i.customerStatus != CustomerItemStatus.refundPending &&
        i.customerStatus != CustomerItemStatus.refundProcessing &&
        i.customerStatus != CustomerItemStatus.refundReview).toList();
    final totalPaid = activeItems.fold<double>(0, (s, i) => s + i.unitPrice);
    final merchantName = first.merchantName ?? first.purchasedMerchantName;

    // 按状态分组
    final unusedItems = dealItems
        .where((i) => i.customerStatus == CustomerItemStatus.unused)
        .toList();
    final usedItems = dealItems
        .where((i) => i.customerStatus == CustomerItemStatus.used)
        .toList();
    final refundedItems = dealItems
        .where((i) =>
            i.customerStatus == CustomerItemStatus.refundSuccess ||
            i.customerStatus == CustomerItemStatus.refundPending ||
            i.customerStatus == CustomerItemStatus.refundProcessing ||
            i.customerStatus == CustomerItemStatus.refundReview)
        .toList();
    final otherItems = dealItems
        .where((i) =>
            i.customerStatus != CustomerItemStatus.unused &&
            i.customerStatus != CustomerItemStatus.used &&
            i.customerStatus != CustomerItemStatus.refundSuccess &&
            i.customerStatus != CustomerItemStatus.refundPending &&
            i.customerStatus != CustomerItemStatus.refundProcessing &&
            i.customerStatus != CustomerItemStatus.refundReview)
        .toList();

    return Container(
      margin: const EdgeInsets.fromLTRB(0, 8, 0, 0),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Deal 摘要行：图片 + 标题 + 商家 + 有效期 + 价格
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Deal 封面图
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: first.dealImageUrl != null
                      ? Image.network(
                          first.dealImageUrl!,
                          width: 80,
                          height: 80,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, _) =>
                              _PlaceholderImage(),
                        )
                      : _PlaceholderImage(),
                ),
                const SizedBox(width: 12),
                // 文字信息
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        first.dealTitle,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                          height: 1.3,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (merchantName != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          merchantName,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                      if (first.couponExpiresAt != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Valid until ${DateFormat('MMM d, yyyy').format(first.couponExpiresAt!.toLocal())}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textHint,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      // 价格行
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${amountFmt.format(first.unitPrice)} × ${activeItems.length}',
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          Text(
                            'Paid ${amountFmt.format(totalPaid)}',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1, color: Color(0xFFF0F0F0)),

          // 券状态汇总行
          if (unusedItems.isNotEmpty)
            _CouponStatusRow(
              label: 'Unused',
              count: unusedItems.length,
              color: const Color(0xFF00C853),
              items: unusedItems,
              isExpanded: false,
              onToggle: () => showUnusedQrSheet(context, unusedItems),
              onRefreshOrder: onRefreshOrder,
              paymentIntentId: paymentIntentId,
              storeCreditUsed: storeCreditUsed,
              orderTotalAmount: orderTotalAmount,
            ),
          if (usedItems.isNotEmpty)
            _CouponStatusRow(
              label: 'Used',
              count: usedItems.length,
              color: const Color(0xFF2979FF),
              items: usedItems,
              isExpanded: isExpanded && unusedItems.isEmpty,
              onToggle: unusedItems.isEmpty ? onToggleExpand : null,
              onRefreshOrder: onRefreshOrder,
              paymentIntentId: paymentIntentId,
              storeCreditUsed: storeCreditUsed,
              orderTotalAmount: orderTotalAmount,
            ),
          if (refundedItems.isNotEmpty)
            _CouponStatusRow(
              label: (refundedItems.first.customerStatus ==
                          CustomerItemStatus.refundPending ||
                      refundedItems.first.customerStatus ==
                          CustomerItemStatus.refundProcessing ||
                      refundedItems.first.customerStatus ==
                          CustomerItemStatus.refundReview)
                  ? 'Refund Processing'
                  : 'Refunded',
              count: refundedItems.length,
              color: const Color(0xFF9E9E9E),
              items: refundedItems,
              isExpanded: false,
              onToggle: null,
              onRefreshOrder: onRefreshOrder,
              paymentIntentId: paymentIntentId,
              storeCreditUsed: storeCreditUsed,
              orderTotalAmount: orderTotalAmount,
            ),
          if (otherItems.isNotEmpty)
            _CouponStatusRow(
              label: otherItems.first.customerStatus.displayLabel,
              count: otherItems.length,
              color: AppColors.textHint,
              items: otherItems,
              isExpanded: false,
              onToggle: null,
              onRefreshOrder: onRefreshOrder,
              paymentIntentId: paymentIntentId,
              storeCreditUsed: storeCreditUsed,
              orderTotalAmount: orderTotalAmount,
            ),
        ],
      ),
    );
  }
}

// ── 券状态行（可展开） ────────────────────────────

class _CouponStatusRow extends ConsumerWidget {
  final String label;
  final int count;
  final Color color;
  final List<OrderItemModel> items;
  final bool isExpanded;
  final VoidCallback? onToggle;
  final VoidCallback onRefreshOrder;
  final String? paymentIntentId;
  final double storeCreditUsed;
  final double orderTotalAmount;

  const _CouponStatusRow({
    required this.label,
    required this.count,
    required this.color,
    required this.items,
    required this.isExpanded,
    required this.onToggle,
    required this.onRefreshOrder,
    this.paymentIntentId,
    this.storeCreditUsed = 0.0,
    this.orderTotalAmount = 0.0,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        // 状态行标题
        InkWell(
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '$label ($count)',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
                const Spacer(),
                if (onToggle != null) ...[
                  Text(
                    'View Details',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    isExpanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_right_rounded,
                    size: 18,
                    color: AppColors.textSecondary,
                  ),
                ],
              ],
            ),
          ),
        ),

        // 展开后：每张券的详情
        if (isExpanded && onToggle != null) ...[
          const Divider(height: 1, color: Color(0xFFF0F0F0)),
          ...items.map((item) => _CouponDetailRow(
                item: item,
                allItems: items,
                paymentIntentId: paymentIntentId,
                onRefreshOrder: onRefreshOrder,
                storeCreditUsed: storeCreditUsed,
                orderTotalAmount: orderTotalAmount,
              )),
        ],

        const Divider(height: 1, color: Color(0xFFF0F0F0)),
      ],
    );
  }
}

// ── 单张券详情行 ──────────────────────────────────

class _CouponDetailRow extends ConsumerWidget {
  final OrderItemModel item;
  final List<OrderItemModel> allItems;
  final String? paymentIntentId;
  final VoidCallback onRefreshOrder;
  final double storeCreditUsed;
  final double orderTotalAmount;

  const _CouponDetailRow({
    required this.item,
    required this.allItems,
    this.paymentIntentId,
    required this.onRefreshOrder,
    this.storeCreditUsed = 0.0,
    this.orderTotalAmount = 0.0,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final formattedCode = item.formattedCouponCode;

    return GestureDetector(
      onTap: () {
        // 点击券码行，跳转到 coupon QR 页面
        final cId = item.couponId;
        if (cId != null && cId.isNotEmpty) {
          context.push('/coupon/$cId');
        }
      },
      child: Container(
        color: const Color(0xFFFAFAFA),
        padding: const EdgeInsets.fromLTRB(24, 12, 16, 12),
        child: Row(
          children: [
            // 券码（可点击跳转 coupon 页面）
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (formattedCode != null)
                        Text(
                          formattedCode,
                          style: const TextStyle(
                            fontSize: 14,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.5,
                            color: AppColors.primary,
                          ),
                        )
                      else
                        const Text(
                          'No code',
                          style: TextStyle(
                              fontSize: 13, color: AppColors.textHint),
                        ),
                      const SizedBox(width: 4),
                      const Icon(Icons.arrow_forward_ios,
                          size: 12, color: AppColors.primary),
                    ],
                  ),
                  // 状态标签
                  const SizedBox(height: 2),
                  Text(
                    item.customerStatus.displayLabel,
                    style: TextStyle(
                      fontSize: 12,
                      color: _statusColor(item.customerStatus),
                    ),
                  ),
                  // 核销时间
                  if (item.redeemedAt != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Used ${DateFormat('MMM d, yyyy').format(item.redeemedAt!.toLocal())}',
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textHint),
                    ),
                  ],
                ],
              ),
            ),
            // 操作按钮
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (item.showCancel)
                  _SmallButton(
                    label: 'Cancel',
                    color: AppColors.error,
                    onTap: () => _showCancelSheet(context, ref, item),
                  ),
                if (item.showRefundRequest)
                  _SmallButton(
                    label: 'Refund',
                    color: AppColors.warning,
                    onTap: () => _showCancelSheet(context, ref, item),
                  ),
                if (item.showWriteReview)
                  _SmallButton(
                    label: 'Review',
                    color: AppColors.accent,
                    onTap: () {
                      final merchantId = item.purchasedMerchantId ?? item.redeemedMerchantId ?? '';
                      context.push('/review/${item.dealId}?merchantId=$merchantId&orderItemId=${item.id}');
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // 根据状态返回颜色
  Color _statusColor(CustomerItemStatus status) {
    return switch (status) {
      CustomerItemStatus.unused => const Color(0xFF00C853),
      CustomerItemStatus.used => const Color(0xFF2979FF),
      CustomerItemStatus.refundSuccess => const Color(0xFF9E9E9E),
      CustomerItemStatus.refundPending => const Color(0xFFFF9800),
      CustomerItemStatus.refundProcessing => const Color(0xFFFF9800),
      CustomerItemStatus.refundReview => const Color(0xFFFF9800),
      _ => AppColors.textHint,
    };
  }

  // 展示取消/退款 Bottom Sheet
  void _showCancelSheet(
      BuildContext context, WidgetRef ref, OrderItemModel item) {
    // 同 deal 下所有 unused items
    final sameDealUnused = allItems
        .where((i) =>
            i.dealId == item.dealId &&
            i.customerStatus == CustomerItemStatus.unused)
        .toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _CancelSheet(
        item: item,
        totalUnusedCount: sameDealUnused.length,
        allUnusedItems: sameDealUnused,
        paymentIntentId: paymentIntentId,
        storeCreditUsed: storeCreditUsed,
        orderTotalAmount: orderTotalAmount,
        onConfirm: (refundMethod,
            {int cancelCount = 1,
            List<String>? selectedItemIds}) async {
          final navigator = Navigator.of(context);
          final messenger = ScaffoldMessenger.of(context);
          final List<OrderItemModel> itemsToCancel;
          if (selectedItemIds != null && selectedItemIds.isNotEmpty) {
            final idSet = selectedItemIds.toSet();
            itemsToCancel =
                sameDealUnused.where((i) => idSet.contains(i.id)).toList();
          } else {
            itemsToCancel = sameDealUnused.take(cancelCount).toList();
          }
          int successCount = 0;
          for (final cancelItem in itemsToCancel) {
            final ok = await ref
                .read(refundNotifierProvider.notifier)
                .requestItemRefund(
                  cancelItem.id,
                  refundMethod: refundMethod,
                );
            if (ok) successCount++;
          }
          navigator.pop();
          if (successCount > 0) {
            messenger.showSnackBar(
              SnackBar(
                content: Text(
                    '$successCount voucher${successCount > 1 ? 's' : ''} cancelled successfully'),
                behavior: SnackBarBehavior.floating,
              ),
            );
            onRefreshOrder();
          } else {
            messenger.showSnackBar(
              const SnackBar(
                content: Text('Failed to cancel voucher'),
                behavior: SnackBarBehavior.floating,
                backgroundColor: AppColors.error,
              ),
            );
          }
        },
      ),
    );
  }
}

// ── 小尺寸操作按钮 ────────────────────────────────

class _SmallButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _SmallButton({
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: color.withValues(alpha: 0.6)),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ),
    );
  }
}

// ── Usage Notes 区块 ──────────────────────────────

class _UsageNotesSection extends StatelessWidget {
  final List<String> usageRules;

  const _UsageNotesSection({required this.usageRules});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Usage Notes',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          ...usageRules.map(
            (rule) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '• ',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                      height: 1.5,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      rule,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                        height: 1.5,
                      ),
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

// ── 快捷操作按钮：导航、电话、转赠 ────────────────

class _VoucherQuickActions extends StatefulWidget {
  final String? merchantId;
  final String? couponId;
  // Gift Bottom Sheet 所需参数
  final String? dealTitle;
  final String? orderItemId;
  final String? merchantName;
  final DateTime? expiresAt;
  // 所有 unused item IDs，供 Gift 选择赠送数量
  final List<String> unusedOrderItemIds;

  const _VoucherQuickActions({
    this.merchantId,
    this.couponId,
    this.dealTitle,
    this.orderItemId,
    this.merchantName,
    this.expiresAt,
    this.unusedOrderItemIds = const [],
  });

  @override
  State<_VoucherQuickActions> createState() => _VoucherQuickActionsState();
}

class _VoucherQuickActionsState extends State<_VoucherQuickActions> {
  String? _address;
  String? _phone;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadMerchantInfo();
  }

  Future<void> _loadMerchantInfo() async {
    final merchantId = widget.merchantId;
    if (merchantId == null) {
      setState(() => _loaded = true);
      return;
    }
    try {
      final data = await Supabase.instance.client
          .from('merchants')
          .select('address, phone')
          .eq('id', merchantId)
          .maybeSingle();
      if (mounted) {
        setState(() {
          _address = data?['address'] as String?;
          _phone = data?['phone'] as String?;
          _loaded = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  Future<void> _navigateToStore() async {
    if (_address == null) return;
    final encoded = Uri.encodeComponent(_address!);
    final uri = Uri.parse('https://maps.google.com/?q=$encoded');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _callStore() async {
    if (_phone == null) return;
    final uri = Uri(scheme: 'tel', path: _phone);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  void _giftToFriend() {
    final orderItemId = widget.orderItemId;
    if (orderItemId == null) return;
    // 调用 Gift Bottom Sheet，传入所有 unused item IDs 供选择数量
    GiftBottomSheet.show(
      context,
      dealTitle: widget.dealTitle ?? '',
      orderItemId: orderItemId,
      merchantName: widget.merchantName,
      expiresAt: widget.expiresAt,
      unusedOrderItemIds: widget.unusedOrderItemIds,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(top: 8),
      color: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          if (_address != null)
            _QuickActionItem(
              icon: Icons.directions_outlined,
              label: 'Navigate',
              color: AppColors.primary,
              onTap: _navigateToStore,
            ),
          if (_phone != null)
            _QuickActionItem(
              icon: Icons.phone_outlined,
              label: 'Call Store',
              color: AppColors.info,
              onTap: _callStore,
            ),
          _QuickActionItem(
            icon: Icons.card_giftcard_outlined,
            label: 'Gift',
            color: AppColors.secondary,
            onTap: _giftToFriend,
          ),
        ],
      ),
    );
  }
}

class _QuickActionItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickActionItem({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(height: 6),
          Text(label, style: TextStyle(fontSize: 12, color: color)),
        ],
      ),
    );
  }
}

// ── 底部固定操作栏 ────────────────────────────────

class _VoucherBottomActionBar extends ConsumerWidget {
  final OrderDetailModel detail;
  final String dealId;
  final VoidCallback onRefreshOrderDetail;

  const _VoucherBottomActionBar({
    required this.detail,
    required this.dealId,
    required this.onRefreshOrderDetail,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 仅找该 deal 下可取消的 items
    final cancelableItems = detail.items
        .where((i) => i.dealId == dealId && i.showCancel)
        .toList();
    final hasUnused = cancelableItems.isNotEmpty;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFEEEEEE), width: 1)),
      ),
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        12 + MediaQuery.of(context).padding.bottom,
      ),
      child: Row(
        children: [
          // Cancel 按钮（有 unused 才显示）
          if (hasUnused) ...[
            Expanded(
              child: OutlinedButton(
                onPressed: () => _showBatchCancelSheet(
                  context,
                  ref,
                  cancelableItems.first,
                  cancelableItems,
                  onRefreshOrderDetail,
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.error),
                  foregroundColor: AppColors.error,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
                child: const Text(
                  'Cancel',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],

          // Buy Again 按钮
          Expanded(
            flex: hasUnused ? 1 : 2,
            child: ElevatedButton(
              onPressed: () => _handleBuyAgain(context, ref),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                elevation: 0,
              ),
              child: const Text(
                'Buy Again',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Buy Again：将该 deal 的券重新加入购物车并跳转结账 ─────────
  Future<void> _handleBuyAgain(BuildContext context, WidgetRef ref) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);

    // 显示加载指示器
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: Colors.white),
      ),
    );

    try {
      final dealsRepo = ref.read(dealsRepositoryProvider);
      final cartNotifier = ref.read(cartProvider.notifier);

      // 仅取当前 deal 对应的订单项
      final orderItems =
          detail.items.where((i) => i.dealId == dealId).toList();
      if (orderItems.isEmpty) {
        navigator.pop();
        return;
      }

      try {
        final deal = await dealsRepo.fetchDealById(dealId);

        // 检查是否已过期
        if (deal.isExpired) {
          navigator.pop();
          messenger.showSnackBar(SnackBar(
            content: Text('${deal.title} is no longer available.'),
          ));
          return;
        }

        // 检查限购
        int allowCount = orderItems.length;
        if (deal.maxPerAccount > 0) {
          final userId = Supabase.instance.client.auth.currentUser?.id;
          if (userId != null) {
            final res = await Supabase.instance.client
                .from('order_items')
                .select('id, orders!inner(user_id)')
                .eq('deal_id', dealId)
                .eq('orders.user_id', userId)
                .neq('customer_status', 'refund_success');
            final purchasedCount = (res as List).length;

            final cartItems = ref.read(cartProvider).valueOrNull ?? [];
            final cartCount =
                cartItems.where((c) => c.dealId == dealId).length;

            final remaining =
                deal.maxPerAccount - purchasedCount - cartCount;
            if (remaining <= 0) {
              navigator.pop();
              messenger.showSnackBar(SnackBar(
                content: Text(
                    '${deal.title} has reached the purchase limit.'),
              ));
              return;
            }
            allowCount = remaining < orderItems.length
                ? remaining
                : orderItems.length;
          }
        }

        // 收集要加入购物车的数据
        final itemsToAdd = <OrderItemBuyAgainData>[];
        for (var i = 0; i < allowCount; i++) {
          final oi = orderItems[i];
          itemsToAdd.add(OrderItemBuyAgainData(
            dealId: oi.dealId,
            unitPrice: oi.unitPrice,
            purchasedMerchantId: oi.purchasedMerchantId,
            applicableStoreIds: oi.applicableStoreIds,
            selectedOptions: oi.selectedOptions,
          ));
        }

        // 关闭 loading
        navigator.pop();

        // 批量加入购物车
        final addedItems =
            await cartNotifier.addBulkFromOrderItems(itemsToAdd);

        // 如果因限购只能加入部分，提示用户
        if (allowCount < orderItems.length) {
          final skipped = orderItems.length - allowCount;
          messenger.showSnackBar(SnackBar(
            content: Text(
                '$skipped coupon(s) skipped due to purchase limit.'),
            duration: const Duration(seconds: 3),
          ));
        }

        // 跳转到结账页
        if (addedItems.isNotEmpty) {
          router.push('/checkout-cart', extra: addedItems);
        }
      } catch (_) {
        navigator.pop();
        messenger.showSnackBar(SnackBar(
          content: Text(
              '${orderItems.first.dealTitle} is no longer available.'),
        ));
      }
    } catch (e) {
      navigator.pop();
      messenger.showSnackBar(SnackBar(
        content: Text('Failed to re-order: $e'),
      ));
    }
  }

  // 批量取消 Bottom Sheet
  void _showBatchCancelSheet(
    BuildContext context,
    WidgetRef ref,
    OrderItemModel item,
    List<OrderItemModel> allUnused,
    VoidCallback onRefreshOrderDetail,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _CancelSheet(
        item: item,
        totalUnusedCount: allUnused.length,
        allUnusedItems: allUnused,
        paymentIntentId: detail.paymentIntentIdMasked,
        storeCreditUsed: detail.storeCreditUsed,
        orderTotalAmount: detail.totalAmount,
        onConfirm: (refundMethod,
            {int cancelCount = 1,
            List<String>? selectedItemIds}) async {
          final navigator = Navigator.of(context);
          final messenger = ScaffoldMessenger.of(context);
          final List<OrderItemModel> itemsToCancel;
          if (selectedItemIds != null && selectedItemIds.isNotEmpty) {
            final idSet = selectedItemIds.toSet();
            itemsToCancel = allUnused.where((i) => idSet.contains(i.id)).toList();
          } else {
            itemsToCancel = allUnused.take(cancelCount).toList();
          }
          int successCount = 0;
          for (final cancelItem in itemsToCancel) {
            final ok = await ref
                .read(refundNotifierProvider.notifier)
                .requestItemRefund(cancelItem.id, refundMethod: refundMethod);
            if (ok) successCount++;
          }
          navigator.pop();
          if (successCount > 0) {
            messenger.showSnackBar(
              SnackBar(
                content: Text(
                    '$successCount voucher${successCount > 1 ? 's' : ''} cancelled'),
                behavior: SnackBarBehavior.floating,
              ),
            );
            onRefreshOrderDetail();
          } else {
            messenger.showSnackBar(
              const SnackBar(
                content: Text('Failed to cancel'),
                behavior: SnackBarBehavior.floating,
                backgroundColor: AppColors.error,
              ),
            );
          }
        },
      ),
    );
  }
}

// ── Deal 图片占位符 ───────────────────────────────

class _PlaceholderImage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 80,
      height: 80,
      color: AppColors.surfaceVariant,
      child: const Icon(
        Icons.local_offer_outlined,
        color: AppColors.textHint,
        size: 32,
      ),
    );
  }
}

// ── Cancel / Refund Bottom Sheet ──────────────────

class _CancelSheet extends ConsumerStatefulWidget {
  final OrderItemModel item;
  final int totalUnusedCount;
  final List<OrderItemModel> allUnusedItems;
  final String? paymentIntentId;
  final double storeCreditUsed;
  final double orderTotalAmount;
  final Future<void> Function(String refundMethod,
      {int cancelCount, List<String>? selectedItemIds}) onConfirm;

  const _CancelSheet({
    required this.item,
    this.totalUnusedCount = 1,
    this.allUnusedItems = const [],
    this.paymentIntentId,
    this.storeCreditUsed = 0.0,
    this.orderTotalAmount = 0.0,
    required this.onConfirm,
  });

  @override
  ConsumerState<_CancelSheet> createState() => _CancelSheetState();
}

class _CancelSheetState extends ConsumerState<_CancelSheet> {
  String _selectedMethod = 'store_credit';
  bool _isSubmitting = false;
  late int _cancelCount;
  late Set<String> _selectedIds;

  bool get _isPaidByStoreCredit {
    if (widget.storeCreditUsed > 0 &&
        widget.orderTotalAmount > 0 &&
        widget.storeCreditUsed >= widget.orderTotalAmount) {
      return true;
    }
    final piId = widget.paymentIntentId ?? '';
    return piId.contains('store_credit');
  }

  bool get _isPartialStoreCredit =>
      !_isPaidByStoreCredit && widget.storeCreditUsed > 0;

  @override
  void initState() {
    super.initState();
    _cancelCount = 1;
    _selectedIds = widget.allUnusedItems.map((i) => i.id).toSet();
    if (_isPaidByStoreCredit) {
      _selectedMethod = 'store_credit';
    }
  }

  List<Widget> _buildRefundOptions(bool isCancel) {
    if (_isPaidByStoreCredit) {
      return [
        _RefundMethodOption(
          selected: true,
          title: 'Store Credit',
          subtitle: 'Full amount incl. service fee · Instant',
          badge: 'Only Option',
          badgeColor: AppColors.success,
          onTap: () {},
        ),
      ];
    }

    String originalPaymentSubtitle;
    if (_isPartialStoreCredit && isCancel) {
      final creditUsedFmt = widget.storeCreditUsed.toStringAsFixed(2);
      originalPaymentSubtitle =
          'Store Credit portion (\$$creditUsedFmt) refunds to Store Credit first, '
          'remainder to card\n'
          'Service fee non-refundable · 5-10 business days';
    } else {
      originalPaymentSubtitle = isCancel
          ? 'Excluding service fee · 5-10 business days'
          : '5-10 business days to original card';
    }

    return [
      _RefundMethodOption(
        selected: _selectedMethod == 'store_credit',
        title: 'Store Credit',
        subtitle: isCancel
            ? 'Full amount incl. service fee · Instant'
            : 'Processed within 1-2 business days',
        badge: 'Recommended',
        badgeColor: AppColors.success,
        onTap: () => setState(() => _selectedMethod = 'store_credit'),
      ),
      const SizedBox(height: 12),
      _RefundMethodOption(
        selected: _selectedMethod == 'original_payment',
        title: 'Original Payment',
        subtitle: originalPaymentSubtitle,
        onTap: () => setState(() => _selectedMethod = 'original_payment'),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final isCancel = widget.item.showCancel;
    final totalUnused = widget.totalUnusedCount;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        24,
        24,
        24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 拖拽指示条
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.textHint,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // 标题
          Text(
            isCancel ? 'Cancel Voucher' : 'Request Refund',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isCancel
                ? 'Choose how you would like to receive your refund.'
                : 'You used this voucher. Choose a refund method.',
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),

          // 多张券时显示券选择列表
          if (totalUnused > 1) ...[
            const SizedBox(height: 16),
            GestureDetector(
              onTap: () {
                setState(() {
                  if (_selectedIds.length == widget.allUnusedItems.length) {
                    _selectedIds = {widget.allUnusedItems.first.id};
                  } else {
                    _selectedIds =
                        widget.allUnusedItems.map((i) => i.id).toSet();
                  }
                  _cancelCount = _selectedIds.length;
                });
              },
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    const Text(
                      'Select vouchers to cancel',
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w500),
                    ),
                    const Spacer(),
                    Text(
                      _selectedIds.length == widget.allUnusedItems.length
                          ? 'Deselect All'
                          : 'Select All',
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.primary),
                    ),
                  ],
                ),
              ),
            ),
            // 每张券的复选框列表
            ...widget.allUnusedItems.map((unusedItem) {
              final code = unusedItem.formattedCouponCode ?? 'No code';
              final isSelected = _selectedIds.contains(unusedItem.id);
              return GestureDetector(
                onTap: () {
                  setState(() {
                    if (isSelected && _selectedIds.length > 1) {
                      _selectedIds.remove(unusedItem.id);
                    } else if (!isSelected) {
                      _selectedIds.add(unusedItem.id);
                    }
                    _cancelCount = _selectedIds.length;
                  });
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Icon(
                        isSelected
                            ? Icons.check_box_rounded
                            : Icons.check_box_outline_blank_rounded,
                        color: isSelected
                            ? AppColors.primary
                            : AppColors.textHint,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        code,
                        style: const TextStyle(
                          fontSize: 13,
                          fontFamily: 'monospace',
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],

          const SizedBox(height: 20),

          // 退款方式选项
          ..._buildRefundOptions(isCancel),

          const SizedBox(height: 24),

          // 确认按钮
          ElevatedButton(
            onPressed: _isSubmitting
                ? null
                : () async {
                    setState(() => _isSubmitting = true);
                    await widget.onConfirm(
                      _selectedMethod,
                      cancelCount: _cancelCount,
                      selectedItemIds: _selectedIds.toList(),
                    );
                    if (mounted) setState(() => _isSubmitting = false);
                  },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
            ),
            child: _isSubmitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : Text(
                    isCancel
                        ? 'Confirm Cancel${_cancelCount > 1 ? ' ($_cancelCount)' : ''}'
                        : 'Confirm Refund',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// ── 退款方式选项卡 ────────────────────────────────

class _RefundMethodOption extends StatelessWidget {
  final bool selected;
  final String title;
  final String subtitle;
  final String? badge;
  final Color? badgeColor;
  final VoidCallback onTap;

  const _RefundMethodOption({
    required this.selected,
    required this.title,
    required this.subtitle,
    this.badge,
    this.badgeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          border: Border.all(
            color: selected ? AppColors.primary : const Color(0xFFE0E0E0),
            width: selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
          color: selected
              ? AppColors.primary.withValues(alpha: 0.04)
              : Colors.white,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_off_rounded,
              color: selected ? AppColors.primary : AppColors.textHint,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: selected
                              ? AppColors.primary
                              : AppColors.textPrimary,
                        ),
                      ),
                      if (badge != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: (badgeColor ?? AppColors.success)
                                .withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            badge!,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: badgeColor ?? AppColors.success,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
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
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════
// 状态独立展示页
// ══════════════════════════════════════════════════════

// ── 简化 Deal 摘要卡片（不含券状态行） ─────────────

class _SimpleDealCard extends StatelessWidget {
  final List<OrderItemModel> dealItems;

  const _SimpleDealCard({required this.dealItems});

  @override
  Widget build(BuildContext context) {
    final first = dealItems.first;
    final amountFmt = NumberFormat.currency(symbol: '\$', decimalDigits: 2);
    // 计算实际有效金额（排除已退款的 items）
    final activeItems = dealItems.where((i) =>
        i.customerStatus != CustomerItemStatus.refundSuccess &&
        i.customerStatus != CustomerItemStatus.refundPending &&
        i.customerStatus != CustomerItemStatus.refundProcessing &&
        i.customerStatus != CustomerItemStatus.refundReview).toList();
    final totalPaid = activeItems.fold<double>(0, (s, i) => s + i.unitPrice);
    final merchantName = first.merchantName ?? first.purchasedMerchantName;

    return Container(
      margin: const EdgeInsets.fromLTRB(0, 8, 0, 0),
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: first.dealImageUrl != null
                ? Image.network(
                    first.dealImageUrl!,
                    width: 80,
                    height: 80,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _PlaceholderImage(),
                  )
                : _PlaceholderImage(),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  first.dealTitle,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                    height: 1.3,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (merchantName != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    merchantName,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${amountFmt.format(first.unitPrice)} × ${activeItems.length}',
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    Text(
                      'Paid ${amountFmt.format(totalPaid)}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── 信息行组件 ──────────────────────────────────────

class _StatusInfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final bool isBadge;

  const _StatusInfoRow({
    required this.label,
    required this.value,
    this.valueColor,
    this.isBadge = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
        if (isBadge)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: (valueColor ?? AppColors.textSecondary)
                  .withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: valueColor ?? AppColors.textSecondary,
              ),
            ),
          )
        else
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: valueColor ?? AppColors.textPrimary,
            ),
          ),
      ],
    );
  }
}

// ── Used 状态展示页 ─────────────────────────────────

class _UsedVoucherBody extends ConsumerWidget {
  final OrderDetailModel detail;
  final List<OrderItemModel> dealItems;
  final String dealId;

  const _UsedVoucherBody({
    required this.detail,
    required this.dealItems,
    required this.dealId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final first = dealItems.first;
    final dateFmt = DateFormat('MMM d, yyyy');
    final usageRules = first.usageRules;
    final redeemedMerchant =
        first.redeemedMerchantName ?? first.merchantName ?? '';

    return Stack(
      children: [
        CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: true,
              title: const Text(
                'Voucher Detail',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              ),
              backgroundColor: Colors.white,
              foregroundColor: AppColors.textPrimary,
              elevation: 0.5,
            ),

            // Deal 摘要卡片
            SliverToBoxAdapter(
              child: _SimpleDealCard(dealItems: dealItems),
            ),

            // 状态 + 日期信息
            SliverToBoxAdapter(
              child: Container(
                margin: const EdgeInsets.only(top: 8),
                color: Colors.white,
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _StatusInfoRow(
                      label: 'Status',
                      value: 'Used',
                      valueColor: const Color(0xFF2979FF),
                      isBadge: true,
                    ),
                    const Divider(height: 24, color: Color(0xFFF0F0F0)),
                    _StatusInfoRow(
                      label: 'Purchased',
                      value: dateFmt.format(detail.createdAt.toLocal()),
                    ),
                    if (first.redeemedAt != null) ...[
                      const SizedBox(height: 12),
                      _StatusInfoRow(
                        label: 'Used On',
                        value: dateFmt.format(first.redeemedAt!.toLocal()),
                      ),
                    ],
                    if (redeemedMerchant.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _StatusInfoRow(
                        label: 'Redeemed At',
                        value: redeemedMerchant,
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // 快捷操作：导航、电话
            SliverToBoxAdapter(
              child: _VoucherQuickActions(
                merchantId: first.purchasedMerchantId,
                couponId: first.couponId,
                dealTitle: first.dealTitle,
                orderItemId: first.id,
                merchantName: first.merchantName,
                expiresAt: first.couponExpiresAt,
              ),
            ),

            // Usage Notes
            if (usageRules.isNotEmpty)
              SliverToBoxAdapter(
                child: _UsageNotesSection(usageRules: usageRules),
              ),

            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),

        // 底部操作栏：Write Review + Buy Again
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _UsedBottomBar(
            dealItems: dealItems,
            dealId: dealId,
          ),
        ),
      ],
    );
  }
}

// ── Refunded 状态展示页 ─────────────────────────────

class _RefundedVoucherBody extends ConsumerWidget {
  final OrderDetailModel detail;
  final List<OrderItemModel> dealItems;
  final String dealId;
  final VoidCallback onRefreshOrderDetail;

  const _RefundedVoucherBody({
    required this.detail,
    required this.dealItems,
    required this.dealId,
    required this.onRefreshOrderDetail,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final first = dealItems.first;
    final dateFmt = DateFormat('MMM d, yyyy');
    final amountFmt = NumberFormat.currency(symbol: '\$', decimalDigits: 2);
    final usageRules = first.usageRules;

    // 退款信息
    final totalRefund = dealItems.fold<double>(
        0, (s, i) => s + (i.refundAmount ?? i.unitPrice));
    final refundMethod = first.refundMethod;

    // 状态文案
    final statusLabel =
        first.customerStatus == CustomerItemStatus.refundPending ||
                first.customerStatus == CustomerItemStatus.refundProcessing
            ? 'Refund Processing'
            : first.customerStatus == CustomerItemStatus.refundReview
                ? 'Under Review'
                : 'Refunded';
    final statusColor =
        first.customerStatus == CustomerItemStatus.refundSuccess
            ? const Color(0xFF9E9E9E)
            : const Color(0xFFFF9800);

    return Stack(
      children: [
        CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: true,
              title: const Text(
                'Voucher Detail',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              ),
              backgroundColor: Colors.white,
              foregroundColor: AppColors.textPrimary,
              elevation: 0.5,
            ),

            // Deal 摘要卡片
            SliverToBoxAdapter(
              child: _SimpleDealCard(dealItems: dealItems),
            ),

            // 状态 + 日期 + 退款信息
            SliverToBoxAdapter(
              child: Container(
                margin: const EdgeInsets.only(top: 8),
                color: Colors.white,
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _StatusInfoRow(
                      label: 'Status',
                      value: statusLabel,
                      valueColor: statusColor,
                      isBadge: true,
                    ),
                    const Divider(height: 24, color: Color(0xFFF0F0F0)),
                    _StatusInfoRow(
                      label: 'Purchased',
                      value: dateFmt.format(detail.createdAt.toLocal()),
                    ),
                    if (first.refundedAt != null) ...[
                      const SizedBox(height: 12),
                      _StatusInfoRow(
                        label: 'Refunded',
                        value: dateFmt.format(first.refundedAt!.toLocal()),
                      ),
                    ],
                    const Divider(height: 24, color: Color(0xFFF0F0F0)),
                    _StatusInfoRow(
                      label: 'Refund Amount',
                      value: amountFmt.format(totalRefund),
                      valueColor: AppColors.success,
                    ),
                    if (refundMethod != null) ...[
                      const SizedBox(height: 12),
                      _StatusInfoRow(
                        label: 'Refund To',
                        value: refundMethod == 'store_credit'
                            ? 'Store Credit'
                            : 'Original Payment',
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // Usage Notes
            if (usageRules.isNotEmpty)
              SliverToBoxAdapter(
                child: _UsageNotesSection(usageRules: usageRules),
              ),

            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),

        // 底部：Buy Again
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _VoucherBottomActionBar(
            detail: detail,
            dealId: dealId,
            onRefreshOrderDetail: onRefreshOrderDetail,
          ),
        ),
      ],
    );
  }
}

// ── Expired 状态展示页 ──────────────────────────────

class _ExpiredVoucherBody extends ConsumerWidget {
  final OrderDetailModel detail;
  final List<OrderItemModel> dealItems;
  final String dealId;
  final VoidCallback onRefreshOrderDetail;

  const _ExpiredVoucherBody({
    required this.detail,
    required this.dealItems,
    required this.dealId,
    required this.onRefreshOrderDetail,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final first = dealItems.first;
    final dateFmt = DateFormat('MMM d, yyyy');
    final usageRules = first.usageRules;

    return Stack(
      children: [
        CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: true,
              title: const Text(
                'Voucher Detail',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              ),
              backgroundColor: Colors.white,
              foregroundColor: AppColors.textPrimary,
              elevation: 0.5,
            ),

            // Deal 摘要卡片
            SliverToBoxAdapter(
              child: _SimpleDealCard(dealItems: dealItems),
            ),

            // 状态 + 日期信息
            SliverToBoxAdapter(
              child: Container(
                margin: const EdgeInsets.only(top: 8),
                color: Colors.white,
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _StatusInfoRow(
                      label: 'Status',
                      value: 'Expired',
                      valueColor: AppColors.textHint,
                      isBadge: true,
                    ),
                    const Divider(height: 24, color: Color(0xFFF0F0F0)),
                    _StatusInfoRow(
                      label: 'Purchased',
                      value: dateFmt.format(detail.createdAt.toLocal()),
                    ),
                    if (first.couponExpiresAt != null) ...[
                      const SizedBox(height: 12),
                      _StatusInfoRow(
                        label: 'Expired On',
                        value: dateFmt.format(
                            first.couponExpiresAt!.toLocal()),
                        valueColor: AppColors.error,
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // Usage Notes
            if (usageRules.isNotEmpty)
              SliverToBoxAdapter(
                child: _UsageNotesSection(usageRules: usageRules),
              ),

            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),

        // 底部：Buy Again
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _VoucherBottomActionBar(
            detail: detail,
            dealId: dealId,
            onRefreshOrderDetail: onRefreshOrderDetail,
          ),
        ),
      ],
    );
  }
}

// ── Used 状态底部操作栏（Write Review + Buy Again） ─

class _UsedBottomBar extends StatelessWidget {
  final List<OrderItemModel> dealItems;
  final String dealId;

  const _UsedBottomBar({
    required this.dealItems,
    required this.dealId,
  });

  @override
  Widget build(BuildContext context) {
    final first = dealItems.first;
    final merchantId =
        first.purchasedMerchantId ?? first.redeemedMerchantId ?? '';

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFEEEEEE), width: 1)),
      ),
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        12 + MediaQuery.of(context).padding.bottom,
      ),
      child: Row(
        children: [
          // Write Review
          Expanded(
            child: OutlinedButton(
              onPressed: () => context.push(
                  '/review/${first.dealId}?merchantId=$merchantId&orderItemId=${first.id}'),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.accent),
                foregroundColor: AppColors.accent,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
              child: const Text(
                'Write Review',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Buy Again → 跳转到 deal 详情页重新购买
          Expanded(
            child: ElevatedButton(
              onPressed: () => context.push('/deals/$dealId'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                elevation: 0,
              ),
              child: const Text(
                'Buy Again',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

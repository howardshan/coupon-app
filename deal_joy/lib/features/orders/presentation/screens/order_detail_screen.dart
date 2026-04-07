// 订单详情页 — 美团风格重写
// 布局从上到下：状态横幅 → Deal摘要卡片 → 券状态展开行 → Order Info → 底部操作栏

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../cart/domain/providers/cart_provider.dart';
import '../../../deals/domain/providers/deals_provider.dart';
import '../../data/models/order_detail_model.dart';
import '../../data/models/order_item_model.dart';
import '../../domain/providers/orders_provider.dart';
import '../../domain/providers/coupons_provider.dart';
import '../widgets/gift_bottom_sheet.dart';

// ── 未使用券 QR 码弹窗 ────────────────────────────

void showUnusedQrSheet(BuildContext context, List<OrderItemModel> items) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _UnusedQrSheet(items: items),
  );
}

class _UnusedQrSheet extends StatefulWidget {
  final List<OrderItemModel> items;
  const _UnusedQrSheet({required this.items});
  @override
  State<_UnusedQrSheet> createState() => _UnusedQrSheetState();
}

class _UnusedQrSheetState extends State<_UnusedQrSheet> {
  late final PageController _pageController;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    final hasMultiple = items.length > 1;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 拖拽指示条
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: AppColors.textHint,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            hasMultiple
                ? 'Voucher ${_currentPage + 1} of ${items.length}'
                : 'Scan to Redeem',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),

          // QR 码区域（支持左右滑动多张券）
          SizedBox(
            height: 340,
            child: PageView.builder(
              controller: _pageController,
              itemCount: items.length,
              onPageChanged: (i) => setState(() => _currentPage = i),
              itemBuilder: (_, i) {
                final item = items[i];
                final qrData = item.couponQrCode ?? item.couponCode ?? '';
                final formattedCode = item.formattedCouponCode;

                return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // QR 码
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: qrData.isNotEmpty
                          ? QrImageView(
                              data: qrData,
                              version: QrVersions.auto,
                              size: 200,
                              backgroundColor: Colors.white,
                            )
                          : const SizedBox(
                              width: 200, height: 200,
                              child: Center(child: Text('QR code unavailable')),
                            ),
                    ),
                    const SizedBox(height: 16),

                    // 券码（可复制）
                    if (formattedCode != null)
                      GestureDetector(
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: formattedCode));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Coupon code copied'),
                              duration: Duration(seconds: 2),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceVariant,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                formattedCode,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 2,
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Icon(Icons.copy_rounded,
                                  size: 16, color: AppColors.textSecondary),
                            ],
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),

          // 多张券时显示分页指示器
          if (hasMultiple) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(items.length, (i) => Container(
                width: i == _currentPage ? 20 : 8,
                height: 8,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  color: i == _currentPage
                      ? AppColors.primary
                      : AppColors.textHint.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(4),
                ),
              )),
            ),
          ],

        ],
      ),
    );
  }
}



// ── 主屏幕 ────────────────────────────────────────

class OrderDetailScreen extends ConsumerWidget {
  final String orderId;

  const OrderDetailScreen({super.key, required this.orderId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(userOrderDetailProvider(orderId));

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: detailAsync.when(
        data: (detail) => _MeituanOrderBody(
          detail: detail,
          orderId: orderId,
        ),
        loading: () => const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => Scaffold(
          appBar: AppBar(title: const Text('Order Detail')),
          body: _ErrorBody(
            onRetry: () => ref.invalidate(userOrderDetailProvider(orderId)),
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
              'Failed to load order',
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

// ── 美团风格主体（带 ConsumerStatefulWidget 控制展开状态） ──

class _MeituanOrderBody extends ConsumerStatefulWidget {
  final OrderDetailModel detail;
  final String orderId;

  const _MeituanOrderBody({required this.detail, required this.orderId});

  @override
  ConsumerState<_MeituanOrderBody> createState() => _MeituanOrderBodyState();
}

class _MeituanOrderBodyState extends ConsumerState<_MeituanOrderBody> {
  // 每个 deal 分组的展开状态（key = dealId）
  final Map<String, bool> _expandedGroups = {};

  OrderDetailModel get detail => widget.detail;

  @override
  Widget build(BuildContext context) {
    // 按 deal_id 分组所有 items
    final groupMap = <String, List<OrderItemModel>>{};
    for (final item in detail.items) {
      groupMap.putIfAbsent(item.dealId, () => []).add(item);
    }

    return Stack(
      children: [
        // 主滚动区域
        CustomScrollView(
          slivers: [
            // 顶部 AppBar
            const SliverAppBar(
              pinned: true,
              title: Text(
                'Order Detail',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              ),
              backgroundColor: Colors.white,
              foregroundColor: AppColors.textPrimary,
              elevation: 0.5,
            ),

            // 每个 deal 分组：摘要卡片 + 券状态行
            ...groupMap.entries.map((entry) {
              final dealId = entry.key;
              final items = entry.value;
              final isExpanded = _expandedGroups[dealId] ?? false;

              return SliverToBoxAdapter(
                child: _DealSummaryCard(
                  dealItems: items,
                  isExpanded: isExpanded,
                  orderId: widget.orderId,
                  paymentIntentId: detail.paymentIntentIdMasked,
                  storeCreditUsed: detail.storeCreditUsed,
                  orderTotalAmount: detail.totalAmount,
                  onToggleExpand: () {
                    setState(() {
                      _expandedGroups[dealId] = !isExpanded;
                    });
                  },
                  onRefreshOrder: () =>
                      ref.invalidate(userOrderDetailProvider(widget.orderId)),
                ),
              );
            }),

            // Order Info 区块
            SliverToBoxAdapter(
              child: _OrderInfoSection(detail: detail),
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
          child: _BottomActionBar(
            detail: detail,
            orderId: widget.orderId,
          ),
        ),
      ],
    );
  }
}

// ── Deal 摘要卡片（含券状态展开行） ───────────────

class _DealSummaryCard extends ConsumerWidget {
  final List<OrderItemModel> dealItems;
  final bool isExpanded;
  final VoidCallback onToggleExpand;
  final VoidCallback onRefreshOrder;
  final String? paymentIntentId;
  final String orderId;
  /// 本单使用的 Store Credit 金额
  final double storeCreditUsed;
  /// 订单原始总金额（未扣 Store Credit）
  final double orderTotalAmount;

  const _DealSummaryCard({
    required this.dealItems,
    required this.isExpanded,
    required this.onToggleExpand,
    required this.onRefreshOrder,
    required this.orderId,
    this.paymentIntentId,
    this.storeCreditUsed = 0.0,
    this.orderTotalAmount = 0.0,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final first = dealItems.first;
    final count = dealItems.length;
    final amountFmt = NumberFormat.currency(symbol: '\$', decimalDigits: 2);

    // 计算已付总价（不含 service fee）
    final totalPaid = dealItems.fold<double>(0, (s, i) => s + i.unitPrice);
    final merchantName = first.merchantName ?? first.purchasedMerchantName;

    // 按状态分组（用于显示 "Unused (2)" 等）
    final unusedItems =
        dealItems.where((i) => i.customerStatus == CustomerItemStatus.unused).toList();
    final usedItems =
        dealItems.where((i) => i.customerStatus == CustomerItemStatus.used).toList();
    final giftedItems =
        dealItems.where((i) => i.customerStatus == CustomerItemStatus.gifted).toList();
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
            i.customerStatus != CustomerItemStatus.gifted &&
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
                          errorBuilder: (context, error, _) => _PlaceholderImage(),
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
                            '${amountFmt.format(first.unitPrice)} × $count',
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

          // 券状态汇总行（美团风格）
          if (unusedItems.isNotEmpty)
            _CouponStatusRow(
              label: 'Unused',
              count: unusedItems.length,
              color: const Color(0xFF00C853),
              items: unusedItems,
              isExpanded: false,
              onToggle: () => showUnusedQrSheet(context, unusedItems),
              onRefreshOrder: onRefreshOrder,
              orderId: orderId,
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
              orderId: orderId,
              paymentIntentId: paymentIntentId,
              storeCreditUsed: storeCreditUsed,
              orderTotalAmount: orderTotalAmount,
            ),
          if (giftedItems.isNotEmpty)
            _CouponStatusRow(
              label: 'Gifted',
              count: giftedItems.length,
              color: AppColors.secondary,
              items: giftedItems,
              isExpanded: isExpanded && unusedItems.isEmpty && usedItems.isEmpty,
              onToggle: unusedItems.isEmpty && usedItems.isEmpty ? onToggleExpand : null,
              onRefreshOrder: onRefreshOrder,
              orderId: orderId,
              paymentIntentId: paymentIntentId,
              storeCreditUsed: storeCreditUsed,
              orderTotalAmount: orderTotalAmount,
            ),
          if (refundedItems.isNotEmpty)
            _CouponStatusRow(
              label: (refundedItems.first.customerStatus == CustomerItemStatus.refundPending ||
                      refundedItems.first.customerStatus == CustomerItemStatus.refundProcessing ||
                      refundedItems.first.customerStatus == CustomerItemStatus.refundReview)
                  ? 'Refund Processing'
                  : 'Refunded',
              count: refundedItems.length,
              color: const Color(0xFF9E9E9E),
              items: refundedItems,
              isExpanded: false,
              onToggle: null,
              onRefreshOrder: onRefreshOrder,
              orderId: orderId,
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
              orderId: orderId,
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
  final String orderId;
  final String? paymentIntentId;
  /// 本单使用的 Store Credit 金额
  final double storeCreditUsed;
  /// 订单原始总金额（未扣 Store Credit）
  final double orderTotalAmount;

  const _CouponStatusRow({
    required this.label,
    required this.count,
    required this.color,
    required this.items,
    required this.isExpanded,
    required this.onToggle,
    required this.onRefreshOrder,
    required this.orderId,
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
                orderId: orderId,
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
  final String orderId;
  final String? paymentIntentId;
  final VoidCallback onRefreshOrder;
  /// 本单使用的 Store Credit 金额
  final double storeCreditUsed;
  /// 订单原始总金额（未扣 Store Credit）
  final double orderTotalAmount;

  const _CouponDetailRow({
    required this.item,
    required this.allItems,
    required this.orderId,
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
        // 赠送出去的券跳转到 coupon 详情页（显示 gift 信息）
        if (item.customerStatus == CustomerItemStatus.gifted && item.couponId != null) {
          context.push('/coupon/${item.couponId}');
        } else {
          // 其他状态跳转到 voucher detail 页面
          context.push('/voucher/$orderId?dealId=${item.dealId}');
        }
      },
      child: Container(
        color: const Color(0xFFFAFAFA),
        padding: const EdgeInsets.fromLTRB(24, 12, 16, 12),
        child: Row(
          children: [
            // 券码（可点击跳转 voucher detail）
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
                  if (item.redeemedAt != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Used ${DateFormat('MMM d, yyyy').format(item.redeemedAt!.toLocal())}',
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textHint),
                    ),
                  ],
                  // 赠送信息（gifted 状态时显示受赠方）
                  if (item.customerStatus == CustomerItemStatus.gifted &&
                      item.activeGift != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Gifted to ${item.activeGift!.recipientDisplay}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.secondary,
                        fontWeight: FontWeight.w500,
                      ),
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
                // 赠送按钮（未使用且未赠出）
                if (item.showGift)
                  _SmallButton(
                    label: 'Gift',
                    color: AppColors.secondary,
                    onTap: () => GiftBottomSheet.show(
                      context,
                      dealTitle: item.dealTitle,
                      merchantName: item.merchantName,
                      expiresAt: item.couponExpiresAt,
                      orderItemId: item.id,
                      onGiftSent: onRefreshOrder,
                    ),
                  ),
                // 撤回赠送按钮（已赠出 + pending）
                if (item.showRecallGift)
                  _SmallButton(
                    label: 'Recall',
                    color: AppColors.warning,
                    onTap: () => _showRecallConfirm(context, ref, item),
                  ),
                // 修改受赠方按钮（已赠出 + pending）
                if (item.showEditRecipient)
                  _SmallButton(
                    label: 'Edit',
                    color: AppColors.info,
                    onTap: () => GiftBottomSheet.show(
                      context,
                      dealTitle: item.dealTitle,
                      merchantName: item.merchantName,
                      expiresAt: item.couponExpiresAt,
                      orderItemId: item.id,
                      prefillEmail: item.activeGift?.recipientEmail,
                      prefillPhone: item.activeGift?.recipientPhone,
                      onGiftSent: onRefreshOrder,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // 撤回赠送确认弹窗
  void _showRecallConfirm(
      BuildContext context, WidgetRef ref, OrderItemModel item) {
    final gift = item.activeGift;
    if (gift == null) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Recall this gift?'),
        content: Text(
          'The coupon will be returned to your account.\n'
          '${gift.recipientDisplay} will no longer be able to use it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.warning,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.of(ctx).pop();
              final success = await ref
                  .read(giftNotifierProvider.notifier)
                  .recallGift(gift.id);
              if (context.mounted) {
                if (success) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Gift recalled successfully')),
                  );
                  onRefreshOrder();
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Failed to recall gift'),
                      backgroundColor: AppColors.error,
                    ),
                  );
                }
              }
            },
            child: const Text('Confirm Recall'),
          ),
        ],
      ),
    );
  }

  // 展示取消/退款 Bottom Sheet
  void _showCancelSheet(
      BuildContext context, WidgetRef ref, OrderItemModel item) {
    // 找同 deal 的所有 unused items（同 order 同 deal 可选数量退）
    final sameDealUnused = allItems
        .where((i) => i.dealId == item.dealId && i.customerStatus == CustomerItemStatus.unused)
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
        onConfirm: (refundMethod, {int cancelCount = 1, List<String>? selectedItemIds}) async {
          final navigator = Navigator.of(context);
          final messenger = ScaffoldMessenger.of(context);
          // 已核销券：只退当前这一条，且仅 Store Credit（与 create-refund 一致）
          final String method =
              item.showRefundRequest ? 'store_credit' : refundMethod;
          final List<OrderItemModel> itemsToCancel;
          if (item.showRefundRequest) {
            itemsToCancel = [item];
          } else if (selectedItemIds != null && selectedItemIds.isNotEmpty) {
            final idSet = selectedItemIds.toSet();
            itemsToCancel = sameDealUnused.where((i) => idSet.contains(i.id)).toList();
          } else {
            itemsToCancel = sameDealUnused.take(cancelCount).toList();
          }
          int successCount = 0;
          for (final cancelItem in itemsToCancel) {
            final ok = await ref
                .read(refundNotifierProvider.notifier)
                .requestItemRefund(
                  cancelItem.id,
                  refundMethod: method,
                );
            if (ok) successCount++;
          }
          navigator.pop();
          if (successCount > 0) {
            final String msg = item.showRefundRequest
                ? (successCount > 1
                    ? '$successCount vouchers refunded to Store Credit'
                    : 'Refunded to Store Credit successfully')
                : '$successCount voucher${successCount > 1 ? 's' : ''} cancelled successfully';
            messenger.showSnackBar(
              SnackBar(
                content: Text(msg),
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


// ── Order Info 区块 ───────────────────────────────

class _OrderInfoSection extends StatelessWidget {
  final OrderDetailModel detail;

  const _OrderInfoSection({required this.detail});

  @override
  Widget build(BuildContext context) {
    final amountFmt = NumberFormat.currency(symbol: '\$', decimalDigits: 2);

    // 计算 service fee 总额
    final totalServiceFee =
        detail.items.fold<double>(0, (s, i) => s + i.serviceFee);

    return Container(
      margin: const EdgeInsets.only(top: 8),
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Order Info',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),

          // 订单号（可复制）
          _InfoRowCopy(
            label: 'Order Number',
            value: detail.orderNumber,
            canCopy: true,
          ),

          // 下单时间
          _InfoRowCopy(
            label: 'Ordered',
            value: DateFormat('MMM d, yyyy · h:mm a')
                .format(detail.createdAt.toLocal()),
            canCopy: false,
          ),

          // 支付方式
          _InfoRowCopy(
            label: 'Payment',
            value: _resolvePaymentMethod(detail),
            canCopy: false,
          ),

          const Divider(height: 20, color: Color(0xFFF0F0F0)),

          // ── 费用明细 ──────────────────────────────────────
          const Text('Price Breakdown',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
          const SizedBox(height: 8),

          // 每个 deal 的价格
          ...detail.items.fold<Map<String, _DealPriceSummary>>({}, (map, item) {
            final title = item.dealTitle.isNotEmpty ? item.dealTitle : 'Deal';
            map.putIfAbsent(title, () => _DealPriceSummary(title: title, unitPrice: item.unitPrice));
            map[title]!.count++;
            return map;
          }).values.map((d) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: Text(
                  '${d.title} × ${d.count}',
                  style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                )),
                Text(amountFmt.format(d.unitPrice * d.count),
                    style: const TextStyle(fontSize: 13)),
              ],
            ),
          )),

          // Service Fee
          if (totalServiceFee > 0)
            _SimpleRow('Service Fee (\$0.99 × ${detail.items.length})',
                amountFmt.format(totalServiceFee)),

          // Tax（从 items 的 taxAmount 汇总，或从 detail 读取）
          // 如果 detail 有 tax 相关字段可以展示

          const Divider(height: 16, color: Color(0xFFF0F0F0)),

          // Total
          _SimpleRow('Total', amountFmt.format(detail.totalAmount),
              isBold: true, valueColor: AppColors.textPrimary),

          const SizedBox(height: 8),

          // ── 支付方式明细 ────────────────────────────────────
          const Text('Payment',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
          const SizedBox(height: 8),

          // Store Credit 支付
          if (detail.storeCreditUsed > 0)
            _SimpleRow('Store Credit', amountFmt.format(detail.storeCreditUsed),
                valueColor: AppColors.success),

          // Card / Google Pay 支付（总额减去 Store Credit）
          if (detail.totalAmount - detail.storeCreditUsed > 0)
            _SimpleRow(
              _resolvePaymentMethod(detail),
              amountFmt.format(detail.totalAmount - detail.storeCreditUsed),
            ),

          // 全额 Store Credit 时
          if (detail.totalAmount - detail.storeCreditUsed <= 0 && detail.storeCreditUsed > 0)
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Text('Fully paid by Store Credit',
                  style: TextStyle(fontSize: 12, color: AppColors.success, fontStyle: FontStyle.italic)),
            ),

          // ── 退款信息 ──────────────────────────────────────
          ...(() {
            final refundedItems = detail.items
                .where((i) => i.customerStatus == CustomerItemStatus.refundSuccess ||
                    i.customerStatus == CustomerItemStatus.refundPending ||
                    i.customerStatus == CustomerItemStatus.refundProcessing)
                .toList();
            if (refundedItems.isEmpty) return <Widget>[];

            final totalRefund = refundedItems.fold<double>(0, (s, i) => s + (i.refundAmount ?? i.unitPrice));
            final storeCreditRefunds = refundedItems
                .where((i) =>
                    i.refundMethod == 'store_credit' &&
                    i.customerStatus == CustomerItemStatus.refundSuccess)
                .toList();
            final originalRefunds = refundedItems
                .where((i) =>
                    i.refundMethod == 'original_payment' &&
                    i.customerStatus == CustomerItemStatus.refundSuccess)
                .toList();
            final pendingRefunds = refundedItems
                .where((i) =>
                    i.customerStatus == CustomerItemStatus.refundPending ||
                    i.customerStatus == CustomerItemStatus.refundProcessing)
                .toList();

            return <Widget>[
              const Divider(height: 20, color: Color(0xFFF0F0F0)),
              const Text('Refunds',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
              const SizedBox(height: 8),

              if (storeCreditRefunds.isNotEmpty)
                _SimpleRow(
                  'To Store Credit (${storeCreditRefunds.length} voucher${storeCreditRefunds.length > 1 ? "s" : ""})',
                  amountFmt.format(storeCreditRefunds.fold<double>(0, (s, i) => s + (i.refundAmount ?? i.unitPrice))),
                  valueColor: AppColors.success,
                ),

              if (originalRefunds.isNotEmpty)
                _SimpleRow(
                  'To Original Payment (${originalRefunds.length})',
                  amountFmt.format(originalRefunds.fold<double>(0, (s, i) => s + (i.refundAmount ?? i.unitPrice))),
                ),

              if (pendingRefunds.isNotEmpty)
                _SimpleRow(
                  'Refund Processing (${pendingRefunds.length})',
                  amountFmt.format(pendingRefunds.fold<double>(0, (s, i) => s + (i.refundAmount ?? i.unitPrice))),
                  valueColor: AppColors.warning,
                ),

              _SimpleRow('Total Refunded', amountFmt.format(totalRefund),
                  isBold: true, valueColor: AppColors.error),
            ];
          })(),
        ],
      ),
    );
  }

  bool _isPaidByStoreCredit(OrderDetailModel detail) {
    // 全额 Store Credit：store_credit_used >= total_amount
    return detail.storeCreditUsed > 0 &&
        detail.storeCreditUsed >= detail.totalAmount;
  }

  String _resolvePaymentMethod(OrderDetailModel detail) {
    if (_isPaidByStoreCredit(detail)) return 'Store Credit';
    final status = detail.paymentStatus ?? '';
    return switch (status.toLowerCase()) {
      'succeeded' => 'Credit Card',
      'paid' => 'Credit Card',
      _ => status.isNotEmpty
          ? status[0].toUpperCase() + status.substring(1)
          : 'Credit Card',
    };
  }
}

// ── 信息行（带可选复制） ──────────────────────────

class _InfoRowCopy extends StatelessWidget {
  final String label;
  final String value;
  final bool canCopy;
  final TextStyle? valueStyle;

  const _InfoRowCopy({
    required this.label,
    required this.value,
    required this.canCopy,
    this.valueStyle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: valueStyle ?? const TextStyle(
                fontSize: 13,
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (canCopy)
            GestureDetector(
              onTap: () {
                Clipboard.setData(ClipboardData(text: value));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Copied to clipboard'),
                    duration: Duration(seconds: 2),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
              child: const Padding(
                padding: EdgeInsets.only(left: 8),
                child: Icon(
                  Icons.copy_rounded,
                  size: 15,
                  color: AppColors.textHint,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── 价格行 ────────────────────────────────────────

class _PriceRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isTotal;

  const _PriceRow({
    required this.label,
    required this.value,
    required this.isTotal,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: isTotal ? 14 : 13,
              fontWeight: isTotal ? FontWeight.w700 : FontWeight.w400,
              color: isTotal ? AppColors.textPrimary : AppColors.textSecondary,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              fontSize: isTotal ? 16 : 13,
              fontWeight: isTotal ? FontWeight.w800 : FontWeight.w500,
              color: isTotal ? AppColors.primary : AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

// ── 底部固定操作栏 ────────────────────────────────

class _BottomActionBar extends ConsumerWidget {
  final OrderDetailModel detail;
  final String orderId;

  const _BottomActionBar({required this.detail, required this.orderId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 找到所有可取消的 item
    final cancelableItems =
        detail.items.where((i) => i.showCancel).toList();
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
                    context, ref, cancelableItems.first),
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

  // ── Buy Again：将订单券重新加入购物车并跳转结账 ─────────────
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

      // 按 dealId 分组订单项
      final itemsByDeal = <String, List<OrderItemModel>>{};
      for (final item in detail.items) {
        itemsByDeal.putIfAbsent(item.dealId, () => []).add(item);
      }

      final unavailableDeals = <String>[]; // 不可购买的 deal 标题
      final itemsToAdd = <OrderItemBuyAgainData>[]; // 要加入购物车的数据

      for (final entry in itemsByDeal.entries) {
        final dealId = entry.key;
        final orderItems = entry.value;

        try {
          final deal = await dealsRepo.fetchDealById(dealId);

          // 检查是否已过期
          if (deal.isExpired) {
            unavailableDeals.add(deal.title);
            continue;
          }

          // 检查限购：查询用户已购买该 deal 的数量（未退款的）
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

              // 也算上购物车中已有的
              final cartItems = ref.read(cartProvider).valueOrNull ?? [];
              final cartCount =
                  cartItems.where((c) => c.dealId == dealId).length;

              final remaining =
                  deal.maxPerAccount - purchasedCount - cartCount;
              if (remaining <= 0) {
                unavailableDeals.add(
                    '${deal.title} (purchase limit reached)');
                continue;
              }
              allowCount = remaining < orderItems.length
                  ? remaining
                  : orderItems.length;
            }
          }

          // 收集要加入购物车的数据
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

          // 如果因限购只能加入部分
          if (allowCount < orderItems.length) {
            final skipped = orderItems.length - allowCount;
            unavailableDeals.add(
                '${deal.title} ($skipped coupon(s) skipped due to purchase limit)');
          }
        } catch (_) {
          // deal 不存在或查询失败
          unavailableDeals.add(orderItems.first.dealTitle);
        }
      }

      // 关闭 loading
      navigator.pop();

      // 没有可加入的券
      if (itemsToAdd.isEmpty) {
        messenger.showSnackBar(const SnackBar(
          content: Text(
              'None of the deals in this order are available for purchase.'),
        ));
        return;
      }

      // 批量加入购物车
      final addedItems = await cartNotifier.addBulkFromOrderItems(itemsToAdd);

      // 显示不可购买的提示
      if (unavailableDeals.isNotEmpty) {
        messenger.showSnackBar(SnackBar(
          content: Text(
            'Some items are unavailable: ${unavailableDeals.join("; ")}',
          ),
          duration: const Duration(seconds: 4),
        ));
      }

      // 跳转到结账页，传入刚添加的购物车项
      if (addedItems.isNotEmpty) {
        router.push('/checkout-cart', extra: addedItems);
      }
    } catch (e) {
      navigator.pop();
      messenger.showSnackBar(SnackBar(
        content: Text('Failed to re-order: $e'),
      ));
    }
  }

  // 显示取消 Bottom Sheet（第一张 unused 券）
  void _showBatchCancelSheet(
      BuildContext context, WidgetRef ref, OrderItemModel item) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) {
        // 所有 unused 的券
        final allUnused = detail.items
            .where((i) => i.showCancel)
            .toList();
        return _CancelSheet(
          item: item,
          totalUnusedCount: allUnused.length,
          allUnusedItems: allUnused,
          paymentIntentId: detail.paymentIntentIdMasked,
          storeCreditUsed: detail.storeCreditUsed,
          orderTotalAmount: detail.totalAmount,
          onConfirm: (refundMethod, {int cancelCount = 1, List<String>? selectedItemIds}) async {
            final navigator = Navigator.of(context);
            final messenger = ScaffoldMessenger.of(context);
            // 优先用用户选中的券 id，否则降级为取前 N 张
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
                  content: Text('$successCount voucher${successCount > 1 ? 's' : ''} cancelled'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
              ref.invalidate(userOrderDetailProvider(orderId));
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
        );
      },
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
  final String? paymentIntentId; // 用于判断是否全额 Store Credit 支付
  final double storeCreditUsed;  // 本单使用的 Store Credit 金额
  final double orderTotalAmount; // 订单原始总金额（未扣 Store Credit）
  /// selectedItemIds: 用户选中的具体券 id 列表（多券选择模式）
  final Future<void> Function(String refundMethod, {int cancelCount, List<String>? selectedItemIds}) onConfirm;

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
  // 券选择：记录被选中的 item id
  late Set<String> _selectedIds;

  // 是否全额 Store Credit 支付
  bool get _isPaidByStoreCredit {
    // 优先用 storeCreditUsed 判断（piId 可能被 mask 后丢失 store_credit 前缀）
    if (widget.storeCreditUsed > 0 && widget.orderTotalAmount > 0 &&
        widget.storeCreditUsed >= widget.orderTotalAmount) {
      return true;
    }
    final piId = widget.paymentIntentId ?? '';
    return piId.contains('store_credit');
  }

  // 是否混合支付（部分 Store Credit + 部分刷卡）
  bool get _isPartialStoreCredit =>
      !_isPaidByStoreCredit && widget.storeCreditUsed > 0;

  @override
  void initState() {
    super.initState();
    _cancelCount = 1;
    // 初始化：默认全选所有 unused 券
    _selectedIds = widget.allUnusedItems.map((i) => i.id).toSet();
    // 全额 Store Credit 支付时锁定退款方式
    if (_isPaidByStoreCredit) {
      _selectedMethod = 'store_credit';
    }
  }

  /// 根据支付方式构建退款选项列表
  List<Widget> _buildRefundOptions(bool isCancel) {
    if (_isPaidByStoreCredit) {
      // 全额 Store Credit 支付：只能退回 Store Credit
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

    // 已核销券仅可退回 Store Credit（create-refund 拒绝 original_payment）
    if (!isCancel) {
      return [
        _RefundMethodOption(
          selected: true,
          title: 'Store Credit',
          subtitle: 'Used vouchers refund to Store Credit only · Incl. service fee · Instant',
          badge: 'Only Option',
          badgeColor: AppColors.success,
          onTap: () {},
        ),
      ];
    }

    // 混合支付时的 Original Payment 说明文案
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
                : 'You used this voucher. Refunds are credited to Store Credit only.',
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
          // 多张券时显示券选择列表（复选框）
          if (totalUnused > 1) ...[
            const SizedBox(height: 16),
            // 全选/取消全选
            GestureDetector(
              onTap: () {
                setState(() {
                  if (_selectedIds.length == widget.allUnusedItems.length) {
                    // 至少保留一张
                    _selectedIds = {widget.allUnusedItems.first.id};
                  } else {
                    _selectedIds = widget.allUnusedItems.map((i) => i.id).toSet();
                  }
                  _cancelCount = _selectedIds.length;
                });
              },
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Text(
                      'Select vouchers to cancel',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                    ),
                    const Spacer(),
                    Text(
                      _selectedIds.length == widget.allUnusedItems.length
                          ? 'Deselect All'
                          : 'Select All',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // 券列表
            Container(
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(10),
              ),
              constraints: const BoxConstraints(maxHeight: 200),
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: widget.allUnusedItems.length,
                separatorBuilder: (_, __) => const Divider(height: 1, indent: 48),
                itemBuilder: (_, index) {
                  final coupon = widget.allUnusedItems[index];
                  final isSelected = _selectedIds.contains(coupon.id);
                  return InkWell(
                    onTap: () {
                      setState(() {
                        if (isSelected && _selectedIds.length > 1) {
                          _selectedIds.remove(coupon.id);
                        } else if (!isSelected) {
                          _selectedIds.add(coupon.id);
                        }
                        _cancelCount = _selectedIds.length;
                      });
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      child: Row(
                        children: [
                          Icon(
                            isSelected
                                ? Icons.check_circle_rounded
                                : Icons.radio_button_unchecked_rounded,
                            color: isSelected ? AppColors.primary : AppColors.textHint,
                            size: 22,
                          ),
                          const SizedBox(width: 10),
                          // Deal 图片
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: coupon.dealImageUrl != null && coupon.dealImageUrl!.isNotEmpty
                                ? CachedNetworkImage(
                                    imageUrl: coupon.dealImageUrl!,
                                    width: 40,
                                    height: 40,
                                    fit: BoxFit.cover,
                                    placeholder: (_, __) => Container(
                                      width: 40,
                                      height: 40,
                                      color: Colors.grey.shade200,
                                      child: Icon(Icons.local_offer_outlined,
                                          size: 18, color: Colors.grey.shade400),
                                    ),
                                    errorWidget: (_, __, ___) => Container(
                                      width: 40,
                                      height: 40,
                                      color: Colors.grey.shade200,
                                      child: Icon(Icons.local_offer_outlined,
                                          size: 18, color: Colors.grey.shade400),
                                    ),
                                  )
                                : Container(
                                    width: 40,
                                    height: 40,
                                    color: Colors.grey.shade200,
                                    child: Icon(Icons.local_offer_outlined,
                                        size: 18, color: Colors.grey.shade400),
                                  ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  coupon.dealTitle.isNotEmpty
                                      ? coupon.dealTitle
                                      : 'Voucher ${index + 1}',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  coupon.formattedCouponCode ?? '',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontFamily: 'monospace',
                                    color: AppColors.textSecondary,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            '\$${coupon.unitPrice.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            // 已选数量提示
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '${_selectedIds.length} of $totalUnused selected',
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ),
          ],
          const SizedBox(height: 20),

          // 判断是否全额 Store Credit 支付（payment_intent_id 含 store_credit）
          ..._buildRefundOptions(isCancel),
          const SizedBox(height: 24),

          // 确认按钮（全额 Store Credit 时自动锁定为 store_credit）
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
                    if (mounted) {
                      setState(() => _isSubmitting = false);
                    }
                  },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: _isSubmitting
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : const Text(
                    'Confirm',
                    style: TextStyle(
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
          color: selected
              ? AppColors.primary.withValues(alpha: 0.06)
              : AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? AppColors.primary
                : AppColors.textHint.withValues(alpha: 0.3),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            // 单选圆圈
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? AppColors.primary : AppColors.textHint,
                  width: 2,
                ),
              ),
              child: selected
                  ? Center(
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.primary,
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            // 文案
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
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
                              fontWeight: FontWeight.w700,
                              color: badgeColor ?? AppColors.success,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
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

// ── Deal 价格汇总辅助类 ────────────────────────────────────
class _DealPriceSummary {
  final String title;
  final double unitPrice;
  int count = 0;

  _DealPriceSummary({required this.title, required this.unitPrice});
}

// ── 简单行（label + value）────────────────────────────────────
class _SimpleRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isBold;
  final Color? valueColor;

  const _SimpleRow(this.label, this.value, {this.isBold = false, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(label,
              style: TextStyle(
                fontSize: isBold ? 14 : 13,
                fontWeight: isBold ? FontWeight.w700 : FontWeight.normal,
                color: isBold ? AppColors.textPrimary : AppColors.textSecondary,
              ),
            ),
          ),
          Text(value,
            style: TextStyle(
              fontSize: isBold ? 15 : 13,
              fontWeight: isBold ? FontWeight.w700 : FontWeight.w500,
              color: valueColor ?? AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

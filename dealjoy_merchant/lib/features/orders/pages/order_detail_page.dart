// 订单详情页面
// 展示完整订单信息：用户信息 / Deal信息 / 支付信息 / 券码 / 时间线
// 退款订单展示 "Automatically refunded by DealJoy" 说明

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/merchant_order.dart';
import '../providers/orders_provider.dart';
import '../widgets/order_status_badge.dart';
import '../widgets/timeline_widget.dart';

/// 订单详情页
class OrderDetailPage extends ConsumerWidget {
  const OrderDetailPage({super.key, required this.orderId});

  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(orderDetailProvider(orderId));

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, size: 20),
          onPressed: () => Navigator.of(context).pop(),
          color: const Color(0xFF1A1A1A),
        ),
        title: const Text(
          'Order Detail',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: Color(0xFF1A1A1A),
          ),
        ),
        centerTitle: true,
        actions: [
          // 刷新按钮
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 20),
            color: Colors.grey.shade600,
            onPressed: () =>
                ref.read(orderDetailProvider(orderId).notifier).refresh(),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: detailAsync.when(
        data: (detail) => _buildDetail(context, detail),
        loading: () => const Center(
          child: CircularProgressIndicator(color: Color(0xFFFF6B35)),
        ),
        error: (e, _) => _buildError(context, e, ref),
      ),
    );
  }

  // =============================================================
  // 主体内容
  // =============================================================
  Widget _buildDetail(BuildContext context, MerchantOrderDetail detail) {
    final amountFmt = NumberFormat.currency(symbol: '\$');

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 顶部：订单号 + 状态 Badge
          _buildHeader(detail),
          const SizedBox(height: 12),

          // 自动退款说明横幅（仅退款订单显示）
          if (detail.status == OrderStatus.refunded)
            _buildRefundBanner(detail),

          // 区块1：用户信息
          _SectionCard(
            title: 'Customer',
            icon: Icons.person_outline_rounded,
            children: [
              _InfoRow(
                label: 'Name',
                value: detail.userName,
              ),
            ],
          ),

          // 区块2：Deal 信息
          _SectionCard(
            title: 'Deal',
            icon: Icons.local_offer_outlined,
            children: [
              _InfoRow(label: 'Title', value: detail.dealTitle),
              _InfoRow(
                label: 'Original Price',
                value: amountFmt.format(detail.dealOriginalPrice),
              ),
              _InfoRow(
                label: 'Deal Price',
                value: amountFmt.format(detail.dealDiscountPrice),
                valueColor: const Color(0xFFFF6B35),
              ),
              _InfoRow(
                label: 'Quantity',
                value: '× ${detail.quantity}',
              ),
            ],
          ),

          // 区块3：支付信息
          _SectionCard(
            title: 'Payment',
            icon: Icons.credit_card_outlined,
            children: [
              _InfoRow(
                label: 'Subtotal',
                value: amountFmt.format(detail.itemsAmount > 0
                    ? detail.itemsAmount
                    : detail.totalAmount - detail.serviceFeeTotal),
              ),
              if (detail.serviceFeeTotal > 0)
                _InfoRow(
                  label: 'Service Fee',
                  value: amountFmt.format(detail.serviceFeeTotal),
                ),
              _InfoRow(
                label: 'Total',
                value: amountFmt.format(detail.totalAmount),
                valueBold: true,
              ),
              if (detail.paymentIntentIdMasked != null)
                _InfoRow(
                  label: 'Transaction ID',
                  value: detail.paymentIntentIdMasked!,
                  monospace: true,
                ),
              if (detail.paymentStatus != null)
                _InfoRow(
                  label: 'Payment Status',
                  value: _capitalise(detail.paymentStatus!),
                ),
              if (detail.refundAmount != null)
                _InfoRow(
                  label: 'Refunded Amount',
                  value: amountFmt.format(detail.refundAmount!),
                  valueColor: const Color(0xFFF59E0B),
                ),
            ],
          ),

          // 区块4：券码（已核销或已退款时显示）
          if (detail.couponCode != null)
            _SectionCard(
              title: 'Voucher',
              icon: Icons.qr_code_2_rounded,
              children: [
                _CouponCodeRow(code: detail.couponCode!),
                if (detail.couponExpiresAt != null)
                  _InfoRow(
                    label: 'Expires',
                    value: DateFormat('MMM d, yyyy')
                        .format(detail.couponExpiresAt!.toLocal()),
                  ),
                if (detail.couponStatus != null)
                  _InfoRow(
                    label: 'Coupon Status',
                    value: _capitalise(detail.couponStatus!),
                  ),
              ],
            ),

          // 区块5：退款原因（如有）
          if (detail.status == OrderStatus.refunded &&
              detail.refundReason != null &&
              detail.refundReason!.isNotEmpty)
            _SectionCard(
              title: 'Refund Reason',
              icon: Icons.info_outline_rounded,
              iconColor: const Color(0xFFF59E0B),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    detail.refundReason!,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF92400E),
                    ),
                  ),
                ),
              ],
            ),

          // 区块6：时间线
          _SectionCard(
            title: 'Timeline',
            icon: Icons.timeline_rounded,
            children: [
              OrderTimelineWidget(timeline: detail.timeline),
            ],
          ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // 顶部订单号 + 状态区域
  Widget _buildHeader(MerchantOrderDetail detail) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            detail.orderNumber,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1A1A1A),
              fontFamily: 'monospace',
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: detail.detailStatusTags
                    .map((s) => OrderStatusBadge(status: s, fontSize: 13))
                    .toList(),
              ),
              const Spacer(),
              Text(
                DateFormat('MMM d, yyyy · h:mm a')
                    .format(detail.createdAt.toLocal()),
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade500,
                ),
              ),
            ],
          ),
          if ((detail.detailStatusTags.contains(OrderStatus.expired) ||
                  detail.detailStatusTags.contains(OrderStatus.pendingRefund)) &&
              detail.status == OrderStatus.paid)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                detail.detailStatusTags.contains(OrderStatus.expired)
                    ? 'Coupon expired; will be auto-refunded 24h after expiry.'
                    : 'Auto-refund in progress (runs hourly).',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // 退款横幅
  Widget _buildRefundBanner(MerchantOrderDetail detail) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFF59E0B).withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.currency_exchange_rounded,
            size: 18,
            color: Color(0xFFF59E0B),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Automatically refunded by DealJoy',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF92400E),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail.refundedAt != null
                      ? 'Refunded on ${DateFormat('MMM d, yyyy').format(detail.refundedAt!.toLocal())}. No action required from you.'
                      : 'This order was automatically refunded. No action required from you.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.brown.shade600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 错误状态
  Widget _buildError(BuildContext context, Object error, WidgetRef ref) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded,
                size: 56, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            const Text(
              'Failed to load order',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Color(0xFF374151),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () =>
                  ref.read(orderDetailProvider(orderId).notifier).refresh(),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6B35),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
                elevation: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _capitalise(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

// =============================================================
// 区块卡片容器
// =============================================================
class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.children,
    this.iconColor = const Color(0xFFFF6B35),
  });

  final String title;
  final IconData icon;
  final List<Widget> children;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 区块标题
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                Icon(icon, size: 16, color: iconColor),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF6B7280),
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
          Divider(color: Colors.grey.shade100, height: 1),
          // 内容区
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================
// 信息行（label + value）
// =============================================================
class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    this.valueColor,
    this.valueBold = false,
    this.monospace = false,
  });

  final String label;
  final String value;
  final Color? valueColor;
  final bool valueBold;
  final bool monospace;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight:
                    valueBold ? FontWeight.w700 : FontWeight.w500,
                color: valueColor ?? const Color(0xFF1A1A1A),
                fontFamily: monospace ? 'monospace' : null,
                letterSpacing: monospace ? 0.5 : null,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================
// 券码行（带复制按钮）
// =============================================================
class _CouponCodeRow extends StatelessWidget {
  const _CouponCodeRow({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                code,
                style: const TextStyle(
                  fontSize: 14,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1A1A1A),
                  letterSpacing: 1,
                ),
              ),
            ),
            GestureDetector(
              onTap: () {
                Clipboard.setData(ClipboardData(text: code));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Coupon code copied'),
                    duration: Duration(seconds: 2),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
              child: Icon(
                Icons.copy_rounded,
                size: 16,
                color: Colors.grey.shade500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

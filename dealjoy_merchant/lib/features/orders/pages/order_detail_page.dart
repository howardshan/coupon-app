// 订单详情页面
// V4: 展示 order 级别信息 + 属于当前商家的 items 列表
// 每张券显示状态、coupon code（已 redeem 时）、金额

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
          // 顶部：订单号 + 主状态 + 时间
          _buildHeader(detail),
          const SizedBox(height: 12),

          // 区块1：客户信息
          _SectionCard(
            title: 'Customer',
            icon: Icons.person_outline_rounded,
            children: [
              _InfoRow(label: 'Name', value: detail.userName),
              if (detail.customerEmail != null &&
                  detail.customerEmail!.isNotEmpty)
                _InfoRow(label: 'Email', value: detail.customerEmail!),
            ],
          ),

          // 区块2：Vouchers 列表（每张券一个卡片）
          _buildVouchersSection(detail, amountFmt),

          // 区块3：Payment 汇总（商家专属金额）
          _SectionCard(
            title: 'Payment Summary',
            icon: Icons.credit_card_outlined,
            children: [
              _InfoRow(
                label: 'Items Amount',
                value: amountFmt.format(detail.itemsAmount),
              ),
              if (detail.serviceFeeTotal > 0)
                _InfoRow(
                  label: 'Service Fee',
                  value: amountFmt.format(detail.serviceFeeTotal),
                ),
              _InfoRow(
                label: 'Your Total',
                value: amountFmt.format(detail.merchantTotal),
                valueBold: true,
                valueColor: const Color(0xFFFF6B35),
              ),
            ],
          ),

          // 区块4：时间线
          if (detail.timeline.events.isNotEmpty)
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
              OrderStatusBadge(status: detail.primaryStatus, fontSize: 13),
              const SizedBox(width: 8),
              Text(
                '${detail.items.length} voucher${detail.items.length > 1 ? 's' : ''}',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade500,
                ),
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
        ],
      ),
    );
  }

  // Vouchers 区块：展示每张券
  Widget _buildVouchersSection(
      MerchantOrderDetail detail, NumberFormat amountFmt) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 区块标题
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Row(
            children: [
              const Icon(Icons.confirmation_number_outlined,
                  size: 16, color: Color(0xFFFF6B35)),
              const SizedBox(width: 8),
              Text(
                'Vouchers (${detail.items.length})',
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
        // 每张券一个卡片
        ...detail.items.asMap().entries.map((entry) {
          final index = entry.key;
          final item = entry.value;
          return _buildVoucherCard(item, index + 1, detail.items.length,
              amountFmt);
        }),
        const SizedBox(height: 4),
      ],
    );
  }

  // 单张券卡片
  Widget _buildVoucherCard(MerchantOrderItem item, int index, int total,
      NumberFormat amountFmt) {
    final itemStatus = OrderStatus.displayStatus(
      item.orderStatus,
      item.couponExpiresAt,
    );
    final isRedeemed =
        item.customerStatus == 'used' || item.customerStatus == 'redeemed';
    final isRefunded = item.customerStatus == 'refund_success' ||
        item.customerStatus == 'refunded';

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
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
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 第一行：序号 + deal 标题 + 状态
            Row(
              children: [
                // 序号圆圈
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '$index',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    item.dealTitle,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1A1A1A),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                OrderStatusBadge(status: itemStatus),
              ],
            ),
            const SizedBox(height: 10),

            // 金额行
            Row(
              children: [
                Text(
                  'Price: ${amountFmt.format(item.unitPrice)}',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade600,
                  ),
                ),
                if (item.dealOriginalPrice > 0 &&
                    item.dealOriginalPrice != item.unitPrice) ...[
                  const SizedBox(width: 8),
                  Text(
                    amountFmt.format(item.dealOriginalPrice),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade400,
                      decoration: TextDecoration.lineThrough,
                    ),
                  ),
                ],
              ],
            ),

            // 券过期时间
            if (item.couponExpiresAt != null) ...[
              const SizedBox(height: 4),
              Text(
                'Expires: ${DateFormat('MMM d, yyyy').format(item.couponExpiresAt!.toLocal())}',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
              ),
            ],

            // 核销信息：已 redeem 时显示 coupon code
            if (isRedeemed && item.couponCode != null) ...[
              const SizedBox(height: 10),
              _CouponCodeRow(code: item.couponCode!),
              if (item.couponRedeemedAt != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Redeemed: ${DateFormat('MMM d, yyyy · h:mm a').format(item.couponRedeemedAt!.toLocal())}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.green.shade600,
                    ),
                  ),
                ),
            ],

            // 退款信息
            if (isRefunded) ...[
              const SizedBox(height: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.currency_exchange_rounded,
                        size: 13, color: Color(0xFFF59E0B)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        item.refundReason != null &&
                                item.refundReason!.isNotEmpty
                            ? 'Refunded — ${item.refundReason}'
                            : 'Refunded by DealJoy',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF92400E),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
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
  });

  final String label;
  final String value;
  final Color? valueColor;
  final bool valueBold;

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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.qr_code_2_rounded,
              size: 16, color: Color(0xFF10B981)),
          const SizedBox(width: 8),
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
    );
  }
}

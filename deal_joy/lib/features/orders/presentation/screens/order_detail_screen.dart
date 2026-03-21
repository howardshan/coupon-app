// 订单详情页 — 美团风格重写
// 布局从上到下：状态横幅 → Deal摘要卡片 → 券状态展开行 → Purchase Notes → Order Info → 底部操作栏

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/models/order_detail_model.dart';
import '../../data/models/order_item_model.dart';
import '../../domain/providers/orders_provider.dart';
import '../../domain/providers/coupons_provider.dart';

// ── 主屏幕 ────────────────────────────────────────

class OrderDetailScreen extends ConsumerWidget {
  final String orderId;
  /// 可选：只显示某个 deal 的信息（从 orders 列表点击某个 deal 进入时传入）
  final String? filterDealId;

  const OrderDetailScreen({super.key, required this.orderId, this.filterDealId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(userOrderDetailProvider(orderId));

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: detailAsync.when(
        data: (detail) => _MeituanOrderBody(
          detail: detail,
          orderId: orderId,
          filterDealId: filterDealId,
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
  final String? filterDealId;

  const _MeituanOrderBody({required this.detail, required this.orderId, this.filterDealId});

  @override
  ConsumerState<_MeituanOrderBody> createState() => _MeituanOrderBodyState();
}

class _MeituanOrderBodyState extends ConsumerState<_MeituanOrderBody> {
  // 每个 deal 分组的展开状态（key = dealId）
  final Map<String, bool> _expandedGroups = {};

  OrderDetailModel get detail => widget.detail;

  @override
  Widget build(BuildContext context) {
    // 如果有 filterDealId，只显示该 deal 的 items
    final filteredItems = widget.filterDealId != null
        ? detail.items.where((i) => i.dealId == widget.filterDealId).toList()
        : detail.items;

    // 按 deal_id 分组 items
    final groupMap = <String, List<OrderItemModel>>{};
    for (final item in filteredItems) {
      groupMap.putIfAbsent(item.dealId, () => []).add(item);
    }

    // 计算综合状态（用于顶部横幅）
    final overallStatus = _computeOverallStatus(filteredItems);

    return Stack(
      children: [
        // 主滚动区域
        CustomScrollView(
          slivers: [
            // 顶部状态横幅（带返回按钮）
            SliverToBoxAdapter(
              child: _StatusBanner(
                status: overallStatus,
                orderId: widget.orderId,
              ),
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

            // Purchase Notes 区块
            SliverToBoxAdapter(
              child: _PurchaseNotesSection(detail: detail),
            ),

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

  /// 根据 items 计算综合状态
  _OverallStatus _computeOverallStatus(List<OrderItemModel> items) {
    if (items.isEmpty) {
      // 降级到 detail.status
      return switch (detail.status) {
        'refunded' => _OverallStatus.refunded,
        'used' => _OverallStatus.used,
        'expired' => _OverallStatus.expired,
        _ => _OverallStatus.unused,
      };
    }

    final statuses = items.map((i) => i.customerStatus).toSet();

    // 优先级：退款中 > 已退款 > 已使用 > 未使用
    if (statuses.contains(CustomerItemStatus.refundPending) ||
        statuses.contains(CustomerItemStatus.refundReview)) {
      return _OverallStatus.refundPending;
    }
    if (statuses.every((s) =>
        s == CustomerItemStatus.refundSuccess ||
        s == CustomerItemStatus.used)) {
      if (statuses.contains(CustomerItemStatus.refundSuccess)) {
        return _OverallStatus.refunded;
      }
    }
    if (statuses.every((s) => s == CustomerItemStatus.refundSuccess)) {
      return _OverallStatus.refunded;
    }
    if (statuses.every((s) => s == CustomerItemStatus.used)) {
      return _OverallStatus.used;
    }
    if (statuses.every((s) => s == CustomerItemStatus.expired)) {
      return _OverallStatus.expired;
    }
    if (statuses.contains(CustomerItemStatus.unused)) {
      return _OverallStatus.unused;
    }
    return _OverallStatus.unused;
  }
}

// ── 综合状态枚举 ──────────────────────────────────

enum _OverallStatus { unused, used, refunded, refundPending, expired }

// ── 状态横幅 ──────────────────────────────────────

class _StatusBanner extends StatelessWidget {
  final _OverallStatus status;
  final String orderId;

  const _StatusBanner({required this.status, required this.orderId});

  @override
  Widget build(BuildContext context) {
    final (Color bgColor, Color textColor, String label, IconData icon) =
        switch (status) {
      _OverallStatus.unused => (
          const Color(0xFF00C853),
          Colors.white,
          'To Use',
          Icons.check_circle_outline_rounded,
        ),
      _OverallStatus.used => (
          const Color(0xFF2979FF),
          Colors.white,
          'Used',
          Icons.done_all_rounded,
        ),
      _OverallStatus.refunded => (
          const Color(0xFF9E9E9E),
          Colors.white,
          'Refunded',
          Icons.currency_exchange_rounded,
        ),
      _OverallStatus.refundPending => (
          const Color(0xFFFF9800),
          Colors.white,
          'Refund Processing',
          Icons.hourglass_empty_rounded,
        ),
      _OverallStatus.expired => (
          const Color(0xFF9E9E9E),
          Colors.white,
          'Expired',
          Icons.timer_off_outlined,
        ),
    };

    return Container(
      width: double.infinity,
      color: bgColor,
      padding: EdgeInsets.fromLTRB(
        16,
        MediaQuery.of(context).padding.top + 12,
        16,
        24,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 返回按钮
          GestureDetector(
            onTap: () => context.pop(),
            child: Icon(Icons.arrow_back_ios_new_rounded,
                color: textColor.withValues(alpha: 0.8), size: 20),
          ),
          const SizedBox(height: 20),
          // 状态图标 + 文字
          Row(
            children: [
              Icon(icon, color: textColor, size: 36),
              const SizedBox(width: 14),
              Text(
                label,
                style: TextStyle(
                  color: textColor,
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Deal 摘要卡片（含券状态展开行） ───────────────

class _DealSummaryCard extends ConsumerWidget {
  final List<OrderItemModel> dealItems;
  final bool isExpanded;
  final VoidCallback onToggleExpand;
  final VoidCallback onRefreshOrder;

  const _DealSummaryCard({
    required this.dealItems,
    required this.isExpanded,
    required this.onToggleExpand,
    required this.onRefreshOrder,
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
    final refundedItems = dealItems
        .where((i) =>
            i.customerStatus == CustomerItemStatus.refundSuccess ||
            i.customerStatus == CustomerItemStatus.refundPending ||
            i.customerStatus == CustomerItemStatus.refundReview)
        .toList();
    final otherItems = dealItems
        .where((i) =>
            i.customerStatus != CustomerItemStatus.unused &&
            i.customerStatus != CustomerItemStatus.used &&
            i.customerStatus != CustomerItemStatus.refundSuccess &&
            i.customerStatus != CustomerItemStatus.refundPending &&
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
              isExpanded: isExpanded,
              onToggle: onToggleExpand,
              onRefreshOrder: onRefreshOrder,
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
            ),
          if (refundedItems.isNotEmpty)
            _CouponStatusRow(
              label: refundedItems.first.customerStatus == CustomerItemStatus.refundPending
                  ? 'Refund Processing'
                  : 'Refunded',
              count: refundedItems.length,
              color: const Color(0xFF9E9E9E),
              items: refundedItems,
              isExpanded: false,
              onToggle: null,
              onRefreshOrder: onRefreshOrder,
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

  const _CouponStatusRow({
    required this.label,
    required this.count,
    required this.color,
    required this.items,
    required this.isExpanded,
    required this.onToggle,
    required this.onRefreshOrder,
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
                onRefreshOrder: onRefreshOrder,
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
  final VoidCallback onRefreshOrder;

  const _CouponDetailRow({required this.item, required this.onRefreshOrder});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final formattedCode = item.formattedCouponCode;

    return Container(
      color: const Color(0xFFFAFAFA),
      padding: const EdgeInsets.fromLTRB(24, 12, 16, 12),
      child: Row(
        children: [
          // 券码
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (formattedCode != null)
                  Text(
                    formattedCode,
                    style: const TextStyle(
                      fontSize: 14,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5,
                      color: AppColors.textPrimary,
                    ),
                  )
                else
                  const Text(
                    'No code',
                    style: TextStyle(
                        fontSize: 13, color: AppColors.textHint),
                  ),
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
              if (item.showQrCode) ...[
                _SmallButton(
                  label: 'QR Code',
                  color: const Color(0xFF00C853),
                  onTap: () => _showQrCodeSheet(context, item),
                ),
                const SizedBox(width: 8),
              ],
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
                  onTap: () => context.push('/review/${item.dealId}'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // 展示 QR Code Bottom Sheet
  void _showQrCodeSheet(BuildContext context, OrderItemModel item) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _QrCodeSheet(item: item),
    );
  }

  // 展示取消/退款 Bottom Sheet
  void _showCancelSheet(
      BuildContext context, WidgetRef ref, OrderItemModel item) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _CancelSheet(
        item: item,
        onConfirm: (refundMethod) async {
          final navigator = Navigator.of(context);
          final messenger = ScaffoldMessenger.of(context);
          final success = await ref
              .read(refundNotifierProvider.notifier)
              .requestItemRefund(
                item.id,
                refundMethod: refundMethod,
              );
          navigator.pop();
          if (success) {
            messenger.showSnackBar(
              const SnackBar(
                content: Text('Refund request submitted successfully'),
                behavior: SnackBarBehavior.floating,
              ),
            );
            onRefreshOrder();
          } else {
            messenger.showSnackBar(
              const SnackBar(
                content: Text('Failed to submit refund request'),
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

// ── Purchase Notes 区块 ───────────────────────────

class _PurchaseNotesSection extends StatelessWidget {
  final OrderDetailModel detail;

  const _PurchaseNotesSection({required this.detail});

  @override
  Widget build(BuildContext context) {
    // 取第一个 item 的过期时间作为有效期
    final expiresAt = detail.items.isNotEmpty
        ? detail.items.first.couponExpiresAt
        : detail.couponExpiresAt;

    return Container(
      margin: const EdgeInsets.only(top: 8),
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Purchase Notes',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),

          // 有效期
          if (expiresAt != null)
            _NoteRow(
              icon: Icons.calendar_today_outlined,
              label: 'Validity',
              value:
                  'Valid until ${DateFormat('MMM d, yyyy').format(expiresAt.toLocal())}',
            ),

          // 退款政策（从 deal 读取，降级到默认文案）
          _NoteRow(
            icon: Icons.refresh_rounded,
            label: 'Refund Policy',
            value: (detail.items.isNotEmpty && detail.items.first.refundPolicy != null)
                ? detail.items.first.refundPolicy!
                : 'Unused vouchers can be refunded anytime, instantly.',
          ),

          // 使用规则（从 deal.usage_rules 读取）
          if (detail.items.isNotEmpty && detail.items.first.usageRules.isNotEmpty)
            ...detail.items.first.usageRules.map((rule) => _NoteRow(
                  icon: Icons.info_outline_rounded,
                  label: 'Rules',
                  value: rule,
                ))
          else
            const _NoteRow(
              icon: Icons.info_outline_rounded,
              label: 'Usage Rules',
              value: 'Present QR code to merchant. Each voucher can only be used once.',
            ),
        ],
      ),
    );
  }
}

// ── 注意事项行 ────────────────────────────────────

class _NoteRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _NoteRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: AppColors.textHint),
          const SizedBox(width: 8),
          SizedBox(
            width: 90,
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
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
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
          if (detail.paymentStatus != null)
            _InfoRowCopy(
              label: 'Payment',
              value: _formatPaymentStatus(detail.paymentStatus!),
              canCopy: false,
            ),

          const Divider(height: 20, color: Color(0xFFF0F0F0)),

          // 小计
          _PriceRow(
            label: 'Subtotal',
            value: amountFmt.format(detail.totalAmount - totalServiceFee),
            isTotal: false,
          ),

          // Service fee（如有）
          if (totalServiceFee > 0)
            _PriceRow(
              label: 'Service Fee',
              value: amountFmt.format(totalServiceFee),
              isTotal: false,
            ),

          const SizedBox(height: 8),

          // 总计
          _PriceRow(
            label: 'Total Paid',
            value: amountFmt.format(detail.totalAmount),
            isTotal: true,
          ),
        ],
      ),
    );
  }

  String _formatPaymentStatus(String status) {
    return switch (status.toLowerCase()) {
      'succeeded' => 'Credit Card',
      'paid' => 'Credit Card',
      _ => status[0].toUpperCase() + status.substring(1),
    };
  }
}

// ── 信息行（带可选复制） ──────────────────────────

class _InfoRowCopy extends StatelessWidget {
  final String label;
  final String value;
  final bool canCopy;

  const _InfoRowCopy({
    required this.label,
    required this.value,
    required this.canCopy,
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
              style: const TextStyle(
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
              onPressed: () => context.push('/deals/${detail.dealId}'),
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
      builder: (_) => _CancelSheet(
        item: item,
        onConfirm: (refundMethod) async {
          final navigator = Navigator.of(context);
          final messenger = ScaffoldMessenger.of(context);
          final success = await ref
              .read(refundNotifierProvider.notifier)
              .requestItemRefund(
                item.id,
                refundMethod: refundMethod,
              );
          navigator.pop();
          if (success) {
            messenger.showSnackBar(
              const SnackBar(
                content: Text('Refund request submitted successfully'),
                behavior: SnackBarBehavior.floating,
              ),
            );
            ref.invalidate(userOrderDetailProvider(orderId));
          } else {
            messenger.showSnackBar(
              const SnackBar(
                content: Text('Failed to submit refund request'),
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

// ── QR Code Bottom Sheet ──────────────────────────

class _QrCodeSheet extends StatelessWidget {
  final OrderItemModel item;

  const _QrCodeSheet({required this.item});

  @override
  Widget build(BuildContext context) {
    final qrData = item.couponQrCode ?? item.couponCode ?? '';
    final formattedCode = item.formattedCouponCode;
    final expiresAt = item.couponExpiresAt;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 拖拽指示条
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.textHint,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Scan to Redeem',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 20),

          // QR Code 图片
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
                    width: 200,
                    height: 200,
                    child: Center(
                      child: Text(
                        'QR code unavailable',
                        style: TextStyle(color: AppColors.textHint),
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: 20),

          // 券码（带复制）
          if (formattedCode != null) ...[
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      formattedCode,
                      style: const TextStyle(
                        fontSize: 18,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Icon(
                      Icons.copy_rounded,
                      size: 16,
                      color: AppColors.textSecondary,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Deal 标题 + 商家 + 过期日期
          Text(
            item.dealTitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          if (item.merchantName != null || item.purchasedMerchantName != null) ...[
            const SizedBox(height: 4),
            Text(
              item.merchantName ?? item.purchasedMerchantName!,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          ],
          if (expiresAt != null) ...[
            const SizedBox(height: 4),
            Text(
              'Expires ${DateFormat('MMM d, yyyy').format(expiresAt.toLocal())}',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textHint,
              ),
            ),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ── Cancel / Refund Bottom Sheet ──────────────────

class _CancelSheet extends ConsumerStatefulWidget {
  final OrderItemModel item;
  final Future<void> Function(String refundMethod) onConfirm;

  const _CancelSheet({required this.item, required this.onConfirm});

  @override
  ConsumerState<_CancelSheet> createState() => _CancelSheetState();
}

class _CancelSheetState extends ConsumerState<_CancelSheet> {
  // 退款方式选择（默认 store_credit）
  String _selectedMethod = 'store_credit';
  bool _isSubmitting = false;

  @override
  Widget build(BuildContext context) {
    final isCancel = widget.item.showCancel;

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
            isCancel ? 'Cancel' : 'Request Refund',
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
          const SizedBox(height: 20),

          // 选项1：Store Credit（推荐）
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

          // 选项2：Original Payment
          _RefundMethodOption(
            selected: _selectedMethod == 'original_payment',
            title: 'Original Payment',
            subtitle: isCancel
                ? 'Excluding service fee · 5-10 business days'
                : '5-10 business days to original card',
            onTap: () =>
                setState(() => _selectedMethod = 'original_payment'),
          ),
          const SizedBox(height: 24),

          // 确认按钮
          ElevatedButton(
            onPressed: _isSubmitting
                ? null
                : () async {
                    setState(() => _isSubmitting = true);
                    await widget.onConfirm(_selectedMethod);
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

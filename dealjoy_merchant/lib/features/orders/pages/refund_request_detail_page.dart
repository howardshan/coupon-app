// 退款申请详情页（商家端）
// 显示用户退款申请的完整信息，商家可选择「同意」或「拒绝」
// 同意 → 直接执行退款（自动调用 execute-refund）
// 拒绝 → 进入管理员仲裁，需填写拒绝原因

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../providers/orders_provider.dart';

class RefundRequestDetailPage extends ConsumerStatefulWidget {
  final String refundRequestId;
  final Map<String, dynamic> refundRequest;

  const RefundRequestDetailPage({
    super.key,
    required this.refundRequestId,
    required this.refundRequest,
  });

  @override
  ConsumerState<RefundRequestDetailPage> createState() =>
      _RefundRequestDetailPageState();
}

class _RefundRequestDetailPageState
    extends ConsumerState<RefundRequestDetailPage> {
  bool _isLoading = false;

  // 从 Map 中提取字段
  String get _status => widget.refundRequest['status'] as String? ?? '';
  double get _refundAmount =>
      double.tryParse(
          widget.refundRequest['refund_amount']?.toString() ?? '0') ??
      0;
  String get _reason =>
      widget.refundRequest['reason'] as String? ?? 'No reason provided';
  String? get _merchantResponse =>
      widget.refundRequest['merchant_response'] as String?;
  String? get _createdAt => widget.refundRequest['created_at'] as String?;
  String? get _respondedAt => widget.refundRequest['responded_at'] as String?;

  // 嵌套 orders 数据
  Map<String, dynamic>? get _order =>
      widget.refundRequest['orders'] as Map<String, dynamic>?;
  String get _orderNumber => _order?['order_number'] as String? ?? '—';
  double get _orderTotal =>
      double.tryParse(_order?['total_amount']?.toString() ?? '0') ?? 0;

  // 嵌套 deals 数据
  Map<String, dynamic>? get _deal =>
      _order?['deals'] as Map<String, dynamic>?;
  String get _dealTitle => _deal?['title'] as String? ?? 'Unknown Deal';

  /// 单笔 order_item 退款时的行级上下文（Edge: refund_line_context）
  Map<String, dynamic>? get _lineCtx {
    final v = widget.refundRequest['refund_line_context'];
    return v is Map<String, dynamic> ? v : null;
  }

  String? get _lineDealTitle => _lineCtx?['deal_title'] as String?;
  String? get _couponTail => _lineCtx?['coupon_code_tail'] as String?;
  String? get _lineRedeemedAt => _lineCtx?['redeemed_at'] as String?;
  String? get _couponStatus => _lineCtx?['coupon_status'] as String?;
  String? get _lineDealSummary => _lineCtx?['deal_summary'] as String?;
  String? get _lineDealIdFromCtx => _lineCtx?['deal_id'] as String?;

  Map<String, dynamic>? get _orderCtx {
    final v = widget.refundRequest['refund_order_context'];
    return v is Map<String, dynamic> ? v : null;
  }

  String get _userDisplayName =>
      widget.refundRequest['user_display_name'] as String? ?? 'User';

  /// 行级 Deal 优先，否则订单级 Deal（与 Edge refund_order_context 一致）
  String get _displayDealTitle {
    final lt = _lineDealTitle;
    if (lt != null && lt.isNotEmpty) return lt;
    final ot = _orderCtx?['deal_title'] as String?;
    if (ot != null && ot.isNotEmpty) return ot;
    return _dealTitle;
  }

  String? get _displayDealSummary {
    final ls = _lineDealSummary?.trim();
    if (ls != null && ls.isNotEmpty) return ls;
    final os = _orderCtx?['deal_summary'] as String?;
    if (os != null && os.trim().isNotEmpty) return os.trim();
    return null;
  }

  String? get _displayDealId {
    final lid = _lineDealIdFromCtx?.trim();
    if (lid != null && lid.isNotEmpty) return lid;
    final oid = _orderCtx?['deal_id'] as String?;
    if (oid != null && oid.isNotEmpty) return oid;
    return _deal?['id'] as String?;
  }

  String? get _orderIdForNav =>
      _orderCtx?['order_id'] as String? ?? _order?['id'] as String?;

  bool get _hasOrderVoucherCard => _orderCtx != null || _order != null;

  double? get _lineUnitPrice {
    final v = _lineCtx?['unit_price'];
    if (v == null) return null;
    return double.tryParse(v.toString());
  }

  bool get _showLineVoucherDetail {
    if (_lineCtx == null) return false;
    return (_lineDealTitle != null && _lineDealTitle!.isNotEmpty) ||
        (_couponTail != null && _couponTail!.isNotEmpty) ||
        (_lineRedeemedAt != null && _lineRedeemedAt!.isNotEmpty) ||
        _lineUnitPrice != null ||
        (_couponStatus != null && _couponStatus!.isNotEmpty) ||
        _selectedOptionsPreview() != null;
  }

  String? _selectedOptionsPreview() {
    final so = _lineCtx?['selected_options'];
    if (so == null) return null;
    try {
      final s = const JsonEncoder.withIndent('  ').convert(so);
      if (s.length > 220) return '${s.substring(0, 217)}…';
      return s;
    } catch (_) {
      return so.toString();
    }
  }

  bool get _isFullOrderRefund =>
      widget.refundRequest['order_item_id'] == null;

  bool get _isPendingMerchant => _status == 'pending_merchant';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Refund Request'),
        actions: [
          // 状态标签
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: _StatusChip(status: _status),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _RefundSummaryCard(
              userDisplayName: _userDisplayName,
              reason: _reason,
              refundAmount: _refundAmount,
              status: _status,
              submittedAtIso: _createdAt,
            ),
            const SizedBox(height: 16),
            if (_hasOrderVoucherCard)
              _RefundOrderVoucherCard(
                orderCtx: _orderCtx,
                orderCreatedAtFallback: _order?['created_at'] as String?,
                orderPaidAtFallback: _order?['paid_at'] as String?,
                orderNumber: _orderNumber,
                orderId: _orderIdForNav,
                orderTotal: _orderTotal,
                displayDealTitle: _displayDealTitle,
                displayDealSummary: _displayDealSummary,
                dealId: _displayDealId,
                showLineVoucherDetail: _showLineVoucherDetail,
                lineDealTitle: _lineDealTitle,
                lineUnitPrice: _lineUnitPrice,
                couponTail: _couponTail,
                couponStatus: _couponStatus,
                lineRedeemedAt: _lineRedeemedAt,
                selectedOptionsPreview: _selectedOptionsPreview(),
                isFullOrderRefund: _isFullOrderRefund,
              ),
            const SizedBox(height: 16),

            // 商家回应（仅已处理时显示）
            if (_merchantResponse != null && _merchantResponse!.isNotEmpty) ...[
              _SectionCard(
                title: 'Your Response',
                icon: Icons.store_outlined,
                iconColor: Colors.blueGrey,
                children: [
                  if (_respondedAt != null)
                    _InfoRow(
                        label: 'Responded',
                        value: _formatDate(_respondedAt!)),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      _merchantResponse!,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.black87,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],

            // 状态说明横幅（已处理）
            if (!_isPendingMerchant) ...[
              _buildStatusBanner(),
              const SizedBox(height: 24),
            ],

            // 操作按钮区（仅 pending_merchant 状态显示）
            if (_isPendingMerchant) ...[
              const SizedBox(height: 8),
              _buildActionButtons(context),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBanner() {
    Color color;
    IconData icon;
    String title;
    String subtitle;

    switch (_status) {
      case 'approved_merchant':
      case 'completed':
        color = Colors.green;
        icon = Icons.check_circle_outline;
        title = 'Refund Approved';
        subtitle = 'You approved this refund. The customer will receive their money back.';
        break;
      case 'rejected_merchant':
      case 'pending_admin':
        color = Colors.orange;
        icon = Icons.pending_outlined;
        title = 'Escalated to Admin';
        subtitle = 'You rejected this request. DealJoy admin will make the final decision.';
        break;
      case 'approved_admin':
        color = Colors.green;
        icon = Icons.verified_outlined;
        title = 'Admin Approved';
        subtitle = 'DealJoy admin approved the refund after review.';
        break;
      case 'rejected_admin':
        color = Colors.red;
        icon = Icons.cancel_outlined;
        title = 'Refund Rejected';
        subtitle = 'DealJoy admin rejected this refund request.';
        break;
      case 'cancelled':
        color = Colors.grey;
        icon = Icons.remove_circle_outline;
        title = 'Request Cancelled';
        subtitle = 'This refund request was cancelled.';
        break;
      default:
        color = Colors.grey;
        icon = Icons.info_outline;
        title = _status.replaceAll('_', ' ');
        subtitle = '';
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: color,
                  ),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: color.withOpacity(0.8),
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 同意按钮
        ElevatedButton.icon(
          onPressed: _isLoading ? null : () => _handleApprove(context),
          icon: _isLoading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.check_circle_outline),
          label: const Text(
            'Approve Refund',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 52),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 12),

        // 拒绝按钮
        OutlinedButton.icon(
          onPressed: _isLoading ? null : () => _handleReject(context),
          icon: const Icon(Icons.cancel_outlined),
          label: const Text(
            'Reject & Escalate to Admin',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.red,
            side: const BorderSide(color: Colors.red),
            minimumSize: const Size(double.infinity, 52),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 8),

        // 提示文字
        const Text(
          'If you reject, DealJoy admin will review both sides and make the final decision.',
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Future<void> _handleApprove(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Approve Refund'),
        content: Text(
          'Are you sure you want to approve the refund of '
          '\$${_refundAmount.toStringAsFixed(2)}? '
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: const Text('Approve'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isLoading = true);
    try {
      await ref.read(ordersServiceProvider).decideRefundRequest(
            refundRequestId: widget.refundRequestId,
            action: 'approve',
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Refund approved. The customer will be notified.'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop(true); // 返回 true 表示需要刷新列表
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to approve: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleReject(BuildContext context) async {
    final reasonController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject & Escalate to Admin'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Please provide a reason for rejection. '
                'Both your reason and the customer\'s reason will be reviewed by DealJoy admin.',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: reasonController,
                maxLines: 3,
                maxLength: 300,
                decoration: const InputDecoration(
                  hintText: 'e.g., The customer fully used the service and the complaint is invalid.',
                  border: OutlineInputBorder(),
                  labelText: 'Rejection Reason',
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'Please provide a reason';
                  }
                  if (v.trim().length < 10) {
                    return 'Reason must be at least 10 characters';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.of(ctx).pop(reasonController.text.trim());
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Reject'),
          ),
        ],
      ),
    );

    if (reason == null || !mounted) return;

    setState(() => _isLoading = true);
    try {
      await ref.read(ordersServiceProvider).decideRefundRequest(
            refundRequestId: widget.refundRequestId,
            action: 'reject',
            reason: reason,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Request rejected and escalated to DealJoy admin for review.'),
          ),
        );
        Navigator.of(context).pop(true); // 返回 true 表示需要刷新列表
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to reject: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _formatDate(String isoString) {
    try {
      final dt = DateTime.parse(isoString).toLocal();
      return DateFormat('MMM d, yyyy · h:mm a').format(dt);
    } catch (_) {
      return isoString;
    }
  }
}

/// 与 After-Sales 详情顶部一致：脱敏用户、理由、金额、提交时间
class _RefundSummaryCard extends StatelessWidget {
  const _RefundSummaryCard({
    required this.userDisplayName,
    required this.reason,
    required this.refundAmount,
    required this.status,
    this.submittedAtIso,
  });

  final String userDisplayName;
  final String reason;
  final double refundAmount;
  final String status;
  final String? submittedAtIso;

  static String _fmtCompact(String? iso) {
    if (iso == null || iso.isEmpty) return '—';
    try {
      return DateFormat('MMM d, yyyy · HH:mm')
          .format(DateTime.parse(iso).toLocal());
    } catch (_) {
      return iso;
    }
  }

  String get _statusLabel {
    switch (status) {
      case 'pending_merchant':
        return 'PENDING';
      case 'approved_merchant':
      case 'completed':
        return 'APPROVED';
      case 'rejected_merchant':
      case 'pending_admin':
        return 'ESCALATED';
      case 'approved_admin':
        return 'ADMIN OK';
      case 'rejected_admin':
        return 'REJECTED';
      case 'cancelled':
        return 'CANCELLED';
      default:
        return status.replaceAll('_', ' ').toUpperCase();
    }
  }

  Color get _statusColor {
    switch (status) {
      case 'pending_merchant':
        return const Color(0xFF0F62FE);
      case 'approved_merchant':
      case 'completed':
      case 'approved_admin':
        return Colors.green.shade700;
      case 'rejected_merchant':
      case 'pending_admin':
        return Colors.deepOrange;
      case 'rejected_admin':
        return Colors.red;
      default:
        return Colors.grey.shade700;
    }
  }

  @override
  Widget build(BuildContext context) {
    final amountFmt = NumberFormat.simpleCurrency();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      userDisplayName,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Customer (masked)',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: Colors.grey.shade600,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      reason,
                      style: const TextStyle(color: Colors.black54),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _statusColor.withValues(alpha: 0.35),
                  ),
                ),
                child: Text(
                  _statusLabel,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: _statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Refund amount',
                      style: TextStyle(color: Colors.black54),
                    ),
                    Text(
                      amountFmt.format(refundAmount),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.red,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Request submitted',
                      style: TextStyle(color: Colors.black54),
                    ),
                    Text(
                      _fmtCompact(submittedAtIso),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 与 After-Sales「Order & voucher」卡对齐：时间、跳转、Deal 摘要、行级券
class _RefundOrderVoucherCard extends StatelessWidget {
  const _RefundOrderVoucherCard({
    required this.orderCtx,
    required this.orderCreatedAtFallback,
    required this.orderPaidAtFallback,
    required this.orderNumber,
    required this.orderId,
    required this.orderTotal,
    required this.displayDealTitle,
    required this.displayDealSummary,
    required this.dealId,
    required this.showLineVoucherDetail,
    required this.lineDealTitle,
    required this.lineUnitPrice,
    required this.couponTail,
    required this.couponStatus,
    required this.lineRedeemedAt,
    required this.selectedOptionsPreview,
    required this.isFullOrderRefund,
  });

  final Map<String, dynamic>? orderCtx;
  final String? orderCreatedAtFallback;
  final String? orderPaidAtFallback;
  final String orderNumber;
  final String? orderId;
  final double orderTotal;
  final String displayDealTitle;
  final String? displayDealSummary;
  final String? dealId;
  final bool showLineVoucherDetail;
  final String? lineDealTitle;
  final double? lineUnitPrice;
  final String? couponTail;
  final String? couponStatus;
  final String? lineRedeemedAt;
  final String? selectedOptionsPreview;
  final bool isFullOrderRefund;

  static String _fmtCompact(String? iso) {
    if (iso == null || iso.isEmpty) return '—';
    try {
      return DateFormat('MMM d, yyyy · HH:mm')
          .format(DateTime.parse(iso).toLocal());
    } catch (_) {
      return iso;
    }
  }

  static String _fmtDetailPage(String iso) {
    try {
      return DateFormat('MMM d, yyyy · h:mm a')
          .format(DateTime.parse(iso).toLocal());
    } catch (_) {
      return iso;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final created = orderCtx?['order_created_at'] as String? ??
        orderCreatedAtFallback;
    final paid = orderCtx?['order_paid_at'] as String? ?? orderPaidAtFallback;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Order & voucher',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 12),
          if (created != null && created.isNotEmpty)
            _RefundCtxRow(
              label: 'Order placed',
              value: _fmtCompact(created),
            ),
          if (paid != null && paid.isNotEmpty)
            _RefundCtxRow(
              label: 'Paid at',
              value: _fmtCompact(paid),
            ),
          if (orderNumber.isNotEmpty && orderNumber != '—')
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 132,
                    child: Text(
                      'Order #',
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          orderNumber,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF1A1A1A),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Total: ${NumberFormat.simpleCurrency().format(orderTotal)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade700,
                          ),
                        ),
                        if (orderId != null && orderId!.isNotEmpty)
                          TextButton(
                            onPressed: () => context.push('/orders/$orderId'),
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              foregroundColor: scheme.primary,
                            ),
                            child: const Text('View order details'),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          if (displayDealTitle.isNotEmpty &&
              displayDealTitle != 'Unknown Deal') ...[
            _RefundCtxRow(label: 'Deal', value: displayDealTitle),
            if (displayDealSummary != null &&
                displayDealSummary!.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 132, bottom: 8),
                child: Text(
                  displayDealSummary!.trim(),
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: Colors.grey.shade800,
                  ),
                ),
              ),
            if (dealId != null && dealId!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 132, bottom: 8),
                child: TextButton(
                  onPressed: () => context.push('/deals/$dealId'),
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    foregroundColor: scheme.primary,
                  ),
                  child: const Text('View deal details'),
                ),
              ),
          ],
          if (isFullOrderRefund && !showLineVoucherDetail) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'This refund applies to the full order (not tied to a single voucher line).',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade700,
                  height: 1.35,
                ),
              ),
            ),
          ],
          if (showLineVoucherDetail) ...[
            const Divider(height: 20),
            Text(
              'Affected voucher',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 8),
            if (lineDealTitle != null && lineDealTitle!.isNotEmpty)
              _RefundCtxRow(label: 'Line deal', value: lineDealTitle!),
            if (lineUnitPrice != null)
              _RefundCtxRow(
                label: 'Line price',
                value: NumberFormat.currency(symbol: '\$').format(lineUnitPrice!),
              ),
            if (couponTail != null && couponTail!.isNotEmpty)
              _RefundCtxRow(label: 'Voucher code', value: couponTail!),
            if (couponStatus != null && couponStatus!.isNotEmpty)
              _RefundCtxRow(label: 'Voucher status', value: couponStatus!),
            if (lineRedeemedAt != null && lineRedeemedAt!.isNotEmpty)
              _RefundCtxRow(
                label: 'Verified / redeemed',
                value: _fmtDetailPage(lineRedeemedAt!),
              ),
            if (selectedOptionsPreview != null)
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 0),
                child: Text(
                  'Purchased options\n$selectedOptionsPreview',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.black54,
                    height: 1.35,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _RefundCtxRow extends StatelessWidget {
  const _RefundCtxRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 132,
            child: Text(
              label,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Color(0xFF1A1A1A),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── 状态 Chip ──────────────────────────────────────────
class _StatusChip extends StatelessWidget {
  final String status;

  const _StatusChip({required this.status});

  Color get _color {
    switch (status) {
      case 'pending_merchant':
        return Colors.orange;
      case 'approved_merchant':
      case 'completed':
        return Colors.green;
      case 'rejected_merchant':
      case 'pending_admin':
        return Colors.deepOrange;
      case 'approved_admin':
        return Colors.green;
      case 'rejected_admin':
        return Colors.red;
      case 'cancelled':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  String get _label {
    switch (status) {
      case 'pending_merchant':
        return 'Awaiting Review';
      case 'approved_merchant':
        return 'Approved';
      case 'rejected_merchant':
        return 'Rejected';
      case 'pending_admin':
        return 'Admin Review';
      case 'approved_admin':
        return 'Admin Approved';
      case 'rejected_admin':
        return 'Rejected';
      case 'completed':
        return 'Refunded';
      case 'cancelled':
        return 'Cancelled';
      default:
        return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _color.withOpacity(0.4)),
      ),
      child: Text(
        _label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: _color,
        ),
      ),
    );
  }
}

// ── 区块卡片 ────────────────────────────────────────────
class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.children,
    this.iconColor = Colors.blue,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
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
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey[600],
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
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

// ── 信息行 ─────────────────────────────────────────────
class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Colors.black87,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

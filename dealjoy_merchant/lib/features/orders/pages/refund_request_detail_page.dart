// 退款申请详情页（商家端）
// 显示用户退款申请的完整信息，商家可选择「同意」或「拒绝」
// 同意 → 直接执行退款（自动调用 execute-refund）
// 拒绝 → 进入管理员仲裁，需填写拒绝原因

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
  String? get _orderCreatedAt => _order?['created_at'] as String?;

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

  double? get _lineUnitPrice {
    final v = _lineCtx?['unit_price'];
    if (v == null) return null;
    return double.tryParse(v.toString());
  }

  bool get _showAffectedVoucherSection {
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
            // 区块1：订单信息
            _SectionCard(
              title: 'Order Info',
              icon: Icons.receipt_long_outlined,
              children: [
                _InfoRow(label: 'Deal', value: _dealTitle),
                _InfoRow(label: 'Order #', value: _orderNumber),
                _InfoRow(
                    label: 'Order Total',
                    value: NumberFormat.currency(symbol: '\$')
                        .format(_orderTotal)),
                if (_orderCreatedAt != null)
                  _InfoRow(
                      label: 'Ordered',
                      value: _formatDate(_orderCreatedAt!)),
              ],
            ),
            const SizedBox(height: 12),

            if (_showAffectedVoucherSection) ...[
              _SectionCard(
                title: 'Affected voucher',
                icon: Icons.confirmation_number_outlined,
                iconColor: Colors.teal,
                children: [
                  if (_lineDealTitle != null && _lineDealTitle!.isNotEmpty)
                    _InfoRow(label: 'Line deal', value: _lineDealTitle!),
                  if (_lineUnitPrice != null)
                    _InfoRow(
                      label: 'Line price',
                      value: NumberFormat.currency(symbol: '\$')
                          .format(_lineUnitPrice!),
                    ),
                  if (_couponTail != null && _couponTail!.isNotEmpty)
                    _InfoRow(label: 'Voucher code', value: _couponTail!),
                  if (_couponStatus != null && _couponStatus!.isNotEmpty)
                    _InfoRow(label: 'Voucher status', value: _couponStatus!),
                  if (_lineRedeemedAt != null && _lineRedeemedAt!.isNotEmpty)
                    _InfoRow(
                      label: 'Verified / redeemed',
                      value: _formatDate(_lineRedeemedAt!),
                    ),
                  if (_selectedOptionsPreview() != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Purchased options\n${_selectedOptionsPreview()!}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.black54,
                            height: 1.35,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
            ] else if (_isFullOrderRefund) ...[
              _SectionCard(
                title: 'Scope',
                icon: Icons.info_outline,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      'This refund applies to the full order (not tied to a single voucher line).',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade700,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],

            // 区块2：退款申请信息
            _SectionCard(
              title: 'Refund Request',
              icon: Icons.policy_outlined,
              iconColor: Colors.orange,
              children: [
                _InfoRow(
                  label: 'Refund Amount',
                  value: NumberFormat.currency(symbol: '\$')
                      .format(_refundAmount),
                  valueColor: Colors.red,
                  valueBold: true,
                ),
                if (_createdAt != null)
                  _InfoRow(
                      label: 'Submitted',
                      value: _formatDate(_createdAt!)),
              ],
            ),
            const SizedBox(height: 12),

            // 区块3：用户填写的退款原因
            _SectionCard(
              title: "Customer's Reason",
              icon: Icons.chat_bubble_outline,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    _reason,
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

            // 区块4：商家回应（仅已处理时显示）
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
            width: 120,
            child: Text(
              label,
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight:
                    valueBold ? FontWeight.w700 : FontWeight.w500,
                color: valueColor ?? Colors.black87,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

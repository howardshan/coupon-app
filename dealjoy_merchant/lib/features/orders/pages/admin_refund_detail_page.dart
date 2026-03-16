// 管理员仲裁详情页（Task 16）
// 展示完整退款申请信息：用户原因 + 商家拒绝理由
// 管理员可「最终批准」（调用 execute-refund）或「最终拒绝」（需填写原因）

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../providers/orders_provider.dart';

class AdminRefundDetailPage extends ConsumerStatefulWidget {
  final String refundRequestId;
  final Map<String, dynamic> refundRequest;

  const AdminRefundDetailPage({
    super.key,
    required this.refundRequestId,
    required this.refundRequest,
  });

  @override
  ConsumerState<AdminRefundDetailPage> createState() =>
      _AdminRefundDetailPageState();
}

class _AdminRefundDetailPageState
    extends ConsumerState<AdminRefundDetailPage> {
  bool _isLoading = false;

  // 基本字段
  String get _status => widget.refundRequest['status'] as String? ?? '';
  double get _refundAmount =>
      double.tryParse(widget.refundRequest['refund_amount']?.toString() ?? '0') ?? 0;
  String get _userReason =>
      widget.refundRequest['reason'] as String? ?? 'No reason provided';
  String? get _merchantResponse =>
      widget.refundRequest['merchant_response'] as String?;
  String? get _adminResponse =>
      widget.refundRequest['admin_response'] as String?;
  String? get _createdAt => widget.refundRequest['created_at'] as String?;
  String? get _respondedAt => widget.refundRequest['responded_at'] as String?;
  String? get _adminDecidedAt => widget.refundRequest['admin_decided_at'] as String?;

  // 嵌套订单数据
  Map<String, dynamic>? get _order =>
      widget.refundRequest['orders'] as Map<String, dynamic>?;
  String get _orderNumber => _order?['order_number'] as String? ?? '—';
  double get _orderTotal =>
      double.tryParse(_order?['total_amount']?.toString() ?? '0') ?? 0;
  String? get _orderCreatedAt => _order?['created_at'] as String?;

  // 嵌套 deal / merchant 数据
  Map<String, dynamic>? get _deal =>
      _order?['deals'] as Map<String, dynamic>?;
  String get _dealTitle => _deal?['title'] as String? ?? 'Unknown Deal';
  Map<String, dynamic>? get _merchant =>
      _order?['merchants'] as Map<String, dynamic>?;
  String get _merchantName => _merchant?['name'] as String? ?? 'Unknown Merchant';

  bool get _isPendingAdmin => _status == 'pending_admin';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Arbitration'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(child: _StatusChip(status: _status)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 管理员仲裁说明横幅
            if (_isPendingAdmin) ...[
              _buildArbitrationBanner(),
              const SizedBox(height: 12),
            ],

            // 区块1：订单信息
            _SectionCard(
              title: 'Order Info',
              icon: Icons.receipt_long_outlined,
              children: [
                _InfoRow(label: 'Deal', value: _dealTitle),
                _InfoRow(label: 'Merchant', value: _merchantName),
                _InfoRow(label: 'Order #', value: _orderNumber),
                _InfoRow(
                  label: 'Order Total',
                  value: NumberFormat.currency(symbol: '\$').format(_orderTotal),
                ),
                if (_orderCreatedAt != null)
                  _InfoRow(label: 'Ordered', value: _formatDate(_orderCreatedAt!)),
              ],
            ),
            const SizedBox(height: 12),

            // 区块2：退款申请信息
            _SectionCard(
              title: 'Refund Request',
              icon: Icons.policy_outlined,
              iconColor: Colors.deepOrange,
              children: [
                _InfoRow(
                  label: 'Refund Amount',
                  value: NumberFormat.currency(symbol: '\$').format(_refundAmount),
                  valueColor: Colors.red,
                  valueBold: true,
                ),
                if (_createdAt != null)
                  _InfoRow(label: 'Submitted', value: _formatDate(_createdAt!)),
              ],
            ),
            const SizedBox(height: 12),

            // 区块3：用户退款原因
            _SectionCard(
              title: "Customer's Reason",
              icon: Icons.person_outline,
              iconColor: Colors.blue,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    _userReason,
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

            // 区块4：商家拒绝理由
            _SectionCard(
              title: "Merchant's Rejection Reason",
              icon: Icons.store_outlined,
              iconColor: Colors.orange,
              children: [
                if (_respondedAt != null)
                  _InfoRow(label: 'Responded', value: _formatDate(_respondedAt!)),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    _merchantResponse ?? 'No reason provided',
                    style: TextStyle(
                      fontSize: 14,
                      color: _merchantResponse != null
                          ? Colors.black87
                          : Colors.grey,
                      height: 1.5,
                      fontStyle: _merchantResponse != null
                          ? FontStyle.normal
                          : FontStyle.italic,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // 区块5：管理员决定（已处理时显示）
            if (_adminResponse != null || _adminDecidedAt != null) ...[
              _SectionCard(
                title: 'Admin Decision',
                icon: Icons.gavel,
                iconColor: _status == 'approved_admin' ? Colors.green : Colors.red,
                children: [
                  if (_adminDecidedAt != null)
                    _InfoRow(label: 'Decided', value: _formatDate(_adminDecidedAt!)),
                  if (_adminResponse != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        _adminResponse!,
                        style: const TextStyle(fontSize: 14, height: 1.5),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
            ],

            // 状态说明横幅（已处理）
            if (!_isPendingAdmin) ...[
              _buildStatusBanner(),
              const SizedBox(height: 24),
            ],

            // 操作按钮（仅 pending_admin 显示）
            if (_isPendingAdmin) ...[
              const SizedBox(height: 8),
              _buildActionButtons(context),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildArbitrationBanner() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.deepOrange.withOpacity(0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.deepOrange.withOpacity(0.3)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.gavel, color: Colors.deepOrange, size: 20),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Admin Arbitration Required',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: Colors.deepOrange,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'The merchant rejected this refund request. Review both the customer\'s reason and the merchant\'s response to make a final decision.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.deepOrange,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBanner() {
    Color color;
    IconData icon;
    String title;
    String subtitle;

    switch (_status) {
      case 'approved_admin':
      case 'completed':
        color = Colors.green;
        icon = Icons.verified_outlined;
        title = 'Refund Approved';
        subtitle = 'You approved this refund. The customer will receive their money back.';
        break;
      case 'rejected_admin':
        color = Colors.red;
        icon = Icons.cancel_outlined;
        title = 'Refund Finally Rejected';
        subtitle = 'You rejected this refund request. The customer will be notified.';
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
                      fontSize: 12,
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
        // 批准按钮
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
            'Approve Refund (Final)',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 52),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 12),

        // 拒绝按钮
        OutlinedButton.icon(
          onPressed: _isLoading ? null : () => _handleReject(context),
          icon: const Icon(Icons.cancel_outlined),
          label: const Text(
            'Reject Refund (Final)',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.red,
            side: const BorderSide(color: Colors.red),
            minimumSize: const Size(double.infinity, 52),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'This is the final decision. The customer will be notified of the outcome.',
          style: TextStyle(fontSize: 12, color: Colors.grey),
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
        title: const Text('Final Approval'),
        content: Text(
          'Approve the refund of \$${_refundAmount.toStringAsFixed(2)} to the customer? '
          'This action will immediately process the Stripe refund and cannot be undone.',
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
      await ref.read(ordersServiceProvider).adminDecideRefundRequest(
            refundRequestId: widget.refundRequestId,
            action: 'approve',
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Refund approved. Stripe refund initiated.'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop(true);
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
        title: const Text('Final Rejection'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'This is the final rejection. The customer will not receive a refund. '
                'Please provide a clear reason.',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: reasonController,
                maxLines: 3,
                maxLength: 500,
                decoration: const InputDecoration(
                  hintText: 'e.g., After reviewing both sides, the service was properly delivered and the complaint lacks merit.',
                  border: OutlineInputBorder(),
                  labelText: 'Admin Rejection Reason',
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
      await ref.read(ordersServiceProvider).adminDecideRefundRequest(
            refundRequestId: widget.refundRequestId,
            action: 'reject',
            reason: reason,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Refund request finally rejected.'),
          ),
        );
        Navigator.of(context).pop(true);
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
      case 'pending_admin':
        return Colors.deepOrange;
      case 'approved_admin':
      case 'completed':
        return Colors.green;
      case 'rejected_admin':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String get _label {
    switch (status) {
      case 'pending_admin':
        return 'Awaiting Admin';
      case 'approved_admin':
        return 'Approved';
      case 'rejected_admin':
        return 'Rejected';
      case 'completed':
        return 'Refunded';
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
                fontWeight: valueBold ? FontWeight.w700 : FontWeight.w500,
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

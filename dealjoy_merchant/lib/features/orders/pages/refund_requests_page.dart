// 商家退款申请列表页
// 显示用户提交的核销后退款申请
// 分 Pending（待处理）/ All（全部）两个 Tab
// 调用 merchant-orders/refund-requests 路由

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../providers/orders_provider.dart';
import 'refund_request_detail_page.dart';

/// 商家退款申请列表页
class RefundRequestsPage extends ConsumerStatefulWidget {
  const RefundRequestsPage({super.key});

  @override
  ConsumerState<RefundRequestsPage> createState() =>
      _RefundRequestsPageState();
}

class _RefundRequestsPageState extends ConsumerState<RefundRequestsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  bool _isLoading = false;
  List<Map<String, dynamic>> _pendingRequests = [];
  List<Map<String, dynamic>> _allRequests = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadRequests();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadRequests() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final service = ref.read(ordersServiceProvider);
      final results = await Future.wait([
        service.fetchRefundRequests(status: 'pending_merchant'),
        service.fetchRefundRequests(),
      ]);

      setState(() {
        _pendingRequests = List<Map<String, dynamic>>.from(
          results[0]['data'] as List? ?? [],
        );
        _allRequests = List<Map<String, dynamic>>.from(
          results[1]['data'] as List? ?? [],
        );
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Refund Requests'),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(
              text: 'Pending',
              icon: _pendingRequests.isNotEmpty
                  ? Badge(
                      label: Text('${_pendingRequests.length}'),
                      child: const Icon(Icons.pending_actions),
                    )
                  : const Icon(Icons.pending_actions),
            ),
            const Tab(text: 'All', icon: Icon(Icons.list_alt)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loadRequests,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildErrorState()
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildList(_pendingRequests, showPendingOnly: true),
                    _buildList(_allRequests),
                  ],
                ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              _error ?? 'Unknown error',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadRequests,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList(
    List<Map<String, dynamic>> requests, {
    bool showPendingOnly = false,
  }) {
    if (requests.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle_outline,
                size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              showPendingOnly
                  ? 'No pending refund requests'
                  : 'No refund requests found',
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 8),
            const Text(
              'When customers request post-use refunds,\nthey will appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadRequests,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: requests.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final rr = requests[index];
          return _RefundRequestTile(
            refundRequest: rr,
            onTap: () async {
              final updated = await Navigator.push<bool>(
                context,
                MaterialPageRoute(
                  builder: (_) => RefundRequestDetailPage(
                    refundRequestId: rr['id'] as String,
                    refundRequest: rr,
                  ),
                ),
              );
              if (updated == true) _loadRequests();
            },
          );
        },
      ),
    );
  }
}

// =============================================================
// _RefundRequestTile — 单条退款申请卡片
// =============================================================
class _RefundRequestTile extends StatelessWidget {
  final Map<String, dynamic> refundRequest;
  final VoidCallback onTap;

  const _RefundRequestTile({required this.refundRequest, required this.onTap});

  Color _statusColor(String status) {
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

  String _statusLabel(String status) {
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
        return status.replaceAll('_', ' ');
    }
  }

  String _formatDate(String isoString) {
    try {
      final dt = DateTime.parse(isoString).toLocal();
      return DateFormat('MMM d, yyyy').format(dt);
    } catch (_) {
      return isoString;
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = refundRequest['status'] as String? ?? '';
    final refundAmount = refundRequest['refund_amount'];
    final orders = refundRequest['orders'] as Map<String, dynamic>?;
    final deals = orders?['deals'] as Map<String, dynamic>?;
    final orderNumber = orders?['order_number'] as String? ?? '';
    final dealTitle = deals?['title'] as String? ?? 'Unknown Deal';
    final createdAt = refundRequest['created_at'] as String?;
    final reason = refundRequest['reason'] as String? ?? '';
    final isPending = status == 'pending_merchant';

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: isPending
            ? BorderSide(color: Colors.orange.withOpacity(0.4), width: 1)
            : BorderSide.none,
      ),
      child: ListTile(
        onTap: onTap,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 4,
          decoration: BoxDecoration(
            color: _statusColor(status),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                dealTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 14),
              ),
            ),
            Text(
              '\$${double.tryParse(refundAmount.toString())?.toStringAsFixed(2) ?? '0.00'}',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: Colors.red,
              ),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            if (orderNumber.isNotEmpty)
              Text(
                'Order: $orderNumber',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            if (createdAt != null) ...[
              const SizedBox(height: 2),
              Text(
                'Submitted: ${_formatDate(createdAt)}',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
            if (reason.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                reason,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
            const SizedBox(height: 6),
            // 状态 Badge
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _statusColor(status).withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                    color: _statusColor(status), width: 0.5),
              ),
              child: Text(
                _statusLabel(status),
                style: TextStyle(
                  fontSize: 10,
                  color: _statusColor(status),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        trailing: isPending
            ? const Icon(Icons.chevron_right,
                color: Colors.orange)
            : const Icon(Icons.chevron_right, color: Colors.grey),
        isThreeLine: true,
      ),
    );
  }
}

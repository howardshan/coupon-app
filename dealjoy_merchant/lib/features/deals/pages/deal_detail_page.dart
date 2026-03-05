// Deal详情页面
// 展示 Deal 完整信息，包含审核状态、拒绝原因、编辑/上下架操作

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../models/merchant_deal.dart';
import '../providers/deals_provider.dart';
import '../widgets/deal_status_badge.dart';
import 'deal_edit_page.dart';

// ============================================================
// DealDetailPage — Deal 完整详情页（ConsumerWidget）
// ============================================================
class DealDetailPage extends ConsumerWidget {
  const DealDetailPage({super.key, required this.dealId});

  final String dealId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dealsAsync = ref.watch(dealsProvider);

    return dealsAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator(color: Color(0xFFFF6B35))),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: Center(child: Text('Error: $e')),
      ),
      data: (deals) {
        // 从列表中查找对应 Deal
        final deal = deals.where((d) => d.id == dealId).firstOrNull;

        if (deal == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Deal Not Found')),
            body: const Center(
              child: Text(
                'This deal was not found.',
                style: TextStyle(color: Color(0xFF999999)),
              ),
            ),
          );
        }

        return _DealDetailView(deal: deal, ref: ref);
      },
    );
  }
}

// ============================================================
// 详情内容视图（分离以便复用 deal 对象）
// ============================================================
class _DealDetailView extends StatelessWidget {
  const _DealDetailView({required this.deal, required this.ref});

  final MerchantDeal deal;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF333333)),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          'Deal Details',
          style: TextStyle(
            color: Color(0xFF1A1A1A),
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          // 编辑按钮（仅非 pending 状态可编辑）
          if (deal.canEdit)
            TextButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => DealEditPage(deal: deal),
                  ),
                );
              },
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Edit'),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFFF6B35),
              ),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 状态横幅（待审核/已拒绝时显示醒目提示）
            if (deal.dealStatus == DealStatus.pending ||
                deal.dealStatus == DealStatus.rejected) ...[
              _StatusBanner(deal: deal),
              const SizedBox(height: 12),
            ],

            // 图片画廊
            if (deal.images.isNotEmpty) ...[
              _ImageGallery(images: deal.images),
              const SizedBox(height: 16),
            ],

            // 基本信息卡片
            _InfoCard(
              title: 'Basic Info',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 标题 + 状态
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          deal.title,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1A1A1A),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      DealStatusBadge(status: deal.dealStatus),
                    ],
                  ),
                  const SizedBox(height: 6),
                  // 类别
                  Text(
                    deal.category,
                    style: const TextStyle(fontSize: 13, color: Color(0xFF999999)),
                  ),
                  const SizedBox(height: 12),
                  // 描述
                  Text(
                    deal.description,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF555555),
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // 价格卡片
            _InfoCard(
              title: 'Pricing',
              child: Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Deal Price',
                        style: TextStyle(fontSize: 12, color: Color(0xFF999999)),
                      ),
                      Text(
                        '\$${deal.discountPrice.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFFFF6B35),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 24),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Original Price',
                        style: TextStyle(fontSize: 12, color: Color(0xFF999999)),
                      ),
                      Text(
                        '\$${deal.originalPrice.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 16,
                          color: Color(0xFFBBBBBB),
                          decoration: TextDecoration.lineThrough,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  // 折扣标签
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF6B35),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      deal.discountLabel,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // 库存和有效期卡片
            _InfoCard(
              title: 'Stock & Validity',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _DetailRow(
                    icon: Icons.inventory_2_outlined,
                    label: 'Stock',
                    value: deal.isUnlimited
                        ? 'Unlimited'
                        : '${deal.remainingStock} remaining (${deal.totalSold} sold)',
                  ),
                  const SizedBox(height: 10),
                  _DetailRow(
                    icon: Icons.calendar_today_outlined,
                    label: 'Validity',
                    value: deal.validityType == ValidityType.fixedDate
                        ? 'Expires ${DateFormat('MMM d, yyyy').format(deal.expiresAt)}'
                        : '${deal.validityDays ?? '?'} days after purchase',
                  ),
                  if (deal.publishedAt != null) ...[
                    const SizedBox(height: 10),
                    _DetailRow(
                      icon: Icons.rocket_launch_outlined,
                      label: 'First Published',
                      value: DateFormat('MMM d, yyyy').format(deal.publishedAt!),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),

            // 套餐内容卡片
            if (deal.packageContents.isNotEmpty) ...[
              _InfoCard(
                title: 'Package Contents',
                child: Text(
                  deal.packageContents,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF555555),
                    height: 1.6,
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],

            // 使用规则卡片
            _InfoCard(
              title: 'Usage Rules',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 可用日期
                  _DetailRow(
                    icon: Icons.event_available_outlined,
                    label: 'Available Days',
                    value: deal.usageDays.isEmpty
                        ? 'All days'
                        : deal.usageDays.join(', '),
                  ),
                  const SizedBox(height: 10),

                  // 每人限用
                  _DetailRow(
                    icon: Icons.people_outline,
                    label: 'Max Per Person',
                    value: deal.maxPerPerson != null
                        ? '${deal.maxPerPerson} per person'
                        : 'No limit',
                  ),
                  const SizedBox(height: 10),

                  // 是否可叠加
                  _DetailRow(
                    icon: deal.isStackable
                        ? Icons.layers_outlined
                        : Icons.layers_clear_outlined,
                    label: 'Stackable',
                    value: deal.isStackable
                        ? 'Can be combined with other offers'
                        : 'Cannot be combined',
                  ),

                  // 使用须知
                  if (deal.usageNotes.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    _DetailRow(
                      icon: Icons.info_outline,
                      label: 'Usage Notes',
                      value: deal.usageNotes,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),

            // 统计卡片
            _InfoCard(
              title: 'Performance',
              child: Row(
                children: [
                  _StatItem(label: 'Total Sold', value: '${deal.totalSold}'),
                  const SizedBox(width: 24),
                  _StatItem(
                    label: 'Rating',
                    value: deal.reviewCount > 0
                        ? '${deal.rating.toStringAsFixed(1)} ★'
                        : 'No reviews',
                  ),
                  const SizedBox(width: 24),
                  _StatItem(label: 'Reviews', value: '${deal.reviewCount}'),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // 操作按钮（上下架）
            _ActionButtons(deal: deal, ref: ref),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// 状态横幅（pending/rejected 时显示）
// ============================================================
class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.deal});

  final MerchantDeal deal;

  @override
  Widget build(BuildContext context) {
    final isPending = deal.dealStatus == DealStatus.pending;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isPending ? const Color(0xFFFFF8E1) : const Color(0xFFFFEBEE),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isPending ? const Color(0xFFFFCC02) : const Color(0xFFEF9A9A),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isPending ? Icons.hourglass_top_rounded : Icons.cancel_outlined,
                color: isPending ? const Color(0xFFF9A825) : const Color(0xFFE53935),
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                isPending ? 'Under Review' : 'Review Rejected',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: isPending
                      ? const Color(0xFFF9A825)
                      : const Color(0xFFE53935),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            isPending
                ? 'Your deal is being reviewed by the DealJoy team. This usually takes 24-48 hours. The previous version (if any) continues to show to customers.'
                : 'Your deal was not approved. Please edit and resubmit.',
            style: TextStyle(
              fontSize: 13,
              color: isPending
                  ? const Color(0xFFF9A825)
                  : const Color(0xFFE53935),
              height: 1.4,
            ),
          ),
          // 拒绝原因（仅 rejected 状态显示）
          if (!isPending && deal.reviewNotes != null && deal.reviewNotes!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Rejection Reason:',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFE53935),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    deal.reviewNotes!,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF555555),
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ============================================================
// 图片画廊（横向滚动）
// ============================================================
class _ImageGallery extends StatelessWidget {
  const _ImageGallery({required this.images});

  final List<DealImage> images;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 200,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: images.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final image = images[index];
          return ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Stack(
              children: [
                CachedNetworkImage(
                  imageUrl: image.imageUrl,
                  width: images.length == 1 ? double.infinity : 220,
                  height: 200,
                  fit: BoxFit.cover,
                  placeholder: (_, _) => Container(
                    color: const Color(0xFFEEEEEE),
                    width: 220,
                    height: 200,
                  ),
                  errorWidget: (_, _, _) => Container(
                    color: const Color(0xFFEEEEEE),
                    width: 220,
                    height: 200,
                    child: const Icon(Icons.broken_image_outlined,
                        color: Color(0xFFCCCCCC)),
                  ),
                ),
                // Cover 标签
                if (image.isPrimary)
                  Positioned(
                    left: 8,
                    bottom: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF6B35),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'Cover',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ============================================================
// 信息卡片容器
// ============================================================
class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1A1A1A),
              ),
            ),
          ),
          const Divider(height: 16, thickness: 0.5),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: child,
          ),
        ],
      ),
    );
  }
}

// ============================================================
// 详情行（图标 + 标签 + 值）
// ============================================================
class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: const Color(0xFF999999)),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 11, color: Color(0xFF999999)),
            ),
            const SizedBox(height: 1),
            Text(
              value,
              style: const TextStyle(fontSize: 13, color: Color(0xFF333333)),
            ),
          ],
        ),
      ],
    );
  }
}

// ============================================================
// 统计数字项
// ============================================================
class _StatItem extends StatelessWidget {
  const _StatItem({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1A1A1A),
          ),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Color(0xFF999999)),
        ),
      ],
    );
  }
}

// ============================================================
// 操作按钮区（上下架 + 删除）
// ============================================================
class _ActionButtons extends StatefulWidget {
  const _ActionButtons({required this.deal, required this.ref});

  final MerchantDeal deal;
  final WidgetRef ref;

  @override
  State<_ActionButtons> createState() => _ActionButtonsState();
}

class _ActionButtonsState extends State<_ActionButtons> {
  bool _isLoading = false;

  Future<void> _toggleStatus(bool activate) async {
    // 显示确认对话框
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(activate ? 'Activate Deal?' : 'Deactivate Deal?'),
        content: Text(
          activate
              ? 'This deal will be visible to customers and available for purchase.'
              : 'This deal will be hidden from customers. Customers who already purchased can still use their vouchers.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF999999))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: activate ? const Color(0xFF4CAF50) : const Color(0xFF757575),
              foregroundColor: Colors.white,
            ),
            child: Text(activate ? 'Activate' : 'Deactivate'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);
    try {
      await widget.ref
          .read(dealsProvider.notifier)
          .toggleDealStatus(widget.deal.id, activate);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            activate ? 'Deal activated successfully!' : 'Deal deactivated.',
          ),
          backgroundColor: activate
              ? const Color(0xFF4CAF50)
              : const Color(0xFF757575),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed: $e'),
          backgroundColor: const Color(0xFFE53935),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteDeal() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Deal?'),
        content: const Text(
          'This action cannot be undone. The deal will be permanently removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF999999))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE53935),
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);
    try {
      await widget.ref
          .read(dealsProvider.notifier)
          .deleteDeal(widget.deal.id);

      if (!mounted) return;
      context.pop(); // 删除成功后返回列表
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete: $e'),
          backgroundColor: const Color(0xFFE53935),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final deal = widget.deal;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 上架按钮（仅 inactive 状态显示）
        if (deal.canActivate)
          ElevatedButton.icon(
            onPressed: _isLoading ? null : () => _toggleStatus(true),
            icon: _isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.rocket_launch_outlined, size: 18),
            label: const Text(
              'Activate Deal',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4CAF50),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),

        // 下架按钮（仅 active 状态显示）
        if (deal.canDeactivate) ...[
          ElevatedButton.icon(
            onPressed: _isLoading ? null : () => _toggleStatus(false),
            icon: _isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.pause_circle_outline, size: 18),
            label: const Text(
              'Deactivate Deal',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF757575),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ],

        // 删除按钮（仅 inactive 状态显示）
        if (deal.dealStatus == DealStatus.inactive) ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _isLoading ? null : _deleteDeal,
            icon: const Icon(Icons.delete_outline_rounded, size: 18),
            label: const Text(
              'Delete Deal',
              style: TextStyle(fontSize: 15),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFE53935),
              side: const BorderSide(color: Color(0xFFE53935)),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

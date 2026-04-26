// Deal详情页面
// 展示 Deal 完整信息，包含审核状态、拒绝原因、编辑/上下架操作

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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
              onPressed: () async {
                // brand deal 权限检查：创建者或 brand owner/admin 可编辑
                if (deal.applicableMerchantIds != null &&
                    deal.applicableMerchantIds!.isNotEmpty) {
                  final supabase = Supabase.instance.client;
                  final user = supabase.auth.currentUser;
                  if (user != null) {
                    final merchant = await supabase
                        .from('merchants')
                        .select('id, brand_id')
                        .eq('user_id', user.id)
                        .maybeSingle();
                    final isCreator = merchant != null &&
                        merchant['id'] == deal.merchantId;
                    // 非创建者：检查是否为同品牌的 owner/admin
                    var isBrandAdmin = false;
                    if (!isCreator && merchant != null && merchant['brand_id'] != null) {
                      final admin = await supabase
                          .from('brand_admins')
                          .select('role')
                          .eq('brand_id', merchant['brand_id'] as String)
                          .eq('user_id', user.id)
                          .maybeSingle();
                      isBrandAdmin = admin != null;
                    }
                    if (!isCreator && !isBrandAdmin) {
                      if (!context.mounted) return;
                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Cannot Edit'),
                          content: const Text(
                            'This is a brand deal. Only the brand owner or manager can edit it.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text('OK'),
                            ),
                          ],
                        ),
                      );
                      return;
                    }
                  }
                }
                if (!context.mounted) return;
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
                      DealStatusBadge(status: deal.isExpiredByDate ? DealStatus.expired : deal.dealStatus),
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
                  Flexible(
                    child: Column(
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
                  ),
                  const SizedBox(width: 24),
                  Flexible(
                    child: Column(
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
                    label: 'Allow Stacking',
                    value: deal.isStackable ? 'Yes' : 'No',
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

                  // 使用须知附带的图片
                  if (deal.usageNoteImages.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const Divider(height: 1, color: Color(0xFFEEEEEE)),
                    const SizedBox(height: 12),
                    const Row(
                      children: [
                        Icon(Icons.photo_library_outlined, size: 16, color: Color(0xFF999999)),
                        SizedBox(width: 6),
                        Text('Attached Photos', style: TextStyle(fontSize: 13, color: Color(0xFF999999))),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 100,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: deal.usageNoteImages.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (context, index) {
                          final url = deal.usageNoteImages[index];
                          return GestureDetector(
                            onTap: () => showDialog(
                              context: context,
                              builder: (_) => _FullScreenImageViewer(
                                images: deal.usageNoteImages,
                                initialIndex: index,
                              ),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: CachedNetworkImage(
                                imageUrl: url,
                                width: 100,
                                height: 100,
                                fit: BoxFit.cover,
                                placeholder: (_, __) => Container(
                                  width: 100, height: 100,
                                  color: const Color(0xFFF5F5F5),
                                  child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                                ),
                                errorWidget: (_, __, ___) => Container(
                                  width: 100, height: 100,
                                  color: const Color(0xFFF5F5F5),
                                  child: const Icon(Icons.broken_image, color: Color(0xFFCCCCCC)),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),

            // 门店审批状态卡片（仅多门店 brand deal 显示）
            if (deal.applicableMerchantIds != null &&
                deal.applicableMerchantIds!.isNotEmpty) ...[
              _StoreStatusCard(dealId: deal.id, creatorMerchantId: deal.merchantId),
              const SizedBox(height: 12),
            ],

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
                ? 'Your deal is being reviewed by the Crunchy Plum team. This usually takes 24-48 hours. The previous version (if any) continues to show to customers.'
                : 'Your deal was not approved. Please edit and resubmit.',
            style: TextStyle(
              fontSize: 13,
              color: isPending
                  ? const Color(0xFFF9A825)
                  : const Color(0xFFE53935),
              height: 1.4,
            ),
          ),
          // 驳回历史记录（从 deal_rejections 表异步加载）
          if (!isPending) ...[
            const SizedBox(height: 8),
            FutureBuilder<List<Map<String, dynamic>>>(
              future: Supabase.instance.client
                  .from('deal_rejections')
                  .select('id, reason, created_at')
                  .eq('deal_id', deal.id)
                  .order('created_at', ascending: false),
              builder: (context, snapshot) {
                final records = snapshot.data ?? [];
                // 无历史记录时降级显示 reviewNotes
                if (records.isEmpty && deal.reviewNotes != null && deal.reviewNotes!.isNotEmpty) {
                  return Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Rejection Reason:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFE53935))),
                        const SizedBox(height: 4),
                        Text(deal.reviewNotes!, style: const TextStyle(fontSize: 13, color: Color(0xFF555555), height: 1.4)),
                      ],
                    ),
                  );
                }
                if (records.isEmpty) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: records.map((r) {
                    final reason = r['reason'] as String? ?? '';
                    final createdAt = r['created_at'] != null
                        ? DateTime.parse(r['created_at'] as String).toLocal()
                        : null;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Rejection Reason:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFE53935))),
                              if (createdAt != null)
                                Text(
                                  '${createdAt.month}/${createdAt.day}/${createdAt.year} ${createdAt.hour}:${createdAt.minute.toString().padLeft(2, '0')}',
                                  style: const TextStyle(fontSize: 11, color: Color(0xFF999999)),
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(reason, style: const TextStyle(fontSize: 13, color: Color(0xFF555555), height: 1.4)),
                        ],
                      ),
                    );
                  }).toList(),
                );
              },
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
        // Expanded 确保 Column 内的长文本（如可用日期、使用须知）不超出 Row 宽度
        Expanded(
          child: Column(
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

  // 判断当前用户是否为 deal 的创建者
  Future<bool> _isMyDeal() async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user == null) return false;
    final merchant = await supabase
        .from('merchants')
        .select('id')
        .eq('user_id', user.id)
        .maybeSingle();
    if (merchant == null) return false;
    return merchant['id'] == widget.deal.merchantId;
  }

  // 非创建者门店：通过 store-confirm decline 退出 deal
  Future<void> _withdrawFromDeal() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Withdraw from this Deal?'),
        content: const Text(
          'Your store will no longer participate in this deal. You can reconsider and rejoin later from the deal confirmation page.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF999999))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF757575),
              foregroundColor: Colors.white,
            ),
            child: const Text('Withdraw'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);
    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;
      final merchant = await supabase
          .from('merchants')
          .select('id')
          .eq('user_id', user!.id)
          .maybeSingle();
      final merchantId = merchant!['id'] as String;

      // 调用 store-confirm decline（必须用 PATCH 方法）
      final response = await supabase.functions.invoke(
        'merchant-deals/${widget.deal.id}/store-confirm',
        method: HttpMethod.patch,
        body: {'action': 'decline'},
        headers: {'X-Merchant-Id': merchantId},
      );

      if (response.status != 200) {
        final data = response.data;
        String msg = 'Request failed (${response.status})';
        if (data is Map && data.containsKey('error')) {
          msg = data['error'] as String;
        }
        throw Exception(msg);
      }

      if (!mounted) return;
      // 刷新 deals 列表
      widget.ref.invalidate(dealsProvider);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You have withdrawn from this deal.'),
          backgroundColor: Color(0xFF757575),
          behavior: SnackBarBehavior.floating,
        ),
      );
      // 返回上一页
      if (mounted) context.pop();
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

  Future<void> _toggleStatus(bool activate) async {
    // 非创建者门店尝试 deactivate 时，改用 withdraw 流程
    if (!activate) {
      final myDeal = await _isMyDeal();
      if (!myDeal) {
        return _withdrawFromDeal();
      }
    }

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
            key: const ValueKey('deal_detail_toggle_active_btn'),
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
            key: const ValueKey('deal_detail_toggle_active_btn'),
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
            key: const ValueKey('deal_detail_delete_btn'),
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

// ============================================================
// 门店审批状态卡片（brand multi-store deal）
// ============================================================
class _StoreStatusCard extends StatefulWidget {
  const _StoreStatusCard({required this.dealId, required this.creatorMerchantId});

  final String dealId;
  final String creatorMerchantId;

  @override
  State<_StoreStatusCard> createState() => _StoreStatusCardState();
}

class _StoreStatusCardState extends State<_StoreStatusCard> {
  List<Map<String, dynamic>>? _stores;
  bool _loading = true;
  bool _hasPermission = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadStoreStatus();
  }

  // 查询 deal_applicable_stores 获取各门店审批状态
  Future<void> _loadStoreStatus() async {
    try {
      // 权限检查：deal 创建者或 brand owner/admin 可查看
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;
      if (user != null) {
        final merchant = await supabase
            .from('merchants')
            .select('id, brand_id')
            .eq('user_id', user.id)
            .maybeSingle();
        final isCreator = merchant != null &&
            merchant['id'] == widget.creatorMerchantId;
        var isBrandAdmin = false;
        if (!isCreator && merchant != null && merchant['brand_id'] != null) {
          final admin = await supabase
              .from('brand_admins')
              .select('role')
              .eq('brand_id', merchant['brand_id'] as String)
              .eq('user_id', user.id)
              .maybeSingle();
          isBrandAdmin = admin != null;
        }
        if (!isCreator && !isBrandAdmin) {
          setState(() {
            _hasPermission = false;
            _loading = false;
          });
          return;
        }
      }

      final data = await supabase
          .from('deal_applicable_stores')
          .select('store_id, status, confirmed_at, merchants!deal_applicable_stores_store_id_fkey(name, logo_url)')
          .eq('deal_id', widget.dealId)
          .order('created_at');
      setState(() {
        _stores = List<Map<String, dynamic>>.from(data);
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // 非 brand owner/manager 不显示
    if (!_hasPermission) return const SizedBox.shrink();

    if (_loading) {
      return const _InfoCard(
        title: 'Store Status',
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: CircularProgressIndicator(color: Color(0xFFFF6B35)),
          ),
        ),
      );
    }

    if (_error != null) {
      return _InfoCard(
        title: 'Store Status',
        child: Text('Failed to load: $_error',
            style: const TextStyle(color: Color(0xFF999999), fontSize: 13)),
      );
    }

    final stores = _stores ?? [];
    if (stores.isEmpty) {
      return const _InfoCard(
        title: 'Store Status',
        child: Text('No stores assigned.',
            style: TextStyle(color: Color(0xFF999999), fontSize: 13)),
      );
    }

    // 统计各状态数量
    int activeCount = 0, pendingCount = 0, declinedCount = 0, removedCount = 0;
    for (final s in stores) {
      switch (s['status'] as String? ?? '') {
        case 'active':
          activeCount++;
        case 'pending_store_confirmation':
          pendingCount++;
        case 'declined':
          declinedCount++;
        case 'removed':
          removedCount++;
      }
    }

    return _InfoCard(
      title: 'Store Status',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 状态汇总标签
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              if (activeCount > 0)
                _StatusChip(label: 'Approved', count: activeCount, color: const Color(0xFF4CAF50)),
              if (pendingCount > 0)
                _StatusChip(label: 'Pending', count: pendingCount, color: const Color(0xFFF9A825)),
              if (declinedCount > 0)
                _StatusChip(label: 'Declined', count: declinedCount, color: const Color(0xFFE53935)),
              if (removedCount > 0)
                _StatusChip(label: 'Removed', count: removedCount, color: const Color(0xFF757575)),
            ],
          ),
          const SizedBox(height: 12),
          // 门店列表
          ...stores.map((s) {
            final merchant = s['merchants'] as Map<String, dynamic>? ?? {};
            final name = merchant['name'] as String? ?? 'Unknown Store';
            final status = s['status'] as String? ?? '';
            final confirmedAt = s['confirmed_at'] != null
                ? DateTime.parse(s['confirmed_at'] as String).toLocal()
                : null;

            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  // 状态图标
                  _statusIcon(status),
                  const SizedBox(width: 10),
                  // 门店名
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF333333),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (confirmedAt != null)
                          Text(
                            '${confirmedAt.month}/${confirmedAt.day}/${confirmedAt.year}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF999999),
                            ),
                          ),
                      ],
                    ),
                  ),
                  // 状态标签
                  _statusBadge(status),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _statusIcon(String status) {
    return switch (status) {
      'active' => const Icon(Icons.check_circle, size: 20, color: Color(0xFF4CAF50)),
      'pending_store_confirmation' => const Icon(Icons.hourglass_top_rounded, size: 20, color: Color(0xFFF9A825)),
      'declined' => const Icon(Icons.cancel, size: 20, color: Color(0xFFE53935)),
      'removed' => const Icon(Icons.remove_circle, size: 20, color: Color(0xFF757575)),
      _ => const Icon(Icons.help_outline, size: 20, color: Color(0xFF999999)),
    };
  }

  Widget _statusBadge(String status) {
    final (label, color) = switch (status) {
      'active' => ('Approved', const Color(0xFF4CAF50)),
      'pending_store_confirmation' => ('Pending', const Color(0xFFF9A825)),
      'declined' => ('Declined', const Color(0xFFE53935)),
      'removed' => ('Removed', const Color(0xFF757575)),
      _ => ('Unknown', const Color(0xFF999999)),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

// ── 状态汇总标签 ─────────────────────────────────────────────

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.count,
    required this.color,
  });

  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$label: $count',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

// ============================================================
// 全屏图片查看器（支持左右滑动）
// ============================================================
class _FullScreenImageViewer extends StatelessWidget {
  const _FullScreenImageViewer({
    required this.images,
    required this.initialIndex,
  });

  final List<String> images;
  final int initialIndex;

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      backgroundColor: Colors.black,
      child: Stack(
        children: [
          // 图片 PageView
          PageView.builder(
            controller: PageController(initialPage: initialIndex),
            itemCount: images.length,
            itemBuilder: (_, index) => InteractiveViewer(
              child: Center(
                child: CachedNetworkImage(
                  imageUrl: images[index],
                  fit: BoxFit.contain,
                  placeholder: (c, u) => const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
                  errorWidget: (c, u, e) => const Icon(
                    Icons.broken_image,
                    color: Colors.white54,
                    size: 48,
                  ),
                ),
              ),
            ),
          ),
          // 关闭按钮
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            right: 12,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 28),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    );
  }
}

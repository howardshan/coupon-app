// 待评价页面 — 显示已使用但还没写评价的券
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../auth/domain/providers/auth_provider.dart';

// 待评价的券数据
class _ReviewableItem {
  final String couponId;
  final String dealId;
  final String dealTitle;
  final String? dealImageUrl;
  final String? merchantId;
  final String? merchantName;
  final DateTime? usedAt;

  _ReviewableItem({
    required this.couponId,
    required this.dealId,
    required this.dealTitle,
    this.dealImageUrl,
    this.merchantId,
    this.merchantName,
    this.usedAt,
  });
}

// 查询已使用但未评价的券
final toReviewProvider = FutureProvider<List<_ReviewableItem>>((ref) async {
  final user = await ref.watch(currentUserProvider.future);
  if (user == null) return [];

  final client = Supabase.instance.client;

  // 查询已使用的券（同时获取 merchant_id 用于跳转评价页面）
  final usedCoupons = await client
      .from('coupons')
      .select('id, deal_id, used_at, deals(title, image_urls, merchant_id, merchants(id, name))')
      .eq('user_id', user.id)
      .eq('status', 'used')
      .order('used_at', ascending: false);

  // 查询该用户已评价的 deal_ids
  final reviews = await client
      .from('reviews')
      .select('deal_id')
      .eq('user_id', user.id);
  final reviewedDealIds = (reviews as List)
      .map((r) => r['deal_id'] as String)
      .toSet();

  // 过滤出未评价的
  final items = <_ReviewableItem>[];
  for (final c in (usedCoupons as List)) {
    final dealId = c['deal_id'] as String? ?? '';
    if (reviewedDealIds.contains(dealId)) continue;

    final deals = c['deals'] as Map<String, dynamic>?;
    final merchants = deals?['merchants'] as Map<String, dynamic>?;
    final imageUrls = deals?['image_urls'] as List?;
    // merchant_id 优先从 deals 直接字段取，其次从嵌套 merchants 对象取
    final merchantId = (deals?['merchant_id'] as String?)
        ?? (merchants?['id'] as String?);

    items.add(_ReviewableItem(
      couponId: c['id'] as String? ?? '',
      dealId: dealId,
      dealTitle: deals?['title'] as String? ?? 'Deal',
      dealImageUrl: (imageUrls != null && imageUrls.isNotEmpty)
          ? imageUrls.first as String?
          : null,
      merchantId: merchantId,
      merchantName: merchants?['name'] as String?,
      usedAt: c['used_at'] != null
          ? DateTime.tryParse(c['used_at'] as String)
          : null,
    ));
  }

  // 按 deal 去重（同 deal 多张券只显示一次）
  final seen = <String>{};
  return items.where((i) => seen.add(i.dealId)).toList();
});

class ToReviewScreen extends ConsumerWidget {
  const ToReviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemsAsync = ref.watch(toReviewProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('To Review')),
      body: itemsAsync.when(
        data: (items) {
          if (items.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.rate_review_outlined, size: 72, color: AppColors.textHint),
                  SizedBox(height: 16),
                  Text('No deals to review', style: TextStyle(color: AppColors.textSecondary)),
                  SizedBox(height: 8),
                  Text(
                    'Use your vouchers first,\nthen come back to write reviews.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: AppColors.textHint),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(toReviewProvider),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (_, i) => _ReviewCard(item: items[i]),
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Failed to load', style: TextStyle(color: AppColors.textSecondary)),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () => ref.invalidate(toReviewProvider),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// 单张待评价卡片
class _ReviewCard extends StatelessWidget {
  final _ReviewableItem item;

  const _ReviewCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('MMM d, yyyy');

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
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            // Deal 图片
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: item.dealImageUrl != null
                  ? Image.network(
                      item.dealImageUrl!,
                      width: 64,
                      height: 64,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _placeholder(),
                    )
                  : _placeholder(),
            ),
            const SizedBox(width: 12),
            // 信息
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.dealTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  if (item.merchantName != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      item.merchantName!,
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ],
                  if (item.usedAt != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Used ${dateFmt.format(item.usedAt!.toLocal())}',
                      style: const TextStyle(fontSize: 11, color: AppColors.textHint),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            // 写评价按钮
            ElevatedButton(
              onPressed: () {
                // couponId は order_items テーブルの ID ではないため orderItemId として渡せない
                // merchantId のみ渡す（orderItemId は省略）
                final merchantId = item.merchantId ?? '';
                context.push('/review/${item.dealId}?merchantId=$merchantId');
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                minimumSize: Size.zero,
              ),
              child: const Text('Review', style: TextStyle(fontSize: 13)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(Icons.restaurant, size: 24, color: AppColors.textHint),
    );
  }
}

// 待评价列表：已核销且该 deal 尚未评价（按 deal 去重，与 DB unique(deal_id,user_id) 一致）

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../shared/providers/supabase_provider.dart';
import '../../../auth/domain/providers/auth_provider.dart';

/// 单条待评价（每个 deal 最多一行）
class PendingReviewItem {
  final String couponId;
  final String dealId;
  final String dealTitle;
  final String? dealImageUrl;
  final String? merchantId;
  final String? merchantName;
  final DateTime? usedAt;

  const PendingReviewItem({
    required this.couponId,
    required this.dealId,
    required this.dealTitle,
    this.dealImageUrl,
    this.merchantId,
    this.merchantName,
    this.usedAt,
  });
}

/// 已使用但未写评价的 deal 列表（按 deal 去重）
final toReviewProvider = FutureProvider<List<PendingReviewItem>>((ref) async {
  final user = await ref.watch(currentUserProvider.future);
  if (user == null) return [];

  final client = ref.watch(supabaseClientProvider);

  final usedCoupons = await client
      .from('coupons')
      .select(
        'id, deal_id, used_at, deals(title, image_urls, merchant_id, merchants(id, name))',
      )
      .eq('user_id', user.id)
      .eq('status', 'used')
      .order('used_at', ascending: false);

  final reviews = await client.from('reviews').select('deal_id').eq('user_id', user.id);
  final reviewedDealIds = (reviews as List)
      .map((r) => r['deal_id'] as String)
      .toSet();

  final items = <PendingReviewItem>[];
  for (final c in (usedCoupons as List)) {
    final dealId = c['deal_id'] as String? ?? '';
    if (reviewedDealIds.contains(dealId)) continue;

    final deals = c['deals'] as Map<String, dynamic>?;
    final merchants = deals?['merchants'] as Map<String, dynamic>?;
    final imageUrls = deals?['image_urls'] as List?;
    final merchantId = (deals?['merchant_id'] as String?) ??
        (merchants?['id'] as String?);

    items.add(PendingReviewItem(
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

  final seen = <String>{};
  return items.where((i) => seen.add(i.dealId)).toList();
});

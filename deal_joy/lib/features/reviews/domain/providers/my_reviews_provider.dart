// 当前用户已提交的评价列表（用于券列表/详情/「我的评价」聚合页）

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../shared/providers/supabase_provider.dart';
import '../../../deals/data/models/review_model.dart';
import '../../../orders/data/models/coupon_model.dart';

/// 拉取当前登录用户未删除的评价（含 deal 标题）
final myWrittenReviewsProvider = FutureProvider<List<ReviewModel>>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  final userId = client.auth.currentUser?.id;
  if (userId == null) return [];

  final data = await client
      .from('reviews')
      .select(
        'id, deal_id, order_item_id, merchant_id, rating_overall, rating, '
        'comment, created_at, updated_at, deals(title)',
      )
      .eq('user_id', userId)
      .eq('is_deleted', false)
      .order('updated_at', ascending: false);

  return (data as List)
      .map((e) => ReviewModel.fromJson(e as Map<String, dynamic>))
      .toList();
});

/// 将某张券与「我的评价」列表匹配：优先 order_item_id，否则 deal 唯一时回退
ReviewModel? matchWrittenReviewForCoupon(
  CouponModel coupon,
  List<ReviewModel> myReviews,
) {
  final oid = coupon.orderItemId;
  if (oid != null && oid.isNotEmpty) {
    for (final r in myReviews) {
      if (r.orderItemId == oid) return r;
    }
  }

  final sameDeal =
      myReviews.where((r) => r.dealId == coupon.dealId).toList();
  if (sameDeal.isEmpty) return null;
  if (sameDeal.length == 1) return sameDeal.first;

  // 同一 deal 多次购买且无 order_item 关联时无法区分，不自动匹配
  return null;
}

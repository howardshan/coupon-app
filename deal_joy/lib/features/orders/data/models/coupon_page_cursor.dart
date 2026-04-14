// My Coupons 游标分页：与 RPC fetch_my_coupon_ids_page 对齐（created_at DESC, id DESC）

import 'coupon_model.dart';

/// 下一页请求游标（上一页最后一条券）
class CouponKeysetCursor {
  final DateTime createdAt;
  final String id;

  const CouponKeysetCursor({
    required this.createdAt,
    required this.id,
  });
}

/// 单页拉取结果
class CouponPageFetchResult {
  final List<CouponModel> items;
  final CouponKeysetCursor? nextCursor;
  final bool hasMore;

  const CouponPageFetchResult({
    required this.items,
    required this.nextCursor,
    required this.hasMore,
  });
}

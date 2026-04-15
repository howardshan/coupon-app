import '../../../after_sales/data/models/after_sales_request_model.dart';
import '../../data/models/order_item_model.dart';

/// 同一 coupon 仅保留最新一条售后（按 createdAt），与订单详情 / voucher 详情共用
Map<String, AfterSalesRequestModel> latestAfterSalesByCouponId(
  List<AfterSalesRequestModel> list,
) {
  final map = <String, AfterSalesRequestModel>{};
  for (final r in list) {
    final cid = r.couponId.trim();
    if (cid.isEmpty) continue;
    final existing = map[cid];
    if (existing == null || r.createdAt.isAfter(existing.createdAt)) {
      map[cid] = r;
    }
  }
  return map;
}

/// 已有售后记录时隐藏 Refund，避免与 After-sales 入口重复
bool showRefundButtonConsideringAfterSales(
  OrderItemModel item,
  Map<String, AfterSalesRequestModel> afterSalesByCoupon,
) {
  if (!item.showRefundRequest) return false;
  final cid = item.couponId;
  if (cid != null && cid.isNotEmpty && afterSalesByCoupon.containsKey(cid)) {
    return false;
  }
  return true;
}

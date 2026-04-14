// 按「列表行」聚合多笔订单下同一 deal 的券，供 Voucher Detail 展示完整 order_items

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/app_exception.dart';
import '../../../../shared/providers/supabase_provider.dart';
import '../../data/models/order_detail_model.dart';
import '../../data/models/order_item_model.dart';
import 'orders_provider.dart';

/// Riverpod family 缓存键：`dealId|itemId1,itemId2,...`（itemId 已排序）
String aggregatedDealVoucherCacheKey(String dealId, Set<String> orderItemIds) {
  final sorted = orderItemIds.toList()..sort();
  return '$dealId|${sorted.join(',')}';
}

/// 将多笔订单中、限定 order_item id 的条目合并为一份合成 [OrderDetailModel]
OrderDetailModel buildSyntheticAggregatedOrderDetail({
  required String dealId,
  required List<OrderItemModel> items,
}) {
  if (items.isEmpty) {
    throw ArgumentError.value(items, 'items', 'must be non-empty');
  }
  final sorted = List<OrderItemModel>.from(items)
    ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  final first = sorted.first;
  final totalPaid = sorted.fold<double>(
    0,
    (s, i) => s + i.unitPrice + i.serviceFee,
  );
  final qty = sorted.length;
  final avgUnit = qty > 0 ? totalPaid / qty : 0.0;
  var earliestCreated = sorted.first.createdAt;
  for (final i in sorted.skip(1)) {
    if (i.createdAt.isBefore(earliestCreated)) earliestCreated = i.createdAt;
  }

  return OrderDetailModel(
    id: 'aggregate:$dealId',
    orderNumber: 'Multiple orders',
    status: 'unused',
    dealId: dealId,
    dealTitle: first.dealTitle,
    dealOriginalPrice: first.dealOriginalPrice ?? 0,
    dealDiscountPrice: first.unitPrice,
    dealImageUrl: first.dealImageUrl,
    merchantName: first.merchantName ?? first.purchasedMerchantName,
    quantity: qty,
    unitPrice: avgUnit,
    totalAmount: totalPaid,
    paymentIntentIdMasked: null,
    storeCreditUsed: 0,
    timeline: const OrderTimeline(events: []),
    items: sorted,
    createdAt: earliestCreated,
    couponExpiresAt: first.couponExpiresAt,
    couponId: first.couponId,
    couponCode: first.couponCode,
    couponStatus: first.couponStatus,
  );
}

/// 根据「dealId + 列表行内的 order_item id 集合」拉取多笔订单详情并合并
final aggregatedDealVoucherDetailProvider =
    FutureProvider.autoDispose.family<OrderDetailModel, String>(
        (ref, cacheKey) async {
  final pipe = cacheKey.indexOf('|');
  if (pipe <= 0) {
    throw const AppException('Invalid aggregate voucher request.');
  }
  final dealId = cacheKey.substring(0, pipe);
  final idsPart = cacheKey.substring(pipe + 1);
  final orderItemIds = idsPart
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toSet();
  if (dealId.isEmpty || orderItemIds.isEmpty) {
    throw const AppException('Invalid aggregate voucher request.');
  }

  // 不拉取全量券：仅按 deal + order_item id 查 order_id
  final client = ref.watch(supabaseClientProvider);
  final idList = orderItemIds.toList();
  final rows = await client
      .from('coupons')
      .select('order_id')
      .eq('deal_id', dealId)
      .inFilter('order_item_id', idList);
  final orderIds = (rows as List)
      .map((e) => (e as Map<String, dynamic>)['order_id'] as String)
      .toSet()
      .toList();
  if (orderIds.isEmpty) {
    throw const AppException('No matching coupons for this selection.');
  }
  final repo = ref.read(ordersRepositoryProvider);
  final details = await Future.wait(
    orderIds.map(repo.fetchOrderDetailFromApi),
  );

  final seen = <String>{};
  final merged = <OrderItemModel>[];
  for (final d in details) {
    for (final item in d.items) {
      if (item.dealId != dealId) continue;
      if (!orderItemIds.contains(item.id)) continue;
      if (seen.add(item.id)) merged.add(item);
    }
  }

  if (merged.isEmpty) {
    throw const AppException('No order items found for this deal.');
  }

  return buildSyntheticAggregatedOrderDetail(dealId: dealId, items: merged);
});

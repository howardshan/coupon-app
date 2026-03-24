import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../shared/providers/supabase_provider.dart';
import '../../../auth/domain/providers/auth_provider.dart';
import '../../data/models/order_detail_model.dart';
import '../../data/models/order_model.dart';
import '../../data/repositories/orders_repository.dart';

final ordersRepositoryProvider = Provider<OrdersRepository>((ref) {
  return OrdersRepository(ref.watch(supabaseClientProvider));
});

final userOrdersProvider = FutureProvider<List<OrderModel>>((ref) async {
  final user = await ref.watch(currentUserProvider.future);
  if (user == null) return [];
  return ref.watch(ordersRepositoryProvider).fetchUserOrders(user.id);
});

final orderDetailProvider = FutureProvider.family<OrderModel, String>((
  ref,
  orderId,
) {
  return ref.watch(ordersRepositoryProvider).fetchOrderById(orderId);
});

/// 订单详情（来自 user-order-detail Edge Function，含时间线 / 支付状态 / 券码等）
/// 使用 autoDispose：每次离开详情页后清除缓存，再次进入时重新请求最新数据
/// 避免券状态变更后（如商家扫码）详情页仍显示旧缓存的问题
final userOrderDetailProvider =
    FutureProvider.autoDispose.family<OrderDetailModel, String>((ref, orderId) {
  return ref.watch(ordersRepositoryProvider).fetchOrderDetailFromApi(orderId);
});

final couponDataProvider = FutureProvider.family<Map<String, dynamic>, String>((
  ref,
  couponId,
) {
  return ref.watch(ordersRepositoryProvider).fetchCoupon(couponId);
});

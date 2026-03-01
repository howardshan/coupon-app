import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../shared/providers/supabase_provider.dart';
import '../../../auth/domain/providers/auth_provider.dart';
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

final orderDetailProvider =
    FutureProvider.family<OrderModel, String>((ref, orderId) {
  return ref.watch(ordersRepositoryProvider).fetchOrderById(orderId);
});

final couponDataProvider =
    FutureProvider.family<Map<String, dynamic>, String>((ref, couponId) {
  return ref.watch(ordersRepositoryProvider).fetchCoupon(couponId);
});

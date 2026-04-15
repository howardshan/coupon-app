import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../shared/providers/supabase_provider.dart';
import '../../data/models/after_sales_request_model.dart';
import '../../data/repositories/after_sales_repository.dart';

final afterSalesRepositoryProvider = Provider<AfterSalesRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  final repo = AfterSalesRepository(client);
  ref.onDispose(repo.dispose);
  return repo;
});

/// 表单提交成功瞬间写入，避免 GET 列表短暂为空时时间线仍显示空态
final afterSalesOptimisticProvider =
    StateProvider.family<AfterSalesRequestModel?, String>((ref, orderId) => null);

/// 优先使用服务端列表；列表尚无记录时用 [afterSalesOptimisticProvider]
final afterSalesRequestProvider =
    FutureProvider.family<AfterSalesRequestModel?, String>((ref, orderId) async {
  final optimistic = ref.watch(afterSalesOptimisticProvider(orderId));
  final repo = ref.watch(afterSalesRepositoryProvider);
  final fetched = await repo.fetchLatestForOrder(orderId);
  if (fetched != null) {
    // 避免 build 阶段交叉写 provider，清空乐观缓存留到下一事件循环
    if (optimistic != null) {
      Future.microtask(() {
        ref.read(afterSalesOptimisticProvider(orderId).notifier).state = null;
      });
    }
    return fetched;
  }
  return optimistic;
});

final afterSalesListProvider = FutureProvider.family<List<AfterSalesRequestModel>, String?>((ref, orderId) {
  return ref.watch(afterSalesRepositoryProvider).fetchRequests(orderId: orderId);
});

final supabaseSessionProvider = Provider<Session?>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return client.auth.currentSession;
});

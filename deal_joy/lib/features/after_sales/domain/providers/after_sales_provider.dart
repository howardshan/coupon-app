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
/// [AutoDispose]：离开页面后释放缓存，再次进入会重新拉取（与后台裁决等外部变更对齐）
final afterSalesRequestProvider =
    AutoDisposeFutureProvider.family<AfterSalesRequestModel?, String>((ref, orderId) async {
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

/// [AutoDispose]：无监听者时清缓存，避免长期停留在旧状态
final afterSalesListProvider =
    AutoDisposeFutureProvider.family<List<AfterSalesRequestModel>, String?>((ref, orderId) {
  return ref.watch(afterSalesRepositoryProvider).fetchRequests(orderId: orderId);
});

/// 将全量售后列表按 `order_id` 分组，供订单列表卡片展示（与 [afterSalesListProvider] null 共用一次请求）
final userAfterSalesByOrderIdProvider =
    Provider<AsyncValue<Map<String, List<AfterSalesRequestModel>>>>((ref) {
  final base = ref.watch(afterSalesListProvider(null));
  return base.when(
    data: (list) {
      final map = <String, List<AfterSalesRequestModel>>{};
      for (final r in list) {
        final oid = r.orderId;
        if (oid.isEmpty) continue;
        map.putIfAbsent(oid, () => []).add(r);
      }
      for (final v in map.values) {
        v.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      }
      return AsyncValue.data(map);
    },
    loading: () => const AsyncValue.loading(),
    error: AsyncValue.error,
  );
});

final supabaseSessionProvider = Provider<Session?>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return client.auth.currentSession;
});

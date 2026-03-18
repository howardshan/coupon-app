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

final afterSalesRequestProvider = FutureProvider.family<AfterSalesRequestModel?, String>((ref, orderId) {
  return ref.watch(afterSalesRepositoryProvider).fetchLatestForOrder(orderId);
});

final afterSalesListProvider = FutureProvider.family<List<AfterSalesRequestModel>, String?>((ref, orderId) {
  return ref.watch(afterSalesRepositoryProvider).fetchRequests(orderId: orderId);
});

final supabaseSessionProvider = Provider<Session?>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return client.auth.currentSession;
});

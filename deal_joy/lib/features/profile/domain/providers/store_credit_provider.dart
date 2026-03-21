import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../shared/providers/supabase_provider.dart';
import '../../../auth/domain/providers/auth_provider.dart';
import '../../data/models/store_credit_model.dart';
import '../../data/repositories/store_credit_repository.dart';

// Repository Provider
final storeCreditRepositoryProvider = Provider<StoreCreditRepository>((ref) {
  return StoreCreditRepository(ref.watch(supabaseClientProvider));
});

/// 查询当前用户余额
final storeCreditBalanceProvider = FutureProvider<StoreCredit>((ref) async {
  final userAsync = await ref.watch(currentUserProvider.future);
  final userId = userAsync?.id ?? '';
  if (userId.isEmpty) return StoreCredit.zero('');
  return ref.read(storeCreditRepositoryProvider).fetchBalance(userId);
});

/// 查询当前用户流水记录
final storeCreditTransactionsProvider =
    FutureProvider<List<StoreCreditTransaction>>((ref) async {
  final userAsync = await ref.watch(currentUserProvider.future);
  final userId = userAsync?.id ?? '';
  if (userId.isEmpty) return [];
  return ref.read(storeCreditRepositoryProvider).fetchTransactions(userId);
});

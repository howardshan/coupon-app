import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../shared/providers/supabase_provider.dart';
import '../../data/models/saved_card_model.dart';
import '../../data/repositories/payment_methods_repository.dart';

// ── Repository Provider ──────────────────────────────────────────────────────
final paymentMethodsRepositoryProvider = Provider<PaymentMethodsRepository>((ref) {
  return PaymentMethodsRepository(ref.watch(supabaseClientProvider));
});

// ── AsyncNotifier：管理已保存卡片列表 ──────────────────────────────────────────
class PaymentMethodsNotifier extends AsyncNotifier<List<SavedCard>> {
  PaymentMethodsRepository get _repo =>
      ref.read(paymentMethodsRepositoryProvider);

  @override
  Future<List<SavedCard>> build() async {
    return _repo.fetchSavedCards();
  }

  /// 刷新卡片列表
  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _repo.fetchSavedCards());
  }

  /// 设置默认卡片，成功后刷新列表
  Future<void> setDefault(String paymentMethodId) async {
    await _repo.setDefaultCard(paymentMethodId);
    await refresh();
  }

  /// 删除卡片，成功后刷新列表
  Future<void> deleteCard(String paymentMethodId) async {
    await _repo.deleteCard(paymentMethodId);
    await refresh();
  }
}

final paymentMethodsProvider =
    AsyncNotifierProvider<PaymentMethodsNotifier, List<SavedCard>>(
  PaymentMethodsNotifier.new,
);

// ── SetupIntent Provider（用于添加新卡片）────────────────────────────────────
final setupIntentProvider = FutureProvider<Map<String, String>>((ref) async {
  return ref.read(paymentMethodsRepositoryProvider).createSetupIntent();
});

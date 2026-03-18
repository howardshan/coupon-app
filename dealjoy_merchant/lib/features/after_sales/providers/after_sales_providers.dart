import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../merchant_auth/providers/merchant_auth_provider.dart';
import '../data/merchant_after_sales_repository.dart';
import '../data/merchant_after_sales_request.dart';

const _defaultStatusFilter = 'pending';

final merchantAfterSalesRepositoryProvider = Provider<MerchantAfterSalesRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  final repo = MerchantAfterSalesRepository(client);
  ref.onDispose(repo.dispose);
  return repo;
});

final afterSalesStatusFilterProvider = StateProvider<String>((ref) => _defaultStatusFilter);

final afterSalesListProvider = AsyncNotifierProvider<MerchantAfterSalesListNotifier, AfterSalesListState>(
  MerchantAfterSalesListNotifier.new,
);

class MerchantAfterSalesListNotifier extends AsyncNotifier<AfterSalesListState> {
  bool _isLoadingMore = false;

  bool get isLoadingMore => _isLoadingMore;

  @override
  Future<AfterSalesListState> build() async {
    ref.watch(afterSalesStatusFilterProvider);
    return _fetch(page: 1, replace: true);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _fetch(page: 1, replace: true));
  }

  Future<void> loadMore() async {
    if (_isLoadingMore) return;
    final current = state.value;
    if (current == null || !current.hasMore) return;
    _isLoadingMore = true;
    try {
      final nextState = await _fetch(page: current.page + 1, replace: false);
      state = AsyncData(nextState);
    } finally {
      _isLoadingMore = false;
    }
  }

  Future<AfterSalesListState> _fetch({required int page, required bool replace}) async {
    final filter = ref.read(afterSalesStatusFilterProvider);
    final repo = ref.read(merchantAfterSalesRepositoryProvider);
    final result = await repo.fetchRequests(status: filter, page: page, perPage: 20);
    final previous = state.value;
    final mergedRequests = replace
        ? result.requests
        : [
            ...?previous?.requests,
            ...result.requests,
          ];
    return AfterSalesListState(
      requests: mergedRequests,
      total: result.total,
      page: result.page,
      perPage: result.perPage,
    );
  }
}

final afterSalesDetailProvider = AsyncNotifierProviderFamily<MerchantAfterSalesDetailNotifier, MerchantAfterSalesRequest, String>(
  MerchantAfterSalesDetailNotifier.new,
);

class MerchantAfterSalesDetailNotifier extends FamilyAsyncNotifier<MerchantAfterSalesRequest, String> {
  @override
  Future<MerchantAfterSalesRequest> build(String requestId) async {
    final repo = ref.read(merchantAfterSalesRepositoryProvider);
    return repo.fetchDetail(requestId);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => ref.read(merchantAfterSalesRepositoryProvider).fetchDetail(arg));
  }
}

class AfterSalesListState {
  const AfterSalesListState({
    required this.requests,
    required this.total,
    required this.page,
    required this.perPage,
  });

  final List<MerchantAfterSalesRequest> requests;
  final int total;
  final int page;
  final int perPage;

  bool get hasMore => requests.length < total;
}

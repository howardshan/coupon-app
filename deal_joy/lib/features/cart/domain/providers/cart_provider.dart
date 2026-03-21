// 购物车状态管理 — V3 DB 持久化版本（AsyncNotifier 模式）

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../shared/providers/supabase_provider.dart';
import '../../../auth/domain/providers/auth_provider.dart';
import '../../../deals/data/models/deal_model.dart';
import '../../data/models/cart_item_model.dart';
import '../../data/repositories/cart_repository.dart';

// ── Repository Provider ─────────────────────────────────────
final cartRepositoryProvider = Provider<CartRepository>((ref) {
  return CartRepository(ref.watch(supabaseClientProvider));
});

// ── CartNotifier (AsyncNotifier) ────────────────────────────
class CartNotifier extends AsyncNotifier<List<CartItemModel>> {
  CartRepository get _repo => ref.read(cartRepositoryProvider);

  @override
  Future<List<CartItemModel>> build() async {
    // 监听登录状态，用户变化时自动重新加载
    final user = await ref.watch(currentUserProvider.future);
    if (user == null) return [];
    return _repo.fetchCartItems(user.id);
  }

  /// 从 DealModel 添加一张券到购物车
  Future<void> addDeal(
    DealModel deal, {
    String? purchasedMerchantId,
    Map<String, dynamic>? selectedOptions,
  }) async {
    final user = await ref.read(currentUserProvider.future);
    if (user == null) return;

    // 乐观更新前先标记 loading
    state = const AsyncLoading();

    state = await AsyncValue.guard(() async {
      await _repo.addToCart(
        userId: user.id,
        dealId: deal.id,
        unitPrice: deal.discountPrice,
        purchasedMerchantId: purchasedMerchantId,
        applicableStoreIds: deal.applicableMerchantIds ?? [],
        selectedOptions: selectedOptions,
      );
      // 重新拉取最新列表
      return _repo.fetchCartItems(user.id);
    });
  }

  /// 从已有 CartItemModel 复制一份加入购物车（数量 +1 用）
  Future<void> addDealFromCartItem(CartItemModel item) async {
    final user = await ref.read(currentUserProvider.future);
    if (user == null) return;

    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await _repo.addToCart(
        userId: user.id,
        dealId: item.dealId,
        unitPrice: item.unitPrice,
        purchasedMerchantId: item.purchasedMerchantId,
        applicableStoreIds: item.applicableStoreIds,
        selectedOptions: item.selectedOptions,
      );
      return _repo.fetchCartItems(user.id);
    });
  }

  /// 移除指定 cart_item（通过主键 id）
  Future<void> removeItem(String cartItemId) async {
    final user = await ref.read(currentUserProvider.future);
    if (user == null) return;

    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await _repo.removeFromCart(cartItemId);
      return _repo.fetchCartItems(user.id);
    });
  }

  /// 清空购物车
  Future<void> clear() async {
    final user = await ref.read(currentUserProvider.future);
    if (user == null) return;

    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await _repo.clearCart(user.id);
      return <CartItemModel>[];
    });
  }
}

final cartProvider =
    AsyncNotifierProvider<CartNotifier, List<CartItemModel>>(CartNotifier.new);

// ── 派生 Providers ──────────────────────────────────────────

/// 购物车总券数（用于底部 Tab badge）
final cartTotalCountProvider = Provider<int>((ref) {
  return ref.watch(cartProvider).valueOrNull?.length ?? 0;
});

/// 购物车不重复 deal 数量（用于计算 service fee）
final cartDistinctDealCountProvider = Provider<int>((ref) {
  final items = ref.watch(cartProvider).valueOrNull ?? [];
  return items.map((e) => e.dealId).toSet().length;
});

/// 购物车商品总价（所有券 unitPrice 之和）
final cartTotalPriceProvider = Provider<double>((ref) {
  final items = ref.watch(cartProvider).valueOrNull ?? [];
  return items.fold(0.0, (sum, item) => sum + item.unitPrice);
});

/// Service fee：$0.99 × 不重复 deal 数量
final cartServiceFeeProvider = Provider<double>((ref) {
  final distinctCount = ref.watch(cartDistinctDealCountProvider);
  return 0.99 * distinctCount;
});

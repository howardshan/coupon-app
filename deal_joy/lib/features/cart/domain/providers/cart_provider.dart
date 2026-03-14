// 购物车状态管理 — Riverpod Notifier（内存态，重启清空）

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../deals/data/models/deal_model.dart';
import '../../data/models/cart_item_model.dart';

/// 购物车 Notifier
class CartNotifier extends Notifier<List<CartItemModel>> {
  @override
  List<CartItemModel> build() => [];

  /// 从 DealModel 添加到购物车（数量 +1 或新增）
  void addDeal(DealModel deal) {
    final idx = state.indexWhere((e) => e.dealId == deal.id);
    if (idx >= 0) {
      // 已存在，数量 +1
      final updated = [...state];
      updated[idx] = updated[idx].copyWith(quantity: updated[idx].quantity + 1);
      state = updated;
    } else {
      state = [
        ...state,
        CartItemModel(
          dealId: deal.id,
          dealTitle: deal.title,
          dealImageUrl: deal.imageUrls.isNotEmpty ? deal.imageUrls.first : null,
          discountPrice: deal.discountPrice,
          originalPrice: deal.originalPrice,
          merchantName: deal.merchant?.name ?? '',
          merchantId: deal.merchantId,
          quantity: 1,
        ),
      ];
    }
  }

  /// 修改指定 deal 数量（0 则移除）
  void updateQuantity(String dealId, int quantity) {
    if (quantity <= 0) {
      state = state.where((e) => e.dealId != dealId).toList();
    } else {
      state = state.map((e) {
        if (e.dealId == dealId) return e.copyWith(quantity: quantity);
        return e;
      }).toList();
    }
  }

  /// 移除单项
  void remove(String dealId) {
    state = state.where((e) => e.dealId != dealId).toList();
  }

  /// 清空购物车
  void clear() {
    state = [];
  }
}

final cartProvider =
    NotifierProvider<CartNotifier, List<CartItemModel>>(CartNotifier.new);

/// 购物车总数量（用于 badge 展示）
final cartTotalCountProvider = Provider<int>((ref) {
  return ref.watch(cartProvider).fold(0, (sum, item) => sum + item.quantity);
});

/// 购物车总金额
final cartTotalPriceProvider = Provider<double>((ref) {
  return ref.watch(cartProvider).fold(0.0, (sum, item) => sum + item.subtotal);
});

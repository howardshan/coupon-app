// 购物车 Repository — 直接读写 cart_items 表
// cart_items JOIN deals JOIN merchants 获取展示数据

import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/cart_item_model.dart';

class CartRepository {
  final SupabaseClient _client;

  const CartRepository(this._client);

  // ── select 字段（cart_items JOIN deals JOIN merchants）──────
  static const _selectFields = '''
    id,
    user_id,
    deal_id,
    unit_price,
    purchased_merchant_id,
    applicable_store_ids,
    selected_options,
    created_at,
    deals(
      id,
      title,
      image_urls,
      original_price,
      discount_price,
      merchants(id, name)
    )
  ''';

  /// 获取用户购物车列表（按创建时间倒序）
  Future<List<CartItemModel>> fetchCartItems(String userId) async {
    final data = await _client
        .from('cart_items')
        .select(_selectFields)
        .eq('user_id', userId)
        .order('created_at', ascending: false);

    return (data as List)
        .map((e) => CartItemModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 添加到购物车（每次调用插入一行 = 一张券）
  Future<CartItemModel> addToCart({
    required String userId,
    required String dealId,
    required double unitPrice,
    String? purchasedMerchantId,
    List<String> applicableStoreIds = const [],
    Map<String, dynamic>? selectedOptions,
  }) async {
    final payload = <String, dynamic>{
      'user_id': userId,
      'deal_id': dealId,
      'unit_price': unitPrice,
      'purchased_merchant_id': purchasedMerchantId,
      'applicable_store_ids': applicableStoreIds.isNotEmpty ? applicableStoreIds : null,
      'selected_options': selectedOptions,
    };

    final data = await _client
        .from('cart_items')
        .insert(payload)
        .select(_selectFields)
        .single();

    return CartItemModel.fromJson(data);
  }

  /// 移除指定 cart_item（通过主键 id）
  Future<void> removeFromCart(String cartItemId) async {
    await _client
        .from('cart_items')
        .delete()
        .eq('id', cartItemId);
  }

  /// 清空用户购物车（删除该用户所有 cart_items）
  Future<void> clearCart(String userId) async {
    await _client
        .from('cart_items')
        .delete()
        .eq('user_id', userId);
  }

  /// 获取购物车券数量（只查 count，不拉完整数据）
  Future<int> getCartCount(String userId) async {
    final resp = await _client
        .from('cart_items')
        .select('id')
        .eq('user_id', userId)
        .count(CountOption.exact);
    return resp.count;
  }
}

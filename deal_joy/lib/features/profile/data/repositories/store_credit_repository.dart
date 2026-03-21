import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/store_credit_model.dart';

// 直接查询 store_credits 和 store_credit_transactions 表
class StoreCreditRepository {
  final SupabaseClient _client;

  StoreCreditRepository(this._client);

  /// 查询用户余额，若无记录则返回零余额占位对象
  Future<StoreCredit> fetchBalance(String userId) async {
    final response = await _client
        .from('store_credits')
        .select()
        .eq('user_id', userId)
        .maybeSingle();

    if (response == null) {
      return StoreCredit.zero(userId);
    }
    return StoreCredit.fromJson(response);
  }

  /// 查询用户流水记录，按创建时间倒序，默认最多 50 条
  Future<List<StoreCreditTransaction>> fetchTransactions(
    String userId, {
    int limit = 50,
  }) async {
    final response = await _client
        .from('store_credit_transactions')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(limit);

    return (response as List<dynamic>)
        .map((e) => StoreCreditTransaction.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}

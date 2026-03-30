import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/saved_card_model.dart';

/// 管理已保存支付卡片的 Repository
/// 所有操作均通过 manage-payment-methods Edge Function 完成
class PaymentMethodsRepository {
  final SupabaseClient _client;

  PaymentMethodsRepository(this._client);

  /// 获取当前用户已保存的卡片列表
  /// Edge Function 返回格式：[{ id, brand, last4, expMonth, expYear, isDefault }]
  Future<List<SavedCard>> fetchSavedCards() async {
    try {
      final response = await _client.functions.invoke(
        'manage-payment-methods',
        method: HttpMethod.get,
      );

      if (response.status != 200) {
        final errMsg = response.data?['error'] as String? ?? 'Failed to load cards';
        throw Exception(errMsg);
      }

      final data = response.data;
      // 后端返回 { paymentMethods: [...] } 或直接返回数组
      final List<dynamic> list = data is List
          ? data
          : (data['paymentMethods'] as List<dynamic>? ?? []);

      return list
          .whereType<Map<String, dynamic>>()
          .map(SavedCard.fromJson)
          .toList();
    } catch (e) {
      throw Exception('Failed to fetch saved cards: $e');
    }
  }

  /// 将指定卡片设为默认支付方式
  Future<void> setDefaultCard(String paymentMethodId) async {
    try {
      final response = await _client.functions.invoke(
        'manage-payment-methods',
        method: HttpMethod.post,
        body: {
          'action': 'set_default',
          'paymentMethodId': paymentMethodId,
        },
      );

      if (response.status != 200) {
        final errMsg = response.data?['error'] as String? ?? 'Failed to set default card';
        throw Exception(errMsg);
      }
    } catch (e) {
      throw Exception('Failed to set default card: $e');
    }
  }

  /// 删除指定卡片（从 Stripe 解绑）
  Future<void> deleteCard(String paymentMethodId) async {
    try {
      final response = await _client.functions.invoke(
        'manage-payment-methods',
        method: HttpMethod.delete,
        body: {'paymentMethodId': paymentMethodId},
      );

      if (response.status != 200) {
        final errMsg = response.data?['error'] as String? ?? 'Failed to delete card';
        throw Exception(errMsg);
      }
    } catch (e) {
      throw Exception('Failed to delete card: $e');
    }
  }

  /// 更新卡片信息（过期日期 + 账单地址）
  Future<void> updateCard({
    required String paymentMethodId,
    int? expMonth,
    int? expYear,
    Map<String, String>? billingAddress,
  }) async {
    try {
      final body = <String, dynamic>{
        'action': 'update_card',
        'paymentMethodId': paymentMethodId,
      };
      if (expMonth != null && expYear != null) {
        body['expMonth'] = expMonth;
        body['expYear'] = expYear;
      }
      if (billingAddress != null) {
        body['billingAddress'] = billingAddress;
      }

      final response = await _client.functions.invoke(
        'manage-payment-methods',
        method: HttpMethod.post,
        body: body,
      );

      if (response.status != 200) {
        final errMsg = response.data?['error'] as String? ?? 'Failed to update card';
        throw Exception(errMsg);
      }
    } catch (e) {
      throw Exception('Failed to update card: $e');
    }
  }

  /// 为添加新卡片创建 SetupIntent
  /// 返回 { clientSecret, customerId, ephemeralKey }
  Future<Map<String, String>> createSetupIntent() async {
    try {
      final response = await _client.functions.invoke(
        'manage-payment-methods',
        method: HttpMethod.post,
        body: {'action': 'create_setup_intent'},
      );

      if (response.status != 200) {
        final errMsg = response.data?['error'] as String? ?? 'Failed to setup card';
        throw Exception(errMsg);
      }

      final data = response.data as Map<String, dynamic>;
      return {
        'clientSecret': data['clientSecret'] as String? ?? '',
        'customerId': data['customerId'] as String? ?? '',
        'ephemeralKey': data['ephemeralKey'] as String? ?? '',
      };
    } catch (e) {
      throw Exception('Failed to create setup intent: $e');
    }
  }
}

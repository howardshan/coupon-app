import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/billing_address_model.dart';

/// 账单地址 CRUD Repository
class BillingAddressRepository {
  final SupabaseClient _client;

  BillingAddressRepository(this._client);

  /// 获取当前用户所有已保存的账单地址（默认地址排最前）
  Future<List<BillingAddressModel>> fetchAll(String userId) async {
    final data = await _client
        .from('billing_addresses')
        .select()
        .eq('user_id', userId)
        .order('is_default', ascending: false)
        .order('created_at', ascending: false);
    return (data as List).map((e) => BillingAddressModel.fromJson(e)).toList();
  }

  /// 新增地址；如果 isDefault=true，先把其他地址取消默认
  Future<BillingAddressModel> create({
    required String userId,
    required String label,
    required String addressLine1,
    String addressLine2 = '',
    required String city,
    required String state,
    required String postalCode,
    String country = 'US',
    bool isDefault = false,
  }) async {
    // 设为默认时，先清除旧默认
    if (isDefault) {
      await _client
          .from('billing_addresses')
          .update({'is_default': false})
          .eq('user_id', userId)
          .eq('is_default', true);
    }
    final row = await _client.from('billing_addresses').insert({
      'user_id': userId,
      'label': label,
      'address_line1': addressLine1,
      'address_line2': addressLine2,
      'city': city,
      'state': state,
      'postal_code': postalCode,
      'country': country,
      'is_default': isDefault,
    }).select().single();
    return BillingAddressModel.fromJson(row);
  }

  /// 设置某地址为默认（先清除旧默认）
  Future<void> setDefault(String userId, String addressId) async {
    await _client
        .from('billing_addresses')
        .update({'is_default': false})
        .eq('user_id', userId)
        .eq('is_default', true);
    await _client
        .from('billing_addresses')
        .update({'is_default': true, 'updated_at': DateTime.now().toIso8601String()})
        .eq('id', addressId);
  }

  /// 删除地址
  Future<void> delete(String addressId) async {
    await _client.from('billing_addresses').delete().eq('id', addressId);
  }

  /// 同步 users 表中的旧 billing address 到 billing_addresses 表（一次性迁移）
  /// 如果用户在 users 表有 billing_address_line1 但 billing_addresses 表为空，自动迁移
  Future<void> migrateFromUsersTable(String userId) async {
    try {
      final existing = await _client
          .from('billing_addresses')
          .select('id')
          .eq('user_id', userId)
          .limit(1);
      if ((existing as List).isNotEmpty) return; // 已有地址，不迁移

      final userData = await _client
          .from('users')
          .select('billing_address_line1, billing_address_line2, billing_city, billing_state, billing_postal_code, billing_country')
          .eq('id', userId)
          .single();

      final line1 = userData['billing_address_line1'] as String? ?? '';
      if (line1.isEmpty) return; // users 表也没地址

      await create(
        userId: userId,
        label: 'Default',
        addressLine1: line1,
        addressLine2: userData['billing_address_line2'] as String? ?? '',
        city: userData['billing_city'] as String? ?? '',
        state: userData['billing_state'] as String? ?? '',
        postalCode: userData['billing_postal_code'] as String? ?? '',
        country: userData['billing_country'] as String? ?? 'US',
        isDefault: true,
      );
    } catch (e) {
      debugPrint('迁移旧 billing address 失败: $e');
    }
  }
}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/models/billing_address_model.dart';
import '../../data/repositories/billing_address_repository.dart';

/// BillingAddressRepository 单例
final billingAddressRepositoryProvider = Provider<BillingAddressRepository>((ref) {
  return BillingAddressRepository(Supabase.instance.client);
});

/// 当前用户的所有已保存账单地址（自动迁移旧数据）
final savedBillingAddressesProvider = FutureProvider<List<BillingAddressModel>>((ref) async {
  final userId = Supabase.instance.client.auth.currentUser?.id;
  if (userId == null || userId.isEmpty) return [];
  final repo = ref.read(billingAddressRepositoryProvider);
  // 首次加载时自动迁移 users 表中的旧地址
  await repo.migrateFromUsersTable(userId);
  return repo.fetchAll(userId);
});

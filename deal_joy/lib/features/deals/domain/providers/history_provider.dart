import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/deal_model.dart';
import '../../data/repositories/history_repository.dart';
import '../../../merchant/data/models/merchant_model.dart';
import '../../../merchant/domain/providers/merchant_provider.dart';
import 'deals_provider.dart';

final historyRepositoryProvider = Provider<HistoryRepository>(
  (_) => HistoryRepository(),
);

// ── Deal 历史 ──────────────────────────────────────────────────

/// 从本地存储读取历史 deal ID 列表（最新在前）
/// autoDispose：每次 HistoryScreen 打开时重新读取 SharedPreferences，避免永久缓存旧数据
final historyIdsProvider = FutureProvider.autoDispose<List<String>>((ref) async {
  return ref.read(historyRepositoryProvider).getHistory();
});

/// 根据历史 ID 列表批量获取 deal 数据
final historyDealsProvider = FutureProvider.autoDispose<List<DealModel>>((ref) async {
  final ids = await ref.watch(historyIdsProvider.future);
  if (ids.isEmpty) return [];
  return ref.watch(dealsRepositoryProvider).fetchDealsByIds(ids);
});

// ── Store 历史 ─────────────────────────────────────────────────

/// 从本地存储读取历史 merchant ID 列表（最新在前）
final historyMerchantIdsProvider = FutureProvider.autoDispose<List<String>>((ref) async {
  return ref.read(historyRepositoryProvider).getMerchantHistory();
});

/// 根据历史 ID 列表批量获取 merchant 数据
final historyMerchantsProvider =
    FutureProvider.autoDispose<List<MerchantModel>>((ref) async {
  final ids = await ref.watch(historyMerchantIdsProvider.future);
  if (ids.isEmpty) return [];
  return ref.watch(merchantRepositoryProvider).fetchMerchantsByIds(ids);
});

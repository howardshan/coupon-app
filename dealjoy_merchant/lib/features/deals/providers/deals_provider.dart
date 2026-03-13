// Deal管理 Riverpod Provider
// 使用 AsyncNotifier 管理 MerchantDeal 列表状态

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/merchant_deal.dart';
import '../models/deal_category.dart';
import '../models/deal_template.dart';
import '../services/deals_service.dart';

// ============================================================
// DealsService Provider — 注入 Supabase 客户端
// ============================================================
final dealsServiceProvider = Provider<DealsService>((ref) {
  return DealsService(Supabase.instance.client);
});

// ============================================================
// dealFilterProvider — 当前选中的状态筛选（null=All）
// ============================================================
final dealFilterProvider = StateProvider<DealStatus?>((ref) => null);

// ============================================================
// DealsNotifier — AsyncNotifier<List<MerchantDeal>>
// 管理商家 Deal 列表，支持 CRUD 操作
// ============================================================
class DealsNotifier extends AsyncNotifier<List<MerchantDeal>> {
  late DealsService _service;
  late String _merchantId;

  @override
  Future<List<MerchantDeal>> build() async {
    _service = ref.read(dealsServiceProvider);

    // 获取当前商家 ID
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) throw Exception('Not authenticated');

    final merchantData = await Supabase.instance.client
        .from('merchants')
        .select('id')
        .eq('user_id', user.id)
        .single();

    _merchantId = merchantData['id'] as String;

    // 加载 Deal 列表（不带筛选，加载全部）
    return await _service.fetchDeals(_merchantId);
  }

  // ----------------------------------------------------------
  // 刷新列表（重新从服务器加载）
  // ----------------------------------------------------------
  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => _service.fetchDeals(_merchantId),
    );
  }

  // ----------------------------------------------------------
  // 创建新 Deal（提交审核）
  //    创建成功后追加到列表头部
  // ----------------------------------------------------------
  Future<MerchantDeal> createDeal(MerchantDeal deal) async {
    final newDeal = await _service.createDeal(
      deal.copyWith(merchantId: _merchantId),
    );

    // 更新本地列表：插入到头部
    final current = state.valueOrNull ?? [];
    state = AsyncValue.data([newDeal, ...current]);

    return newDeal;
  }

  // ----------------------------------------------------------
  // 更新 Deal（修改后重新审核）
  //    乐观更新：先更新本地，失败时回滚
  // ----------------------------------------------------------
  Future<void> updateDeal(MerchantDeal deal) async {
    final current = state.valueOrNull ?? [];

    // 乐观更新本地状态（标记为 pending）
    final optimistic = deal.copyWith(dealStatus: DealStatus.pending, isActive: false);
    final updatedList = current
        .map((d) => d.id == deal.id ? optimistic : d)
        .toList();
    state = AsyncValue.data(updatedList);

    try {
      final updated = await _service.updateDeal(deal);
      // 用服务器返回的最终数据替换
      final finalList = current
          .map((d) => d.id == deal.id ? updated : d)
          .toList();
      state = AsyncValue.data(finalList);
    } catch (e, st) {
      // 失败回滚
      state = AsyncValue.data(current);
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  // ----------------------------------------------------------
  // 上下架切换
  //    乐观更新：先更新本地状态，失败时回滚
  // ----------------------------------------------------------
  Future<void> toggleDealStatus(String dealId, bool isActive) async {
    final current = state.valueOrNull ?? [];
    final target = current.firstWhere(
      (d) => d.id == dealId,
      orElse: () => throw Exception('Deal not found: $dealId'),
    );

    // 乐观更新
    final newStatus = isActive ? DealStatus.active : DealStatus.inactive;
    final optimistic = target.copyWith(dealStatus: newStatus, isActive: isActive);
    final updatedList = current
        .map((d) => d.id == dealId ? optimistic : d)
        .toList();
    state = AsyncValue.data(updatedList);

    try {
      await _service.toggleDealStatus(dealId, isActive);
    } catch (e, st) {
      // 失败回滚
      state = AsyncValue.data(current);
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  // ----------------------------------------------------------
  // 删除 Deal（仅 inactive 状态）
  //    乐观删除：先从列表移除，失败时恢复
  // ----------------------------------------------------------
  Future<void> deleteDeal(String dealId) async {
    final current = state.valueOrNull ?? [];

    // 乐观删除
    final updatedList = current.where((d) => d.id != dealId).toList();
    state = AsyncValue.data(updatedList);

    try {
      await _service.deleteDeal(dealId);
    } catch (e, st) {
      // 失败回滚
      state = AsyncValue.data(current);
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  // ----------------------------------------------------------
  // 上传图片并关联到 Deal
  //    上传完成后更新对应 Deal 的 images 列表
  // ----------------------------------------------------------
  Future<DealImage> uploadImage({
    required String dealId,
    required XFile file,
    int sortOrder = 0,
    bool isPrimary = false,
  }) async {
    final image = await _service.uploadDealImage(
      merchantId: _merchantId,
      dealId: dealId,
      file: file,
      sortOrder: sortOrder,
      isPrimary: isPrimary,
    );

    // 更新本地对应 Deal 的图片列表
    final current = state.valueOrNull ?? [];
    final updatedList = current.map((d) {
      if (d.id != dealId) return d;
      return d.copyWith(images: [...d.images, image]);
    }).toList();
    state = AsyncValue.data(updatedList);

    return image;
  }

  // ----------------------------------------------------------
  // 删除 Deal 图片
  // ----------------------------------------------------------
  Future<void> deleteImage({
    required String dealId,
    required String imageId,
    required String imageUrl,
  }) async {
    final current = state.valueOrNull ?? [];

    // 乐观从列表移除
    final updatedList = current.map((d) {
      if (d.id != dealId) return d;
      final newImages = d.images.where((img) => img.id != imageId).toList();
      return d.copyWith(images: newImages);
    }).toList();
    state = AsyncValue.data(updatedList);

    try {
      await _service.deleteDealImage(
        dealId: dealId,
        imageId: imageId,
        imageUrl: imageUrl,
      );
    } catch (e, st) {
      // 失败回滚
      state = AsyncValue.data(current);
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  /// 获取当前商家 ID
  String get merchantId => _merchantId;
}

// ============================================================
// dealsProvider — 全局单例，Deal 列表管理
// ============================================================
final dealsProvider =
    AsyncNotifierProvider<DealsNotifier, List<MerchantDeal>>(
  DealsNotifier.new,
);

// ============================================================
// filteredDealsProvider — 根据 dealFilterProvider 筛选后的列表
// 用于 Tab 视图，避免重复请求
// ============================================================
final filteredDealsProvider = Provider<AsyncValue<List<MerchantDeal>>>((ref) {
  final allDealsAsync = ref.watch(dealsProvider);
  final filter = ref.watch(dealFilterProvider);

  return allDealsAsync.whenData((deals) {
    if (filter == null) return deals;
    return deals.where((d) => d.dealStatus == filter).toList();
  });
});

// ============================================================
// dealCategoriesProvider — 当前商家的 Deal 分类列表
// ============================================================
final dealCategoriesProvider =
    FutureProvider<List<DealCategory>>((ref) async {
  final service = ref.read(dealsServiceProvider);
  // 获取商家 ID
  final user = Supabase.instance.client.auth.currentUser;
  if (user == null) return [];
  final merchantData = await Supabase.instance.client
      .from('merchants')
      .select('id')
      .eq('user_id', user.id)
      .single();
  final merchantId = merchantData['id'] as String;
  final rawList = await service.fetchDealCategories(merchantId);
  return rawList.map((e) => DealCategory.fromJson(e)).toList();
});

// ============================================================
// V2.2 Deal 模板 Provider
// ============================================================

/// 模板列表 Notifier — 品牌级 Deal 模板 CRUD
class DealTemplatesNotifier extends AsyncNotifier<List<DealTemplate>> {
  @override
  Future<List<DealTemplate>> build() async {
    final service = ref.read(dealsServiceProvider);
    return service.fetchTemplates();
  }

  /// 刷新模板列表
  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => ref.read(dealsServiceProvider).fetchTemplates(),
    );
  }

  /// 创建模板
  Future<DealTemplate> createTemplate(DealTemplate template) async {
    final service = ref.read(dealsServiceProvider);
    final created = await service.createTemplate(template);
    final current = state.valueOrNull ?? [];
    state = AsyncValue.data([created, ...current]);
    return created;
  }

  /// 更新模板
  Future<void> updateTemplate(String templateId, Map<String, dynamic> updates) async {
    final service = ref.read(dealsServiceProvider);
    final updated = await service.updateTemplate(templateId, updates);
    final current = state.valueOrNull ?? [];
    state = AsyncValue.data(
      current.map((t) => t.id == templateId ? updated : t).toList(),
    );
  }

  /// 发布模板到指定门店
  Future<Map<String, dynamic>> publishTemplate(
    String templateId,
    List<String> merchantIds,
  ) async {
    final service = ref.read(dealsServiceProvider);
    final result = await service.publishTemplate(templateId, merchantIds);
    // 发布后刷新模板列表（更新 linkedStores）
    await refresh();
    return result;
  }

  /// 同步模板到所有关联门店
  Future<Map<String, dynamic>> syncTemplate(String templateId) async {
    final service = ref.read(dealsServiceProvider);
    return service.syncTemplate(templateId);
  }

  /// 删除模板
  Future<void> deleteTemplate(String templateId) async {
    final service = ref.read(dealsServiceProvider);
    final current = state.valueOrNull ?? [];
    // 乐观删除
    state = AsyncValue.data(current.where((t) => t.id != templateId).toList());
    try {
      await service.deleteTemplate(templateId);
    } catch (e, st) {
      state = AsyncValue.data(current);
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }
}

/// 模板列表 Provider
final dealTemplatesProvider =
    AsyncNotifierProvider<DealTemplatesNotifier, List<DealTemplate>>(
  DealTemplatesNotifier.new,
);

// ============================================================
// pendingStoreDealsProvider — 当前门店待确认的品牌 Deal 列表
// 直接查 Supabase 表（门店视角，不走 Edge Function）
// ============================================================
final pendingStoreDealsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final supabase = Supabase.instance.client;
  final user = supabase.auth.currentUser;
  if (user == null) {
    debugPrint('[pendingStoreDeals] user is null');
    return [];
  }
  debugPrint('[pendingStoreDeals] user=${user.id}');

  // 获取当前用户关联的门店 merchant_id
  final merchant = await supabase
      .from('merchants')
      .select('id')
      .eq('user_id', user.id)
      .maybeSingle();
  if (merchant == null) {
    debugPrint('[pendingStoreDeals] merchant not found for user');
    return [];
  }
  final merchantId = merchant['id'] as String;
  debugPrint('[pendingStoreDeals] merchantId=$merchantId');

  try {
    // 查询 deal_applicable_stores 中 pending 记录，join deals 和品牌商家名称
    final rows = await supabase
        .from('deal_applicable_stores')
        .select(
          'deal_id, created_at, deals(title, discount_price, merchants!deals_merchant_id_fkey(name))',
        )
        .eq('store_id', merchantId)
        .eq('status', 'pending_store_confirmation')
        .order('created_at', ascending: false);

    debugPrint('[pendingStoreDeals] rows count=${(rows as List).length}, data=$rows');
    return List<Map<String, dynamic>>.from(rows);
  } catch (e) {
    debugPrint('[pendingStoreDeals] ERROR: $e');
    rethrow;
  }
});

// ============================================================
// declinedStoreDealsProvider — 当前门店已拒绝的品牌 Deal 列表
// 直接查 Supabase 表（门店视角，不走 Edge Function）
// ============================================================
final declinedStoreDealsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final supabase = Supabase.instance.client;
  final user = supabase.auth.currentUser;
  if (user == null) return [];

  final merchant = await supabase
      .from('merchants')
      .select('id')
      .eq('user_id', user.id)
      .maybeSingle();
  if (merchant == null) return [];
  final merchantId = merchant['id'] as String;

  try {
    final rows = await supabase
        .from('deal_applicable_stores')
        .select(
          'deal_id, created_at, deals(title, discount_price, merchants!deals_merchant_id_fkey(name), deal_images(image_url, is_primary, sort_order))',
        )
        .eq('store_id', merchantId)
        .eq('status', 'declined')
        .order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(rows);
  } catch (e) {
    debugPrint('[declinedStoreDeals] ERROR: $e');
    rethrow;
  }
});

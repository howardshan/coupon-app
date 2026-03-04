// Deal管理 Riverpod Provider
// 使用 AsyncNotifier 管理 MerchantDeal 列表状态

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/merchant_deal.dart';
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

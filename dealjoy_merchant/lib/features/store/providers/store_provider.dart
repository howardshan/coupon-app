// 门店信息 Riverpod Provider
// 使用 AsyncNotifier 管理 StoreInfo 状态

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/store_info.dart';
import '../models/store_summary.dart';
import '../models/staff_member.dart';
import '../services/store_service.dart';

// ============================================================
// StoreService Provider — 注入 Supabase 客户端
// ============================================================
final storeServiceProvider = Provider<StoreService>((ref) {
  return StoreService(Supabase.instance.client);
});

// ============================================================
// StoreNotifier — AsyncNotifier<StoreInfo>
// 负责加载门店信息和触发各类更新操作
// ============================================================
class StoreNotifier extends AsyncNotifier<StoreInfo> {
  late StoreService _service;

  @override
  Future<StoreInfo> build() async {
    _service = ref.read(storeServiceProvider);
    // 加载门店完整信息
    final info = await _service.fetchStoreInfo();
    debugPrint('[StoreProvider] name=${info.name}, isBrandAdmin=${info.isBrandAdmin}, role=${info.currentRole}, brand=${info.brand?.name}');
    return info;
  }

  // ----------------------------------------------------------
  // 刷新门店信息（从服务器重新加载）
  // ----------------------------------------------------------
  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _service.fetchStoreInfo());
  }

  // ----------------------------------------------------------
  // 更新基本信息（乐观更新：先更新本地状态，再调 API）
  // ----------------------------------------------------------
  Future<void> updateBasicInfo({
    String? name,
    String? description,
    String? phone,
    String? address,
    String? city,
    double? lat,
    double? lng,
  }) async {
    final current = state.valueOrNull;
    if (current == null) return;

    // 乐观更新本地状态
    state = AsyncValue.data(
      current.copyWith(
        name: name ?? current.name,
        description: description ?? current.description,
        phone: phone ?? current.phone,
        address: address ?? current.address,
      ),
    );

    try {
      await _service.updateStoreInfo(
        name: name,
        description: description,
        phone: phone,
        address: address,
        city: city,
        lat: lat,
        lng: lng,
      );
    } catch (e, st) {
      // 失败时回滚本地状态
      state = AsyncValue.data(current);
      state = AsyncValue.error(e, st);
    }
  }

  // ----------------------------------------------------------
  // 更新标签
  // ----------------------------------------------------------
  Future<void> updateTags(List<String> tags) async {
    final current = state.valueOrNull;
    if (current == null) return;

    // 乐观更新
    state = AsyncValue.data(current.copyWith(tags: tags));

    try {
      await _service.updateStoreInfo(tags: tags);
    } catch (e, st) {
      state = AsyncValue.data(current);
      state = AsyncValue.error(e, st);
    }
  }

  // ----------------------------------------------------------
  // 更新头图模式（single / triple）和选中的头图
  // ----------------------------------------------------------
  Future<void> updateHeaderStyle({
    required String headerPhotoStyle,
    required List<String> headerPhotos,
  }) async {
    final current = state.valueOrNull;
    if (current == null) return;

    // 乐观更新
    state = AsyncValue.data(current.copyWith(
      headerPhotoStyle: headerPhotoStyle,
      headerPhotos: headerPhotos,
    ));

    try {
      await _service.updateStoreInfo(
        headerPhotoStyle: headerPhotoStyle,
        headerPhotos: headerPhotos,
      );
    } catch (e, st) {
      state = AsyncValue.data(current);
      state = AsyncValue.error(e, st);
    }
  }

  // ----------------------------------------------------------
  // 批量保存营业时间
  // ----------------------------------------------------------
  Future<void> updateBusinessHours(List<BusinessHours> hours) async {
    final current = state.valueOrNull;
    if (current == null) return;

    // 乐观更新本地营业时间
    state = AsyncValue.data(current.copyWith(hours: hours));

    try {
      final updatedHours = await _service.updateBusinessHours(hours);
      // 用服务器返回的数据更新（含服务端生成的 id）
      final updatedStore = current.copyWith(hours: updatedHours);
      state = AsyncValue.data(updatedStore);
    } catch (e, st) {
      state = AsyncValue.data(current);
      state = AsyncValue.error(e, st);
    }
  }

  // ----------------------------------------------------------
  // 上传照片
  // ----------------------------------------------------------
  Future<void> uploadPhoto({
    required String merchantId,
    required XFile file,
    required StorePhotoType type,
    int sortOrder = 0,
  }) async {
    final current = state.valueOrNull;
    if (current == null) return;

    // 上传过程中不乐观更新（需要等待 Storage URL）
    try {
      final newPhoto = await _service.uploadPhoto(
        merchantId: merchantId,
        file: file,
        type: type,
        sortOrder: sortOrder,
      );
      // 追加到照片列表
      final updatedPhotos = [...current.photos, newPhoto];
      var updated = current.copyWith(photos: updatedPhotos);

      // 自动同步：上传 cover 类型且当前是第一张 → 自动设为 homepage cover
      if (type == StorePhotoType.cover) {
        final coverPhotos = updatedPhotos
            .where((p) => p.type == StorePhotoType.cover)
            .toList()
          ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
        if (coverPhotos.isNotEmpty) {
          final firstCoverUrl = coverPhotos.first.url;
          if (current.homepageCoverUrl != firstCoverUrl) {
            await _service.updateHomepageCover(merchantId, firstCoverUrl);
            updated = updated.copyWith(homepageCoverUrl: firstCoverUrl);
          }
        }
      }

      state = AsyncValue.data(updated);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  // ----------------------------------------------------------
  // 删除照片
  // 删除 cover 类型照片后自动重排剩余 cover 的 sortOrder
  // ----------------------------------------------------------
  Future<void> deletePhoto(String photoId) async {
    final current = state.valueOrNull;
    if (current == null) return;

    // 找到被删照片的类型
    final deletedPhoto = current.photos.where((p) => p.id == photoId).firstOrNull;

    // 乐观从列表移除
    final updatedPhotos =
        current.photos.where((p) => p.id != photoId).toList();
    state = AsyncValue.data(current.copyWith(photos: updatedPhotos));

    try {
      await _service.deletePhoto(photoId);

      // 如果删除的是 cover 类型，自动重排剩余 cover 的 sortOrder + 同步 homepage cover
      if (deletedPhoto?.type == StorePhotoType.cover) {
        final remainingCovers = updatedPhotos
            .where((p) => p.type == StorePhotoType.cover)
            .toList()
          ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

        if (remainingCovers.isNotEmpty) {
          await reorderPhotos(remainingCovers.map((p) => p.id).toList());
          // 同步第一张为 homepage cover
          await _syncHomepageCover(current.id, remainingCovers.first.url);
        } else {
          // 没有 cover 了，清空 homepage cover
          await _service.updateHomepageCover(current.id, '');
          state = AsyncValue.data(
            (state.valueOrNull ?? current).copyWith(homepageCoverUrl: ''),
          );
        }
      }
    } catch (e, st) {
      // 失败回滚
      state = AsyncValue.data(current);
      state = AsyncValue.error(e, st);
    }
  }

  // ----------------------------------------------------------
  // 上传首页封面图
  // ----------------------------------------------------------
  Future<void> uploadHomepageCover({
    required String merchantId,
    required XFile file,
  }) async {
    final current = state.valueOrNull;
    if (current == null) return;

    try {
      final url = await _service.uploadHomepageCover(
        merchantId: merchantId,
        file: file,
      );
      state = AsyncValue.data(current.copyWith(homepageCoverUrl: url));
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  // ----------------------------------------------------------
  // 删除首页封面图
  // ----------------------------------------------------------
  Future<void> deleteHomepageCover() async {
    final current = state.valueOrNull;
    if (current == null) return;
    final currentUrl = current.homepageCoverUrl;
    if (currentUrl == null) return;

    // 乐观清空
    state = AsyncValue.data(current.copyWith(homepageCoverUrl: ''));

    try {
      await _service.deleteHomepageCover(
        merchantId: current.id,
        currentUrl: currentUrl,
      );
    } catch (e, st) {
      state = AsyncValue.data(current);
      state = AsyncValue.error(e, st);
    }
  }

  // ----------------------------------------------------------
  // 重新排序照片（拖拽排序后调用）
  // orderedIds: 新顺序的照片 ID 列表
  // ----------------------------------------------------------
  Future<void> reorderPhotos(List<String> orderedIds) async {
    final current = state.valueOrNull;
    if (current == null) return;

    // 构造新顺序的照片列表（乐观更新）
    final photoMap = {for (final p in current.photos) p.id: p};
    final reorderedPhotos = orderedIds
        .asMap()
        .entries
        .map((e) => photoMap[e.value]?.copyWith(sortOrder: e.key))
        .whereType<StorePhoto>()
        .toList();

    // 保留未在 orderedIds 中的照片（其他类型）
    final otherPhotos = current.photos
        .where((p) => !orderedIds.contains(p.id))
        .toList();

    state = AsyncValue.data(
      current.copyWith(photos: [...reorderedPhotos, ...otherPhotos]),
    );

    try {
      await _service.reorderPhotos(orderedIds);

      // 如果排序的是 cover 类型，同步第一张为 homepage cover
      if (reorderedPhotos.isNotEmpty &&
          reorderedPhotos.first.type == StorePhotoType.cover) {
        await _syncHomepageCover(current.id, reorderedPhotos.first.url);
      }
    } catch (e, st) {
      state = AsyncValue.data(current);
      state = AsyncValue.error(e, st);
    }
  }

  // ----------------------------------------------------------
  // 辅助：同步第一张 cover 照片为 homepage cover
  // ----------------------------------------------------------
  Future<void> _syncHomepageCover(String merchantId, String url) async {
    final cur = state.valueOrNull;
    if (cur == null || cur.homepageCoverUrl == url) return;
    try {
      await _service.updateHomepageCover(merchantId, url);
      state = AsyncValue.data(cur.copyWith(homepageCoverUrl: url));
    } catch (_) {
      // homepage cover 同步失败不阻塞主流程
    }
  }

  // ----------------------------------------------------------
  // 更新商家全局分类
  // ----------------------------------------------------------
  Future<void> updateGlobalCategories(List<GlobalCategory> categories) async {
    final current = state.valueOrNull;
    if (current == null) return;

    // 乐观更新
    state = AsyncValue.data(current.copyWith(globalCategories: categories));

    try {
      final ids = categories.map((c) => c.id).toList();
      await _service.updateCategories(ids);
    } catch (e, st) {
      state = AsyncValue.data(current);
      state = AsyncValue.error(e, st);
    }
  }

  // ----------------------------------------------------------
  // 切换当前操作的门店（品牌管理员专用）
  // ----------------------------------------------------------
  Future<void> switchStore(String merchantId) async {
    _service.setActiveMerchantId(merchantId);
    await refresh();
  }
}

// ============================================================
// storeProvider — 全局单例，供所有门店信息页面使用
// ============================================================
final storeProvider =
    AsyncNotifierProvider<StoreNotifier, StoreInfo>(StoreNotifier.new);

// ============================================================
// brandStoresProvider — 品牌管理员旗下门店列表
// ============================================================
final brandStoresProvider = FutureProvider<List<StoreSummary>>((ref) async {
  final service = ref.read(storeServiceProvider);
  return service.fetchBrandStores();
});

// ============================================================
// brandDetailsProvider — 品牌完整信息（品牌+门店+管理员）
// ============================================================
final brandDetailsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final service = ref.read(storeServiceProvider);
  return service.fetchBrandDetails();
});

// ============================================================
// StaffNotifier — 员工列表 + 邀请管理
// ============================================================
class StaffNotifier
    extends AsyncNotifier<({List<StaffMember> staff, List<StaffInvitation> invitations})> {
  late StoreService _service;

  @override
  Future<({List<StaffMember> staff, List<StaffInvitation> invitations})> build() async {
    _service = ref.read(storeServiceProvider);
    return _service.fetchStaff();
  }

  /// 刷新员工列表
  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _service.fetchStaff());
  }

  /// 邀请员工
  Future<void> inviteStaff({
    required String email,
    required String role,
  }) async {
    await _service.inviteStaff(email: email, role: role);
    await refresh();
  }

  /// 修改员工角色/昵称/启用状态
  Future<void> updateStaff({
    required String staffId,
    String? role,
    String? nickname,
    bool? isActive,
  }) async {
    await _service.updateStaff(
      staffId: staffId,
      role: role,
      nickname: nickname,
      isActive: isActive,
    );
    await refresh();
  }

  /// 移除员工
  Future<void> removeStaff(String staffId) async {
    await _service.removeStaff(staffId);
    await refresh();
  }
}

// ============================================================
// staffProvider — 员工列表 provider
// ============================================================
final staffProvider = AsyncNotifierProvider<
    StaffNotifier,
    ({List<StaffMember> staff, List<StaffInvitation> invitations})>(
  StaffNotifier.new,
);

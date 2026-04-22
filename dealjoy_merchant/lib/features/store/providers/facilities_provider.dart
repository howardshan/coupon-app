import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/store_facility_model.dart';
import '../services/store_service.dart';
import 'store_provider.dart';

// ============================================================
// FacilitiesProvider — 设施列表 AsyncNotifier
// ============================================================

final facilitiesProvider =
    AsyncNotifierProvider<FacilitiesNotifier, List<StoreFacilityModel>>(
  FacilitiesNotifier.new,
);

class FacilitiesNotifier extends AsyncNotifier<List<StoreFacilityModel>> {
  late StoreService _service;

  @override
  Future<List<StoreFacilityModel>> build() async {
    _service = ref.read(storeServiceProvider);
    return await _service.fetchFacilities();
  }

  // ----------------------------------------------------------
  // 新增设施（乐观更新：先追加占位，成功后替换真实数据）
  // ----------------------------------------------------------
  Future<void> create({
    required String facilityType,
    required String name,
    String? description,
    String? imageUrl,
    int? capacity,
    bool isFree = true,
  }) async {
    final current = state.valueOrNull ?? [];
    try {
      final created = await _service.createFacility(
        facilityType: facilityType,
        name: name,
        description: description,
        imageUrl: imageUrl,
        capacity: capacity,
        isFree: isFree,
      );
      state = AsyncValue.data([...current, created]);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  // ----------------------------------------------------------
  // 更新设施（乐观更新）
  // ----------------------------------------------------------
  Future<void> updateFacility(
    String facilityId, {
    String? facilityType,
    String? name,
    String? description,
    String? imageUrl,
    int? capacity,
    bool? isFree,
    bool clearImageUrl = false,
    bool clearDescription = false,
    bool clearCapacity = false,
  }) async {
    final current = state.valueOrNull ?? [];
    // 乐观更新：先用本地值替换
    final optimistic = current.map((f) {
      if (f.id != facilityId) return f;
      return f.copyWith(
        facilityType: facilityType,
        name: name,
        description: description,
        imageUrl: imageUrl,
        capacity: capacity,
        isFree: isFree,
        clearImageUrl: clearImageUrl,
        clearDescription: clearDescription,
        clearCapacity: clearCapacity,
      );
    }).toList();
    state = AsyncValue.data(optimistic);

    try {
      final updated = await _service.updateFacility(
        facilityId,
        facilityType: facilityType,
        name: name,
        description: description,
        imageUrl: imageUrl,
        capacity: capacity,
        isFree: isFree,
        clearImageUrl: clearImageUrl,
        clearDescription: clearDescription,
        clearCapacity: clearCapacity,
      );
      state = AsyncValue.data(
        current.map((f) => f.id == facilityId ? updated : f).toList(),
      );
    } catch (e, st) {
      // 回滚
      state = AsyncValue.data(current);
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  // ----------------------------------------------------------
  // 删除设施（乐观删除）
  // ----------------------------------------------------------
  Future<void> delete(String facilityId) async {
    final current = state.valueOrNull ?? [];
    state = AsyncValue.data(current.where((f) => f.id != facilityId).toList());

    try {
      await _service.deleteFacility(facilityId);
    } catch (e, st) {
      // 回滚
      state = AsyncValue.data(current);
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  // ----------------------------------------------------------
  // 重新加载（下拉刷新）
  // ----------------------------------------------------------
  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _service.fetchFacilities());
  }
}

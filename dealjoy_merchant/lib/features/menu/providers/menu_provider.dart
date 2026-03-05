// 菜品管理 Riverpod Provider
// 使用 AsyncNotifier 管理 MenuItem 列表状态

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/menu_item.dart';
import '../services/menu_service.dart';

// ============================================================
// MenuService Provider
// ============================================================
final menuServiceProvider = Provider<MenuService>((ref) {
  return MenuService(Supabase.instance.client);
});

// ============================================================
// MenuNotifier — AsyncNotifier<List<MenuItem>>
// ============================================================
class MenuNotifier extends AsyncNotifier<List<MenuItem>> {
  late MenuService _service;
  late String _merchantId;

  @override
  Future<List<MenuItem>> build() async {
    _service = ref.read(menuServiceProvider);

    // 获取当前商家 ID
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) throw Exception('Not authenticated');

    final merchantData = await Supabase.instance.client
        .from('merchants')
        .select('id')
        .eq('user_id', user.id)
        .single();

    _merchantId = merchantData['id'] as String;

    return await _service.fetchMenuItems(_merchantId);
  }

  String get merchantId => _merchantId;

  // ----------------------------------------------------------
  // 刷新列表
  // ----------------------------------------------------------
  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => _service.fetchMenuItems(_merchantId),
    );
  }

  // ----------------------------------------------------------
  // 创建菜品
  // ----------------------------------------------------------
  Future<MenuItem> createItem(MenuItem item) async {
    final newItem = await _service.createMenuItem(
      item.copyWith(merchantId: _merchantId),
    );

    final current = state.valueOrNull ?? [];
    state = AsyncValue.data([...current, newItem]);

    return newItem;
  }

  // ----------------------------------------------------------
  // 更新菜品
  // ----------------------------------------------------------
  Future<void> updateItem(MenuItem item) async {
    final current = state.valueOrNull ?? [];

    // 乐观更新
    final updatedList = current
        .map((i) => i.id == item.id ? item : i)
        .toList();
    state = AsyncValue.data(updatedList);

    try {
      final updated = await _service.updateMenuItem(item);
      final finalList = current
          .map((i) => i.id == item.id ? updated : i)
          .toList();
      state = AsyncValue.data(finalList);
    } catch (e, st) {
      state = AsyncValue.data(current);
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  // ----------------------------------------------------------
  // 删除菜品
  // ----------------------------------------------------------
  Future<void> deleteItem(String id) async {
    final current = state.valueOrNull ?? [];
    final updatedList = current.where((i) => i.id != id).toList();
    state = AsyncValue.data(updatedList);

    try {
      await _service.deleteMenuItem(id);
    } catch (e, st) {
      state = AsyncValue.data(current);
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  // ----------------------------------------------------------
  // 切换状态
  // ----------------------------------------------------------
  Future<void> toggleStatus(String id) async {
    final current = state.valueOrNull ?? [];
    final item = current.firstWhere((i) => i.id == id);
    final newStatus = item.isActive ? 'inactive' : 'active';

    // 乐观更新
    final updatedList = current
        .map((i) => i.id == id ? i.copyWith(status: newStatus) : i)
        .toList();
    state = AsyncValue.data(updatedList);

    try {
      await _service.toggleStatus(id, newStatus);
    } catch (e, st) {
      state = AsyncValue.data(current);
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  // ----------------------------------------------------------
  // 上传菜品图片
  // ----------------------------------------------------------
  Future<String> uploadImage(XFile file) async {
    return await _service.uploadMenuItemImage(
      merchantId: _merchantId,
      file: file,
    );
  }
}

// ============================================================
// menuProvider — 全局单例
// ============================================================
final menuProvider =
    AsyncNotifierProvider<MenuNotifier, List<MenuItem>>(MenuNotifier.new);

// ============================================================
// activeMenuItemsProvider — 仅返回 active 状态的菜品（用于 Deal 创建选择）
// ============================================================
final activeMenuItemsProvider = Provider<AsyncValue<List<MenuItem>>>((ref) {
  return ref.watch(menuProvider).whenData(
        (items) => items.where((i) => i.isActive).toList(),
      );
});

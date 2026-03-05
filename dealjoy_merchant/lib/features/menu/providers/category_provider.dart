// 菜品分类 Riverpod Provider
// 使用 AsyncNotifier 管理 MenuCategory 列表状态

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/menu_category.dart';
import '../services/category_service.dart';

// ============================================================
// CategoryService Provider
// ============================================================
final categoryServiceProvider = Provider<CategoryService>((ref) {
  return CategoryService(Supabase.instance.client);
});

// ============================================================
// CategoryNotifier — AsyncNotifier<List<MenuCategory>>
// ============================================================
class CategoryNotifier extends AsyncNotifier<List<MenuCategory>> {
  late CategoryService _service;
  late String _merchantId;

  @override
  Future<List<MenuCategory>> build() async {
    _service = ref.read(categoryServiceProvider);

    // 获取当前商家 ID
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return [];

    try {
      final merchantData = await Supabase.instance.client
          .from('merchants')
          .select('id')
          .eq('user_id', user.id)
          .maybeSingle();

      if (merchantData == null) return [];

      _merchantId = merchantData['id'] as String;
      return await _service.fetchCategories(_merchantId);
    } catch (e) {
      // 查询失败时返回空列表，不阻塞页面
      return [];
    }
  }

  String get merchantId => _merchantId;

  // ----------------------------------------------------------
  // 刷新列表
  // ----------------------------------------------------------
  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => _service.fetchCategories(_merchantId),
    );
  }

  // ----------------------------------------------------------
  // 创建分类
  // ----------------------------------------------------------
  Future<MenuCategory> create(String name) async {
    final current = state.valueOrNull ?? [];
    final sortOrder = current.length;

    final newCategory = await _service.createCategory(
      merchantId: _merchantId,
      name: name,
      sortOrder: sortOrder,
    );

    state = AsyncValue.data([...current, newCategory]);
    return newCategory;
  }

  // ----------------------------------------------------------
  // 重命名分类
  // ----------------------------------------------------------
  Future<void> rename(String id, String newName) async {
    final current = state.valueOrNull ?? [];

    // 乐观更新
    final updatedList = current
        .map((c) => c.id == id ? c.copyWith(name: newName) : c)
        .toList();
    state = AsyncValue.data(updatedList);

    try {
      await _service.updateCategory(id: id, name: newName);
    } catch (e, st) {
      state = AsyncValue.data(current);
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  // ----------------------------------------------------------
  // 删除分类
  // ----------------------------------------------------------
  Future<void> delete(String id) async {
    final current = state.valueOrNull ?? [];
    final updatedList = current.where((c) => c.id != id).toList();
    state = AsyncValue.data(updatedList);

    try {
      await _service.deleteCategory(id);
    } catch (e, st) {
      state = AsyncValue.data(current);
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  // ----------------------------------------------------------
  // 重新排序
  // ----------------------------------------------------------
  Future<void> reorder(int oldIndex, int newIndex) async {
    final current = List<MenuCategory>.from(state.valueOrNull ?? []);
    if (newIndex > oldIndex) newIndex -= 1;

    final item = current.removeAt(oldIndex);
    current.insert(newIndex, item);

    // 更新 sort_order
    final reordered = List.generate(
      current.length,
      (i) => current[i].copyWith(sortOrder: i),
    );

    state = AsyncValue.data(reordered);

    try {
      await _service.reorderCategories(reordered);
    } catch (_) {
      // 回滚
      state = await AsyncValue.guard(
        () => _service.fetchCategories(_merchantId),
      );
    }
  }
}

// ============================================================
// categoryProvider — 全局单例
// ============================================================
final categoryProvider =
    AsyncNotifierProvider<CategoryNotifier, List<MenuCategory>>(
        CategoryNotifier.new);

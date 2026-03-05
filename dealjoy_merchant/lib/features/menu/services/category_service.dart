// 菜品分类服务层
// 负责 menu_categories 表的 CRUD 操作

import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/menu_category.dart';

// ============================================================
// CategoryService — 分类 CRUD
// ============================================================
class CategoryService {
  CategoryService(this._supabase);

  final SupabaseClient _supabase;

  // ----------------------------------------------------------
  // 获取商家的所有分类（按 sort_order 排序）
  // ----------------------------------------------------------
  Future<List<MenuCategory>> fetchCategories(String merchantId) async {
    final data = await _supabase
        .from('menu_categories')
        .select()
        .eq('merchant_id', merchantId)
        .order('sort_order', ascending: true);

    return (data as List<dynamic>)
        .map((e) => MenuCategory.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ----------------------------------------------------------
  // 创建分类
  // ----------------------------------------------------------
  Future<MenuCategory> createCategory({
    required String merchantId,
    required String name,
    required int sortOrder,
  }) async {
    final data = await _supabase
        .from('menu_categories')
        .insert({
          'merchant_id': merchantId,
          'name': name,
          'sort_order': sortOrder,
        })
        .select()
        .single();

    return MenuCategory.fromJson(data);
  }

  // ----------------------------------------------------------
  // 更新分类名称
  // ----------------------------------------------------------
  Future<MenuCategory> updateCategory({
    required String id,
    required String name,
  }) async {
    final data = await _supabase
        .from('menu_categories')
        .update({'name': name})
        .eq('id', id)
        .select()
        .single();

    return MenuCategory.fromJson(data);
  }

  // ----------------------------------------------------------
  // 删除分类（关联菜品的 category_id 会被置为 null）
  // ----------------------------------------------------------
  Future<void> deleteCategory(String id) async {
    await _supabase.from('menu_categories').delete().eq('id', id);
  }

  // ----------------------------------------------------------
  // 批量更新排序
  // ----------------------------------------------------------
  Future<void> reorderCategories(List<MenuCategory> categories) async {
    // 逐条更新 sort_order
    for (int i = 0; i < categories.length; i++) {
      await _supabase
          .from('menu_categories')
          .update({'sort_order': i})
          .eq('id', categories[i].id);
    }
  }
}

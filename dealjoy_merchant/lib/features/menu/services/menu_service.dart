// 菜品管理服务层
// 负责 menu_items 表的 CRUD 操作

import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/menu_item.dart';

// ============================================================
// MenuService — 菜品 CRUD + 图片上传
// ============================================================
class MenuService {
  MenuService(this._supabase);

  final SupabaseClient _supabase;

  // ----------------------------------------------------------
  // 获取商家的所有菜品
  // ----------------------------------------------------------
  Future<List<MenuItem>> fetchMenuItems(String merchantId) async {
    // join menu_categories 获取分类名称
    final data = await _supabase
        .from('menu_items')
        .select('*, menu_categories(name)')
        .eq('merchant_id', merchantId)
        .order('sort_order', ascending: true);

    return (data as List<dynamic>)
        .map((e) => MenuItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ----------------------------------------------------------
  // 创建菜品
  // ----------------------------------------------------------
  Future<MenuItem> createMenuItem(MenuItem item) async {
    final data = await _supabase
        .from('menu_items')
        .insert(item.toJson())
        .select()
        .single();

    return MenuItem.fromJson(data);
  }

  // ----------------------------------------------------------
  // 更新菜品
  // ----------------------------------------------------------
  Future<MenuItem> updateMenuItem(MenuItem item) async {
    final data = await _supabase
        .from('menu_items')
        .update(item.toJson())
        .eq('id', item.id)
        .select()
        .single();

    return MenuItem.fromJson(data);
  }

  // ----------------------------------------------------------
  // 删除菜品
  // ----------------------------------------------------------
  Future<void> deleteMenuItem(String id) async {
    await _supabase.from('menu_items').delete().eq('id', id);
  }

  // ----------------------------------------------------------
  // 切换菜品状态（active/inactive）
  // ----------------------------------------------------------
  Future<void> toggleStatus(String id, String status) async {
    await _supabase
        .from('menu_items')
        .update({'status': status})
        .eq('id', id);
  }

  // ----------------------------------------------------------
  // 上传菜品图片到 Supabase Storage
  // ----------------------------------------------------------
  Future<String> uploadMenuItemImage({
    required String merchantId,
    required XFile file,
  }) async {
    final bytes = await File(file.path).readAsBytes();
    final ext = file.path.split('.').last.toLowerCase();
    final fileName = '${DateTime.now().millisecondsSinceEpoch}.$ext';
    final storagePath = '$merchantId/menu/$fileName';

    await _supabase.storage.from('merchant-photos').uploadBinary(
          storagePath,
          bytes,
          fileOptions: FileOptions(
            contentType: ext == 'png' ? 'image/png' : 'image/jpeg',
            upsert: true,
          ),
        );

    // 返回公开 URL
    return _supabase.storage.from('merchant-photos').getPublicUrl(storagePath);
  }
}

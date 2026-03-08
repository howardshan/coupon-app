// Deal管理服务层
// 负责: 获取Deal列表、创建Deal、更新Deal、上下架、删除、上传图片
// 通过 Edge Function merchant-deals 与后端交互

import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/deal_template.dart';
import '../models/merchant_deal.dart';

// ============================================================
// DealsService — 所有 Deal 管理相关的 Supabase 操作
// ============================================================
class DealsService {
  DealsService(this._supabase);

  final SupabaseClient _supabase;

  /// Edge Function 名称
  static const String _functionName = 'merchant-deals';

  /// Supabase Storage bucket 名称（Deal 图片）
  static const String _storageBucket = 'deal-images';

  // ----------------------------------------------------------
  // 1. 获取商家所有 Deals（支持状态筛选）
  // ----------------------------------------------------------
  Future<List<MerchantDeal>> fetchDeals(
    String merchantId, {
    DealStatus? filter,
  }) async {
    // 构建查询参数
    final queryParams = <String, String>{};
    if (filter != null) {
      queryParams['status'] = filter.value;
    }

    final response = await _supabase.functions.invoke(
      _functionName,
      method: HttpMethod.get,
      queryParameters: queryParams,
    );

    if (response.status != 200) {
      throw _handleError(response);
    }

    final data = response.data as Map<String, dynamic>;
    final dealsJson = data['deals'] as List<dynamic>? ?? [];

    return dealsJson
        .map((e) => MerchantDeal.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ----------------------------------------------------------
  // 2. 创建新 Deal（提交后状态为 pending，等待审核）
  // ----------------------------------------------------------
  Future<MerchantDeal> createDeal(MerchantDeal deal) async {
    final response = await _supabase.functions.invoke(
      _functionName,
      method: HttpMethod.post,
      body: deal.toJson(),
    );

    if (response.status != 200 && response.status != 201) {
      throw _handleError(response);
    }

    final data = response.data as Map<String, dynamic>;
    return MerchantDeal.fromJson(data['deal'] as Map<String, dynamic>);
  }

  // ----------------------------------------------------------
  // 3. 更新 Deal（修改后状态重置为 pending，需重新审核）
  // ----------------------------------------------------------
  Future<MerchantDeal> updateDeal(MerchantDeal deal) async {
    final response = await _supabase.functions.invoke(
      '$_functionName/${deal.id}',
      method: HttpMethod.patch,
      body: deal.toJson(),
    );

    if (response.status != 200) {
      throw _handleError(response);
    }

    final data = response.data as Map<String, dynamic>;
    return MerchantDeal.fromJson(data['deal'] as Map<String, dynamic>);
  }

  // ----------------------------------------------------------
  // 4. 上下架切换
  //    isActive=true: 上架(active), isActive=false: 下架(inactive)
  //    注意: pending/rejected 状态不允许上架
  // ----------------------------------------------------------
  Future<void> toggleDealStatus(String dealId, bool isActive) async {
    final response = await _supabase.functions.invoke(
      '$_functionName/$dealId/status',
      method: HttpMethod.patch,
      body: {'is_active': isActive},
    );

    if (response.status != 200) {
      throw _handleError(response);
    }
  }

  // ----------------------------------------------------------
  // 5. 删除 Deal（仅 inactive 状态可删除）
  // ----------------------------------------------------------
  Future<void> deleteDeal(String dealId) async {
    final response = await _supabase.functions.invoke(
      '$_functionName/$dealId',
      method: HttpMethod.delete,
    );

    if (response.status != 200) {
      throw _handleError(response);
    }
  }

  // ----------------------------------------------------------
  // 6. 上传 Deal 图片
  //    步骤: 压缩 → 上传到 Storage → 通知 Edge Function 保存记录
  //    merchantId: 商家 ID（用于 Storage 路径）
  //    dealId: Deal ID
  //    file: XFile（来自 image_picker）
  //    sortOrder: 排序（0-based）
  //    isPrimary: 是否设为主图
  // ----------------------------------------------------------
  Future<DealImage> uploadDealImage({
    required String merchantId,
    required String dealId,
    required XFile file,
    int sortOrder = 0,
    bool isPrimary = false,
  }) async {
    // 6.1 生成唯一存储路径: {merchant_id}/{deal_id}/{timestamp}.jpg
    final fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';
    final storagePath = '$merchantId/$dealId/$fileName';

    // 6.2 读取文件字节（image_picker 已完成压缩选项处理）
    final bytes = await file.readAsBytes();

    // 6.3 上传到 Supabase Storage
    await _supabase.storage.from(_storageBucket).uploadBinary(
          storagePath,
          bytes,
          fileOptions: const FileOptions(
            contentType: 'image/jpeg',
            upsert: false,
          ),
        );

    // 6.4 获取公开 URL
    final publicUrl =
        _supabase.storage.from(_storageBucket).getPublicUrl(storagePath);

    // 6.5 通知 Edge Function 保存图片记录
    final response = await _supabase.functions.invoke(
      '$_functionName/$dealId/images',
      method: HttpMethod.post,
      body: {
        'image_url':  publicUrl,
        'sort_order': sortOrder,
        'is_primary': isPrimary,
      },
    );

    if (response.status != 200 && response.status != 201) {
      // 上传记录失败，回滚删除 Storage 文件
      try {
        await _supabase.storage.from(_storageBucket).remove([storagePath]);
      } catch (_) {
        // 回滚失败不阻塞主流程
      }
      throw _handleError(response);
    }

    final data = response.data as Map<String, dynamic>;
    return DealImage.fromJson(data['image'] as Map<String, dynamic>);
  }

  // ----------------------------------------------------------
  // 7. 删除 Deal 图片（删除 DB 记录 + Storage 文件）
  //    imageUrl: Storage 公开 URL（解析出路径）
  //    imageId: deal_images 表中的记录 ID
  // ----------------------------------------------------------
  Future<void> deleteDealImage({
    required String dealId,
    required String imageId,
    required String imageUrl,
  }) async {
    // 7.1 从数据库删除记录
    await _supabase
        .from('deal_images')
        .delete()
        .eq('id', imageId);

    // 7.2 从 Storage 删除文件（解析 URL 中的路径）
    try {
      // URL 格式: .../storage/v1/object/public/{bucket}/{path}
      final uri = Uri.parse(imageUrl);
      final pathSegments = uri.pathSegments;
      final bucketIndex = pathSegments.indexOf(_storageBucket);
      if (bucketIndex >= 0) {
        final storagePath =
            pathSegments.sublist(bucketIndex + 1).join('/');
        await _supabase.storage.from(_storageBucket).remove([storagePath]);
      }
    } catch (_) {
      // Storage 删除失败不阻塞（可异步清理）
    }
  }

  // ----------------------------------------------------------
  // 错误处理辅助方法
  // ----------------------------------------------------------
  Exception _handleError(FunctionResponse response) {
    final data = response.data;
    String message = 'Unknown error';

    if (data is Map<String, dynamic> && data.containsKey('error')) {
      message = data['error'] as String;
    }

    return Exception('DealsService error (${response.status}): $message');
  }

  // ----------------------------------------------------------
  // Deal Categories（直接查表，不走 Edge Function）
  // ----------------------------------------------------------

  /// 获取当前商家的 deal 分类列表
  Future<List<Map<String, dynamic>>> fetchDealCategories(String merchantId) async {
    final data = await _supabase
        .from('deal_categories')
        .select()
        .eq('merchant_id', merchantId)
        .order('sort_order');
    return List<Map<String, dynamic>>.from(data);
  }

  /// 创建 deal 分类
  Future<Map<String, dynamic>> createDealCategory({
    required String merchantId,
    required String name,
    required int sortOrder,
  }) async {
    final data = await _supabase
        .from('deal_categories')
        .insert({
          'merchant_id': merchantId,
          'name': name,
          'sort_order': sortOrder,
        })
        .select()
        .single();
    return data;
  }

  /// 更新 deal 分类名称
  Future<void> updateDealCategory({
    required String id,
    required String name,
  }) async {
    await _supabase
        .from('deal_categories')
        .update({'name': name})
        .eq('id', id);
  }

  /// 删除 deal 分类
  Future<void> deleteDealCategory(String id) async {
    await _supabase
        .from('deal_categories')
        .delete()
        .eq('id', id);
  }

  // ----------------------------------------------------------
  // V2.2 Deal 模板管理（品牌级一键多店发布）
  // 通过 merchant-deals Edge Function 的 /templates 子路由
  // ----------------------------------------------------------

  /// 获取品牌下所有 Deal 模板
  Future<List<DealTemplate>> fetchTemplates() async {
    final response = await _supabase.functions.invoke(
      '$_functionName/templates',
      method: HttpMethod.get,
    );

    if (response.status != 200) {
      throw _handleError(response);
    }

    final data = response.data as Map<String, dynamic>;
    final list = data['templates'] as List<dynamic>? ?? [];
    return list
        .map((e) => DealTemplate.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 创建 Deal 模板
  Future<DealTemplate> createTemplate(DealTemplate template) async {
    final response = await _supabase.functions.invoke(
      '$_functionName/templates',
      method: HttpMethod.post,
      body: template.toJson(),
    );

    if (response.status != 200 && response.status != 201) {
      throw _handleError(response);
    }

    final data = response.data as Map<String, dynamic>;
    return DealTemplate.fromJson(data['template'] as Map<String, dynamic>);
  }

  /// 更新 Deal 模板
  Future<DealTemplate> updateTemplate(String templateId, Map<String, dynamic> updates) async {
    final response = await _supabase.functions.invoke(
      '$_functionName/templates/$templateId',
      method: HttpMethod.patch,
      body: updates,
    );

    if (response.status != 200) {
      throw _handleError(response);
    }

    final data = response.data as Map<String, dynamic>;
    return DealTemplate.fromJson(data['template'] as Map<String, dynamic>);
  }

  /// 发布模板到指定门店（为每个门店创建独立 Deal）
  Future<Map<String, dynamic>> publishTemplate(
    String templateId,
    List<String> merchantIds,
  ) async {
    final response = await _supabase.functions.invoke(
      '$_functionName/templates/$templateId/publish',
      method: HttpMethod.post,
      body: {'merchant_ids': merchantIds},
    );

    if (response.status != 200) {
      throw _handleError(response);
    }

    // 返回 { published: int, errors: [...] }
    return response.data as Map<String, dynamic>;
  }

  /// 同步模板更新到所有未自定义的关联门店
  Future<Map<String, dynamic>> syncTemplate(String templateId) async {
    final response = await _supabase.functions.invoke(
      '$_functionName/templates/$templateId/sync',
      method: HttpMethod.post,
      body: {},
    );

    if (response.status != 200) {
      throw _handleError(response);
    }

    // 返回 { synced: int }
    return response.data as Map<String, dynamic>;
  }

  /// 删除 Deal 模板
  Future<void> deleteTemplate(String templateId) async {
    final response = await _supabase.functions.invoke(
      '$_functionName/templates/$templateId',
      method: HttpMethod.delete,
    );

    if (response.status != 200) {
      throw _handleError(response);
    }
  }
}

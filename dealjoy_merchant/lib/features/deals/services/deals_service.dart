// Deal管理服务层
// 负责: 获取Deal列表、创建Deal、更新Deal、上下架、删除、上传图片
// 通过 Edge Function merchant-deals 与后端交互

import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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
}

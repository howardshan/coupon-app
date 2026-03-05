// 门店信息服务层
// 负责: 获取门店信息、更新基本信息、更新营业时间、上传/删除照片、重排序

import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/store_info.dart';

// ============================================================
// StoreService — 所有门店信息相关的 Supabase 操作
// 通过 Edge Function merchant-store 与后端交互
// ============================================================
class StoreService {
  StoreService(this._supabase);

  final SupabaseClient _supabase;

  // Edge Function 基础 URL 路径
  static const String _functionName = 'merchant-store';

  // ----------------------------------------------------------
  // 确保 access token 有效（functions.invoke 不会自动刷新）
  // ----------------------------------------------------------
  Future<void> _ensureFreshSession() async {
    final session = _supabase.auth.currentSession;
    print('[StoreService] currentSession: ${session != null ? "EXISTS" : "NULL"}');
    if (session != null) {
      final expiresAt = session.expiresAt;
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      print('[StoreService] token expiresAt: $expiresAt, now: $now, diff: ${(expiresAt ?? 0) - now}s');
      print('[StoreService] accessToken prefix: ${session.accessToken.substring(0, 20)}...');
    }
    if (session == null) return;
    try {
      print('[StoreService] Attempting refreshSession...');
      await _supabase.auth.refreshSession();
      final newSession = _supabase.auth.currentSession;
      print('[StoreService] refreshSession OK, new expiresAt: ${newSession?.expiresAt}');
    } catch (e) {
      print('[StoreService] refreshSession FAILED: $e');
    }
  }

  // ----------------------------------------------------------
  // 1. 获取完整门店信息（基本信息 + 照片 + 营业时间 + 专业资料）
  // ----------------------------------------------------------
  Future<StoreInfo> fetchStoreInfo() async {
    await _ensureFreshSession();
    final response = await _supabase.functions.invoke(
      _functionName,
      method: HttpMethod.get,
    );

    if (response.status != 200) {
      throw _handleError(response);
    }

    var storeInfo = StoreInfo.fromJson(response.data as Map<String, dynamic>);

    // 补充查询：如果 Edge Function 没返回专业资料，直接查 merchants 表
    if (storeInfo.companyName == null || storeInfo.companyName!.isEmpty) {
      storeInfo = await _enrichWithMerchantData(storeInfo);
    }

    // 补充查询：从 merchant_documents 获取注册时上传的所有证件（含门头照）
    storeInfo = await _enrichWithDocuments(storeInfo);

    return storeInfo;
  }

  // 从 merchants 表补充专业资料字段
  Future<StoreInfo> _enrichWithMerchantData(StoreInfo store) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return store;

      final data = await _supabase
          .from('merchants')
          .select('company_name, contact_name, contact_email, ein, city, website')
          .eq('user_id', userId)
          .maybeSingle();

      if (data == null) return store;

      return store.copyWith(
        companyName: data['company_name'] as String?,
        contactName: data['contact_name'] as String?,
        contactEmail: data['contact_email'] as String?,
        ein: data['ein'] as String?,
        city: data['city'] as String?,
        website: data['website'] as String?,
      );
    } catch (_) {
      return store;
    }
  }

  // 从 merchant_documents 表获取注册时上传的所有证件（含门头照）
  Future<StoreInfo> _enrichWithDocuments(StoreInfo store) async {
    try {
      final rows = await _supabase
          .from('merchant_documents')
          .select('document_type, file_url')
          .eq('merchant_id', store.id);

      if ((rows as List).isEmpty) return store;

      final docs = (rows as List<dynamic>)
          .map((e) => MerchantDoc.fromJson(e as Map<String, dynamic>))
          .toList();

      // 从证件列表中提取门头照 URL
      String? storefrontUrl = store.registrationStorefrontUrl;
      if (storefrontUrl == null) {
        final storefrontDoc = docs.where((d) => d.documentType == 'storefront_photo').firstOrNull;
        storefrontUrl = storefrontDoc?.fileUrl;
      }

      return store.copyWith(
        registrationStorefrontUrl: storefrontUrl,
        documents: docs,
      );
    } catch (_) {
      return store;
    }
  }

  // ----------------------------------------------------------
  // 2. 更新门店基本信息（店名、简介、电话、地址、标签）
  // ----------------------------------------------------------
  Future<void> updateStoreInfo({
    String? name,
    String? description,
    String? phone,
    String? address,
    List<String>? tags,
  }) async {
    // 构造只包含非空字段的更新体
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (description != null) body['description'] = description;
    if (phone != null) body['phone'] = phone;
    if (address != null) body['address'] = address;
    if (tags != null) body['tags'] = tags;

    if (body.isEmpty) return; // 没有变更，直接返回

    await _ensureFreshSession();
    final response = await _supabase.functions.invoke(
      _functionName,
      method: HttpMethod.patch,
      body: body,
    );

    if (response.status != 200) {
      throw _handleError(response);
    }
  }

  // ----------------------------------------------------------
  // 3. 批量更新 7 天营业时间
  //    传入全部 7 天的配置，Edge Function 做 upsert
  // ----------------------------------------------------------
  Future<List<BusinessHours>> updateBusinessHours(
    List<BusinessHours> hours,
  ) async {
    await _ensureFreshSession();
    final response = await _supabase.functions.invoke(
      _functionName,
      method: HttpMethod.put,
      body: {
        'hours': hours.map((h) => h.toJson()).toList(),
      },
      // Edge Function 路由: PUT /merchant-store/hours
      // supabase_flutter invoke 方法需要在 function name 后加子路径
    );

    // 注意：supabase_flutter 的 invoke 暂不支持子路径，改用 HTTP 客户端直接调用
    // 此处通过 _invokeWithPath 辅助方法实现
    if (response.status != 200) {
      throw _handleError(response);
    }

    final data = response.data as Map<String, dynamic>;
    final hoursList = data['hours'] as List<dynamic>? ?? [];
    return hoursList
        .map((e) => BusinessHours.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ----------------------------------------------------------
  // 4. 上传照片
  //    步骤: image_picker 获取文件 → 上传到 Storage → 通知 Edge Function 保存记录
  // ----------------------------------------------------------
  Future<StorePhoto> uploadPhoto({
    required String merchantId,
    required XFile file,
    required StorePhotoType type,
    int sortOrder = 0,
  }) async {
    // 4.1 生成唯一文件路径: {merchant_id}/{photo_type}/{timestamp}.jpg
    final fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';
    final storagePath = '$merchantId/${type.value}/$fileName';

    // 4.2 读取文件字节并上传到 Supabase Storage
    final bytes = await file.readAsBytes();
    await _supabase.storage.from('merchant-photos').uploadBinary(
          storagePath,
          bytes,
          fileOptions: const FileOptions(
            contentType: 'image/jpeg',
            upsert: false,
          ),
        );

    // 4.3 获取公开 URL
    final publicUrl =
        _supabase.storage.from('merchant-photos').getPublicUrl(storagePath);

    // 4.4 通知 Edge Function 保存照片记录到 merchant_photos 表
    await _ensureFreshSession();
    final response = await _supabase.functions.invoke(
      '$_functionName/photos',
      method: HttpMethod.post,
      body: {
        'photo_url': publicUrl,
        'photo_type': type.value,
        'sort_order': sortOrder,
      },
    );

    if (response.status != 200 && response.status != 201) {
      // 上传记录失败，尝试删除已上传的 Storage 文件（回滚）
      try {
        await _supabase.storage.from('merchant-photos').remove([storagePath]);
      } catch (_) {
        // 回滚失败不阻塞
      }
      throw _handleError(response);
    }

    final data = response.data as Map<String, dynamic>;
    return StorePhoto.fromJson(data['photo'] as Map<String, dynamic>);
  }

  // ----------------------------------------------------------
  // 5. 删除照片（删除 DB 记录 + Storage 文件）
  //    Edge Function DELETE /merchant-store/photos/:id 负责双删
  // ----------------------------------------------------------
  Future<void> deletePhoto(String photoId) async {
    await _ensureFreshSession();
    final response = await _supabase.functions.invoke(
      '$_functionName/photos/$photoId',
      method: HttpMethod.delete,
    );

    if (response.status != 200) {
      throw _handleError(response);
    }
  }

  // ----------------------------------------------------------
  // 6. 重排序照片（批量更新 sort_order）
  //    orderedIds: 照片 ID 列表，顺序即为新的 sort_order (0, 1, 2...)
  //    通过 Edge Function 调用，确保权限验证
  // ----------------------------------------------------------
  Future<void> reorderPhotos(List<String> orderedIds) async {
    await _ensureFreshSession();
    final response = await _supabase.functions.invoke(
      '$_functionName/photos/reorder',
      method: HttpMethod.patch,
      body: {'ordered_ids': orderedIds},
    );

    if (response.status != 200) {
      throw _handleError(response);
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

    return Exception('StoreService error (${response.status}): $message');
  }
}

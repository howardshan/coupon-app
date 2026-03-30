// 门店信息服务层
// 负责: 获取门店信息、更新基本信息、更新营业时间、上传/删除照片、重排序

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/store_info.dart';
import '../models/store_summary.dart';
import '../models/staff_member.dart';

// ============================================================
// StoreService — 所有门店信息相关的 Supabase 操作
// 通过 Edge Function merchant-store 与后端交互
// ============================================================
class StoreService {
  StoreService(this._supabase);

  final SupabaseClient _supabase;

  // Edge Function 基础 URL 路径
  static const String _functionName = 'merchant-store';
  static const String _staffFunctionName = 'merchant-staff-mgmt';
  static const String _brandFunctionName = 'merchant-brand';

  // 全局活跃门店 ID（品牌管理员切换门店时设置，所有 service 共享读取）
  static String? globalActiveMerchantId;

  // SharedPreferences key
  static const String _merchantIdKey = 'active_merchant_id';

  // 品牌管理员当前操作的门店 ID（非品牌管理员为 null）
  String? _activeMerchantId;

  /// 设置当前操作的门店 ID（品牌管理员切换门店时调用）
  /// 同时持久化到 SharedPreferences，重启后可恢复
  void setActiveMerchantId(String? merchantId) {
    _activeMerchantId = merchantId;
    // 同步到全局静态变量，供其他 service 读取
    globalActiveMerchantId = merchantId;
    // 持久化（fire-and-forget）
    _persistMerchantId(merchantId);
  }

  /// 持久化门店 ID 到本地存储
  static Future<void> _persistMerchantId(String? merchantId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (merchantId != null) {
        await prefs.setString(_merchantIdKey, merchantId);
      } else {
        await prefs.remove(_merchantIdKey);
      }
    } catch (e) {
      debugPrint('[StoreService] 持久化 merchantId 失败: $e');
    }
  }

  /// App 启动时恢复上次选中的门店 ID（品牌管理员使用）
  /// 返回 true 表示成功恢复了门店 ID
  static Future<bool> restoreActiveMerchantId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedId = prefs.getString(_merchantIdKey);
      if (savedId != null && savedId.isNotEmpty) {
        globalActiveMerchantId = savedId;
        debugPrint('[StoreService] 恢复 activeMerchantId: $savedId');
        return true;
      }
    } catch (e) {
      debugPrint('[StoreService] 恢复 merchantId 失败: $e');
    }
    return false;
  }

  /// 登出时清除持久化的门店 ID
  static Future<void> clearPersistedMerchantId() async {
    globalActiveMerchantId = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_merchantIdKey);
    } catch (e) {
      debugPrint('[StoreService] 清除 merchantId 失败: $e');
    }
  }

  /// 获取当前操作的门店 ID
  String? get activeMerchantId => _activeMerchantId;

  /// 构建带 X-Merchant-Id 的 headers（品牌管理员需要）
  /// 优先用实例变量，fallback 到全局变量（恢复的持久化值）
  Map<String, String> get _merchantHeaders {
    final id = _activeMerchantId ?? globalActiveMerchantId;
    if (id != null) {
      return {'x-merchant-id': id};
    }
    return {};
  }

  /// 静态方法：获取 x-merchant-id headers（供其他 service 使用）
  static Map<String, String> get merchantIdHeaders {
    if (globalActiveMerchantId != null) {
      return {'x-merchant-id': globalActiveMerchantId!};
    }
    return {};
  }

  // ----------------------------------------------------------
  // 确保 access token 有效（functions.invoke 不会自动刷新）
  // ----------------------------------------------------------
  Future<void> _ensureFreshSession() async {
    final session = _supabase.auth.currentSession;
    if (session == null) return;
    try {
      await _supabase.auth.refreshSession();
    } catch (_) {
      // refresh 失败则使用现有 token
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
      headers: _merchantHeaders,
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
    String? city,
    double? lat,
    double? lng,
    List<String>? tags,
    String? headerPhotoStyle,
    List<String>? headerPhotos,
  }) async {
    // 构造只包含非空字段的更新体
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (description != null) body['description'] = description;
    if (phone != null) body['phone'] = phone;
    if (address != null) body['address'] = address;
    if (city != null) body['city'] = city;
    if (lat != null) body['lat'] = lat;
    if (lng != null) body['lng'] = lng;
    if (tags != null) body['tags'] = tags;
    if (headerPhotoStyle != null) body['header_photo_style'] = headerPhotoStyle;
    if (headerPhotos != null) body['header_photos'] = headerPhotos;

    if (body.isEmpty) return; // 没有变更，直接返回

    await _ensureFreshSession();
    final response = await _supabase.functions.invoke(
      _functionName,
      method: HttpMethod.patch,
      body: body,
      headers: _merchantHeaders,
    );

    if (response.status != 200) {
      throw _handleError(response);
    }
  }

  // ----------------------------------------------------------
  // 2b. 上传首页封面图（上传到 Storage → 保存 URL 到 merchants 表）
  // ----------------------------------------------------------
  Future<String> uploadHomepageCover({
    required String merchantId,
    required XFile file,
  }) async {
    final fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';
    final storagePath = '$merchantId/homepage_cover/$fileName';

    final bytes = await file.readAsBytes();
    await _supabase.storage.from('merchant-photos').uploadBinary(
          storagePath,
          bytes,
          fileOptions: const FileOptions(
            contentType: 'image/jpeg',
            upsert: true,
          ),
        );

    final publicUrl =
        _supabase.storage.from('merchant-photos').getPublicUrl(storagePath);

    // 通过 Edge Function PATCH 保存到 merchants 表
    await _ensureFreshSession();
    final response = await _supabase.functions.invoke(
      _functionName,
      method: HttpMethod.patch,
      body: {'homepage_cover_url': publicUrl},
      headers: _merchantHeaders,
    );

    if (response.status != 200) {
      throw _handleError(response);
    }

    return publicUrl;
  }

  // ----------------------------------------------------------
  // 2c. 删除首页封面图
  // ----------------------------------------------------------
  Future<void> deleteHomepageCover({
    required String merchantId,
    required String currentUrl,
  }) async {
    // 从 Storage 删除文件
    try {
      final prefix = _supabase.storage
          .from('merchant-photos')
          .getPublicUrl('');
      if (currentUrl.startsWith(prefix)) {
        final storagePath = currentUrl.replaceFirst(prefix, '');
        await _supabase.storage.from('merchant-photos').remove([storagePath]);
      }
    } catch (_) {
      // Storage 删除失败不阻塞
    }

    // 清空 merchants 表的 homepage_cover_url
    await _ensureFreshSession();
    final response = await _supabase.functions.invoke(
      _functionName,
      method: HttpMethod.patch,
      body: {'homepage_cover_url': null},
      headers: _merchantHeaders,
    );

    if (response.status != 200) {
      throw _handleError(response);
    }
  }

  // ----------------------------------------------------------
  // 2d. 直接更新 homepage_cover_url（用已有的照片 URL，不重新上传）
  // ----------------------------------------------------------
  Future<void> updateHomepageCover(String merchantId, String url) async {
    await _ensureFreshSession();
    final response = await _supabase.functions.invoke(
      _functionName,
      method: HttpMethod.patch,
      body: {'homepage_cover_url': url},
      headers: _merchantHeaders,
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
      '$_functionName/hours',
      method: HttpMethod.put,
      body: {
        'hours': hours.map((h) => h.toJson()).toList(),
      },
      headers: _merchantHeaders,
    );

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
      headers: _merchantHeaders,
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
      headers: _merchantHeaders,
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
      headers: _merchantHeaders,
    );

    if (response.status != 200) {
      throw _handleError(response);
    }
  }

  // ==========================================================
  // 闭店 + 解除品牌
  // ==========================================================

  // ----------------------------------------------------------
  // 闭店（标记 closed + 下架所有 deal）
  // ----------------------------------------------------------
  Future<int> closeStore() async {
    await _ensureFreshSession();
    final response = await _supabase.functions.invoke(
      '$_functionName/close',
      method: HttpMethod.post,
      body: {},
      headers: _merchantHeaders,
    );

    if (response.status != 200) {
      throw _handleError(response);
    }

    final data = response.data as Map<String, dynamic>;
    return data['pending_refund_count'] as int? ?? 0;
  }

  // ----------------------------------------------------------
  // 解除品牌合作
  // ----------------------------------------------------------
  Future<void> leaveBrand() async {
    await _ensureFreshSession();
    final response = await _supabase.functions.invoke(
      '$_functionName/leave-brand',
      method: HttpMethod.post,
      body: {},
      headers: _merchantHeaders,
    );

    if (response.status != 200) {
      throw _handleError(response);
    }
  }

  // ==========================================================
  // 品牌管理相关方法（调 merchant-brand Edge Function）
  // ==========================================================

  // ----------------------------------------------------------
  // 创建品牌（独立门店升级为连锁时调用）
  // ----------------------------------------------------------
  Future<void> createBrand({
    required String name,
    String? description,
  }) async {
    await _ensureFreshSession();
    final body = <String, dynamic>{
      'name': name,
    };
    if (description != null && description.isNotEmpty) {
      body['description'] = description;
    }

    final response = await _supabase.functions.invoke(
      _brandFunctionName,
      method: HttpMethod.post,
      body: body,
      headers: _merchantHeaders,
    );

    if (response.status != 200 && response.status != 201) {
      throw _handleError(response);
    }
  }

  // ----------------------------------------------------------
  // 获取品牌管理员旗下所有门店列表
  // ----------------------------------------------------------
  Future<List<StoreSummary>> fetchBrandStores() async {
    await _ensureFreshSession();
    final response = await _supabase.functions.invoke(
      '$_functionName/stores-list',
      method: HttpMethod.get,
      headers: _merchantHeaders,
    );

    if (response.status != 200) {
      throw _handleError(response);
    }

    final data = response.data as Map<String, dynamic>;
    final stores = data['stores'] as List<dynamic>? ?? [];
    return stores
        .map((e) => StoreSummary.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ----------------------------------------------------------
  // 更新品牌信息（#30）
  // ----------------------------------------------------------
  Future<void> updateBrand({
    String? name,
    String? description,
    String? logoUrl,
  }) async {
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (description != null) body['description'] = description;
    if (logoUrl != null) body['logo_url'] = logoUrl;
    if (body.isEmpty) return;

    await _ensureFreshSession();
    final response = await _supabase.functions.invoke(
      _brandFunctionName,
      method: HttpMethod.patch,
      body: body,
      headers: _merchantHeaders,
    );

    if (response.status != 200) {
      throw _handleError(response);
    }
  }

  // ----------------------------------------------------------
  // 获取品牌完整信息（品牌+门店+管理员列表）
  // ----------------------------------------------------------
  Future<Map<String, dynamic>> fetchBrandDetails() async {
    await _ensureFreshSession();
    final response = await _supabase.functions.invoke(
      _brandFunctionName,
      method: HttpMethod.get,
      headers: _merchantHeaders,
    );

    if (response.status != 200) {
      throw _handleError(response);
    }

    return response.data as Map<String, dynamic>;
  }

  // ----------------------------------------------------------
  // 添加门店到品牌（#33）
  // ----------------------------------------------------------
  Future<void> addStoreToBrand({String? merchantId, String? email}) async {
    await _ensureFreshSession();
    final body = <String, dynamic>{};
    if (merchantId != null) body['merchant_id'] = merchantId;
    if (email != null) body['email'] = email;

    final response = await _supabase.functions.invoke(
      '$_brandFunctionName/stores',
      method: HttpMethod.post,
      body: body,
      headers: _merchantHeaders,
    );

    if (response.status != 200 && response.status != 201) {
      throw _handleError(response);
    }
  }

  // ----------------------------------------------------------
  // 从品牌移除门店（#31）
  // ----------------------------------------------------------
  Future<void> removeStoreFromBrand(String merchantId) async {
    await _ensureFreshSession();
    final response = await _supabase.functions.invoke(
      '$_brandFunctionName/stores/$merchantId',
      method: HttpMethod.delete,
      headers: _merchantHeaders,
    );

    if (response.status != 200) {
      throw _handleError(response);
    }
  }

  // ----------------------------------------------------------
  // 邀请品牌管理员（#32）
  // ----------------------------------------------------------
  Future<void> inviteBrandAdmin(String email) async {
    await _ensureFreshSession();
    final response = await _supabase.functions.invoke(
      '$_brandFunctionName/admins',
      method: HttpMethod.post,
      body: {'email': email},
      headers: _merchantHeaders,
    );

    if (response.status != 200 && response.status != 201) {
      throw _handleError(response);
    }
  }

  // ----------------------------------------------------------
  // 移除品牌管理员（#32）
  // ----------------------------------------------------------
  Future<void> removeBrandAdmin(String adminId) async {
    await _ensureFreshSession();
    final response = await _supabase.functions.invoke(
      '$_brandFunctionName/admins/$adminId',
      method: HttpMethod.delete,
      headers: _merchantHeaders,
    );

    if (response.status != 200) {
      throw _handleError(response);
    }
  }

  // ==========================================================
  // 员工管理相关方法（调 merchant-staff-mgmt Edge Function）
  // ==========================================================

  // ----------------------------------------------------------
  // 获取员工列表 + 待处理邀请
  // ----------------------------------------------------------
  Future<({List<StaffMember> staff, List<StaffInvitation> invitations})>
      fetchStaff() async {
    await _ensureFreshSession();
    final response = await _supabase.functions.invoke(
      _staffFunctionName,
      method: HttpMethod.get,
      headers: _merchantHeaders,
    );

    if (response.status != 200) {
      throw _handleError(response);
    }

    final data = response.data as Map<String, dynamic>;
    final staffList = (data['staff'] as List<dynamic>? ?? [])
        .map((e) => StaffMember.fromJson(e as Map<String, dynamic>))
        .toList();
    final invitationList = (data['invitations'] as List<dynamic>? ?? [])
        .map((e) => StaffInvitation.fromJson(e as Map<String, dynamic>))
        .toList();

    return (staff: staffList, invitations: invitationList);
  }

  // ----------------------------------------------------------
  // 邀请员工
  // ----------------------------------------------------------
  Future<void> inviteStaff({
    required String email,
    required String role,
  }) async {
    await _ensureFreshSession();
    final response = await _supabase.functions.invoke(
      '$_staffFunctionName/invite',
      method: HttpMethod.post,
      body: {
        'email': email,
        'role': role,
      },
      headers: _merchantHeaders,
    );

    if (response.status != 200 && response.status != 201) {
      throw _handleError(response);
    }
  }

  // ----------------------------------------------------------
  // 修改员工角色/昵称/启用状态
  // ----------------------------------------------------------
  Future<void> updateStaff({
    required String staffId,
    String? role,
    String? nickname,
    bool? isActive,
  }) async {
    final body = <String, dynamic>{};
    if (role != null) body['role'] = role;
    if (nickname != null) body['nickname'] = nickname;
    if (isActive != null) body['is_active'] = isActive;

    if (body.isEmpty) return;

    await _ensureFreshSession();
    final response = await _supabase.functions.invoke(
      '$_staffFunctionName/$staffId',
      method: HttpMethod.patch,
      body: body,
      headers: _merchantHeaders,
    );

    if (response.status != 200) {
      throw _handleError(response);
    }
  }

  // ----------------------------------------------------------
  // 移除员工
  // ----------------------------------------------------------
  Future<void> removeStaff(String staffId) async {
    await _ensureFreshSession();
    final response = await _supabase.functions.invoke(
      '$_staffFunctionName/$staffId',
      method: HttpMethod.delete,
      headers: _merchantHeaders,
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

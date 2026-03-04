// 商家认证服务层
// 负责: Supabase Auth 注册、文件上传、申请提交、状态查询、重新提交

import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/merchant_application.dart';

// ============================================================
// MerchantAuthService — 所有商家认证相关的 Supabase 操作
// ============================================================
class MerchantAuthService {
  MerchantAuthService(this._supabase);

  final SupabaseClient _supabase;

  // ----------------------------------------------------------
  // 1. 用邮箱+密码注册新商家账号
  //    （使用 Supabase Auth，与用户端共用同一 Auth 实例）
  // ----------------------------------------------------------
  Future<AuthResponse> registerWithEmail({
    required String email,
    required String password,
  }) async {
    return await _supabase.auth.signUp(
      email: email,
      password: password,
      data: {'role': 'merchant'},
    );
  }

  // ----------------------------------------------------------
  // 2. 邮箱+密码登录（已有账号重新登录）
  // ----------------------------------------------------------
  Future<AuthResponse> signInWithEmail({
    required String email,
    required String password,
  }) async {
    return await _supabase.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  // ----------------------------------------------------------
  // 3. 上传单个证件文件到 Supabase Storage
  //    返回上传后的公开/签名 URL
  //    path 格式: {merchantId}/{documentType}/{filename}
  // ----------------------------------------------------------
  Future<String> uploadDocument({
    required String localFilePath,
    required DocumentType documentType,
    required String userId,
    String? customFileName,
  }) async {
    final file = File(localFilePath);
    if (!await file.exists()) {
      throw Exception('File not found: $localFilePath');
    }

    // 确定文件扩展名和 MIME 类型
    final extension = localFilePath.split('.').last.toLowerCase();
    final mimeType = _getMimeType(extension);
    final fileName = customFileName ?? '${documentType.apiValue}.$extension';

    // Storage 路径: {userId}/{documentType}/{fileName}
    final storagePath = '$userId/${documentType.apiValue}/$fileName';

    final fileBytes = await file.readAsBytes();

    // 上传到 merchant-documents bucket
    await _supabase.storage.from('merchant-documents').uploadBinary(
          storagePath,
          fileBytes,
          fileOptions: FileOptions(
            contentType: mimeType,
            upsert: true, // 覆盖已有文件（重新提交时）
          ),
        );

    // 返回 signed URL（私有 bucket 需要签名 URL，有效期 7 天）
    final signedUrl = await _supabase.storage
        .from('merchant-documents')
        .createSignedUrl(storagePath, 60 * 60 * 24 * 7);

    return signedUrl;
  }

  // ----------------------------------------------------------
  // 4. 提交注册申请（调用 merchant-register Edge Function）
  //    所有文件需先上传完毕，documents 中包含 Supabase Storage URL
  // ----------------------------------------------------------
  Future<Map<String, dynamic>> submitApplication(
    MerchantApplication application,
  ) async {
    final response = await _supabase.functions.invoke(
      'merchant-register',
      body: application.toJson(),
    );

    // Edge Function 返回非 2xx 时 invoke 会抛出异常
    if (response.status != 200) {
      final errorData = response.data as Map<String, dynamic>?;
      throw Exception(
        errorData?['error'] ?? 'Failed to submit application',
      );
    }

    return response.data as Map<String, dynamic>;
  }

  // ----------------------------------------------------------
  // 5. 查询当前用户的商家申请状态
  //    返回 MerchantApplication?（null 表示尚未提交）
  // ----------------------------------------------------------
  Future<MerchantApplication?> getApplicationStatus() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return null;

    final data = await _supabase
        .from('merchants')
        .select('*, merchant_documents(*)')
        .eq('user_id', user.id)
        .maybeSingle();

    if (data == null) return null;

    // 解析 documents 列表
    final rawDocs =
        (data['merchant_documents'] as List<dynamic>?) ?? [];
    final documents = rawDocs.map((d) {
      final doc = d as Map<String, dynamic>;
      return MerchantDocument(
        documentType: DocumentType.values.firstWhere(
          (t) => t.apiValue == doc['document_type'],
          orElse: () => DocumentType.businessLicense,
        ),
        fileUrl: doc['file_url'] as String? ?? '',
        fileName: doc['file_name'] as String?,
        fileSize: doc['file_size'] as int?,
        mimeType: doc['mime_type'] as String?,
      );
    }).toList();

    final application = MerchantApplication.fromJson(data);
    return application.copyWith(documents: documents);
  }

  // ----------------------------------------------------------
  // 6. 重新提交申请（审核被拒后使用）
  //    与 submitApplication 相同逻辑，Edge Function 内部处理 upsert
  // ----------------------------------------------------------
  Future<Map<String, dynamic>> resubmitApplication(
    MerchantApplication application,
  ) async {
    // 复用同一 Edge Function（内部判断是否已存在）
    return submitApplication(application);
  }

  // ----------------------------------------------------------
  // 7. 退出登录
  // ----------------------------------------------------------
  Future<void> signOut() async {
    await _supabase.auth.signOut();
  }

  // ----------------------------------------------------------
  // 内部辅助：根据文件扩展名返回 MIME 类型
  // ----------------------------------------------------------
  String _getMimeType(String extension) {
    switch (extension) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'pdf':
        return 'application/pdf';
      default:
        return 'application/octet-stream';
    }
  }

  // ----------------------------------------------------------
  // 8. 获取当前登录用户（快捷方法）
  // ----------------------------------------------------------
  User? get currentUser => _supabase.auth.currentUser;

  // ----------------------------------------------------------
  // 9. 监听 Auth 状态变更流
  // ----------------------------------------------------------
  Stream<AuthState> get authStateStream => _supabase.auth.onAuthStateChange;
}

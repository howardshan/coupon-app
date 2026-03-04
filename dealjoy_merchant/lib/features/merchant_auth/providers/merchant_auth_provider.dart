// 商家认证状态管理
// 使用 Riverpod AsyncNotifier 模式，管理整个注册流程的状态

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/merchant_application.dart';
import '../services/merchant_auth_service.dart';

// ============================================================
// 全局 SupabaseClient Provider
// ============================================================
final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

// ============================================================
// MerchantAuthService Provider
// ============================================================
final merchantAuthServiceProvider = Provider<MerchantAuthService>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return MerchantAuthService(client);
});

// ============================================================
// 当前用户 Provider（StreamProvider，实时响应 auth 变化）
// ============================================================
final currentUserProvider = StreamProvider<User?>((ref) {
  return Supabase.instance.client.auth.onAuthStateChange
      .map((event) => event.session?.user);
});

// ============================================================
// MerchantAuthNotifier — 商家注册流程的核心状态机
//
// state: AsyncData(MerchantApplication?) — null 表示尚未创建申请
// ============================================================
class MerchantAuthNotifier extends AsyncNotifier<MerchantApplication?> {
  // 注册时临时保存凭据，用于 signUp 未自动建立 session 时的自动补登录
  String? _regEmail;
  String? _regPassword;

  @override
  Future<MerchantApplication?> build() async {
    // 初始化时尝试加载已有申请（用于重启 App 后恢复状态）
    return _loadApplicationSafely();
  }

  // 获取 Service 实例
  MerchantAuthService get _service => ref.read(merchantAuthServiceProvider);

  // ----------------------------------------------------------
  // 私有方法：安全加载申请（捕获异常返回 null，不抛出）
  // ----------------------------------------------------------
  Future<MerchantApplication?> _loadApplicationSafely() async {
    try {
      final user = _service.currentUser;
      if (user == null) return null;
      return await _service.getApplicationStatus();
    } catch (_) {
      return null;
    }
  }

  // ----------------------------------------------------------
  // Step 1: 用邮箱+密码注册账号
  //         注册成功后创建空的 MerchantApplication 草稿
  // ----------------------------------------------------------
  Future<void> registerWithEmail({
    required String email,
    required String password,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final response = await _service.registerWithEmail(
        email: email,
        password: password,
      );
      if (response.user == null) {
        throw Exception('Registration failed. Please try again.');
      }
      // 缓存凭据，用于 signUp 未建立 session 时自动补登录
      _regEmail = email;
      _regPassword = password;
      // signUp 可能不会自动建立 session（Supabase 开启邮件确认时）
      // 立即尝试 signIn，确保后续上传文件时有 currentUser
      if (_service.currentUser == null) {
        try {
          await _service.signInWithEmail(email: email, password: password);
          _regPassword = null; // 登录成功后立即清除密码
        } catch (_) {
          // 若邮件未确认导致 signIn 失败，忽略，流程继续
        }
      }
      return MerchantApplication(email: email, contactEmail: email);
    });
  }

  // ----------------------------------------------------------
  // Step 2: 更新公司基本信息（本地状态，不写 DB）
  // ----------------------------------------------------------
  void updateBusinessInfo({
    required String companyName,
    required String contactName,
    required String contactEmail,
    required String phone,
  }) {
    final current = state.value;
    state = AsyncData(
      (current ?? const MerchantApplication()).copyWith(
        companyName: companyName,
        contactName: contactName,
        contactEmail: contactEmail,
        phone: phone,
      ),
    );
  }

  // ----------------------------------------------------------
  // Step 3: 更新商家类别（切换类别时清空已上传的证件）
  // ----------------------------------------------------------
  void updateCategory(MerchantCategory category) {
    final current = state.value;
    state = AsyncData(
      (current ?? const MerchantApplication()).copyWith(
        category: category,
        // 类别变更时清空证件（避免上传了无关证件）
        documents: const [],
      ),
    );
  }

  // ----------------------------------------------------------
  // Step 4a: 更新 EIN（本地状态）
  // ----------------------------------------------------------
  void updateEin(String ein) {
    final current = state.value;
    state = AsyncData(
      (current ?? const MerchantApplication()).copyWith(ein: ein),
    );
  }

  // ----------------------------------------------------------
  // Step 4b: 上传单个证件文件
  //          先上传到 Supabase Storage，再更新本地 documents 列表
  // ----------------------------------------------------------
  Future<void> uploadDocument({
    required DocumentType documentType,
    required String localFilePath,
    String? fileName,
  }) async {
    final current = state.value;
    if (current == null) return;

    var userId = _service.currentUser?.id;
    // session 丢失时用缓存凭据自动补登录（signUp 未建立 session 的情况）
    if (userId == null && _regEmail != null && _regPassword != null) {
      try {
        await _service.signInWithEmail(
          email: _regEmail!,
          password: _regPassword!,
        );
        userId = _service.currentUser?.id;
      } catch (_) {}
    }
    if (userId == null) throw Exception('User not logged in');
    final resolvedUserId = userId;

    // 标记为加载中（局部更新，保留已有数据）
    state = const AsyncLoading();

    state = await AsyncValue.guard(() async {
      final fileUrl = await _service.uploadDocument(
        localFilePath: localFilePath,
        documentType: documentType,
        userId: resolvedUserId,
        customFileName: fileName,
      );

      // 读取最新 state 避免并发上传时互相覆盖
      final latest = state.value ?? current;
      final updatedDocs = List<MerchantDocument>.from(latest.documents)
        ..removeWhere((d) => d.documentType == documentType);
      updatedDocs.add(
        MerchantDocument(
          documentType: documentType,
          fileUrl: fileUrl,
          localPath: localFilePath,
          fileName: fileName,
        ),
      );

      return latest.copyWith(documents: updatedDocs);
    });
  }

  // ----------------------------------------------------------
  // Step 5: 更新门店地址（本地状态，拆分为多字段）
  // ----------------------------------------------------------
  void updateAddress({
    required String address1,
    required String address2,
    required String city,
    required String state,
    required String zipcode,
  }) {
    final current = this.state.value;
    this.state = AsyncData(
      (current ?? const MerchantApplication()).copyWith(
        address1: address1,
        address2: address2,
        city: city,
        state: state,
        zipcode: zipcode,
      ),
    );
  }

  // ----------------------------------------------------------
  // 提交申请（调用 Edge Function）
  // ----------------------------------------------------------
  Future<void> submitApplication() async {
    final current = state.value;
    if (current == null) throw Exception('No application data');
    if (!current.isReadyToSubmit) {
      throw Exception('Please complete all required fields and documents');
    }

    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final result = await _service.submitApplication(current);
      final merchantId = result['merchant_id'] as String?;
      return current.copyWith(
        merchantId: merchantId,
        status: ApplicationStatus.pending,
        submittedAt: DateTime.now(),
      );
    });
  }

  // ----------------------------------------------------------
  // 重新提交（审核被拒后）
  // ----------------------------------------------------------
  Future<void> resubmitApplication() async {
    final current = state.value;
    if (current == null) throw Exception('No application data');

    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final result = await _service.resubmitApplication(current);
      final merchantId = result['merchant_id'] as String? ?? current.merchantId;
      return current.copyWith(
        merchantId: merchantId,
        status: ApplicationStatus.pending,
        submittedAt: DateTime.now(),
        rejectionReason: null,
      );
    });
  }

  // ----------------------------------------------------------
  // 刷新申请状态（从 DB 重新拉取）
  // ----------------------------------------------------------
  Future<void> refreshStatus() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _service.getApplicationStatus());
  }

  // ----------------------------------------------------------
  // 退出登录，清空状态
  // ----------------------------------------------------------
  Future<void> signOut() async {
    await _service.signOut();
    _regEmail = null;
    _regPassword = null;
    state = const AsyncData(null);
  }
}

// ============================================================
// 对外暴露的 Provider
// ============================================================
final merchantAuthProvider =
    AsyncNotifierProvider<MerchantAuthNotifier, MerchantApplication?>(
  MerchantAuthNotifier.new,
);

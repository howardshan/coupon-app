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
  // Step 1: 暂存邮箱密码（不调 signUp，延迟到最终提交时）
  // ----------------------------------------------------------
  void updateAccountInfo({
    required String email,
    required String password,
  }) {
    _regEmail = email;
    _regPassword = password;
    final current = state.value;
    state = AsyncData(
      (current ?? const MerchantApplication()).copyWith(
        email: email,
        contactEmail: email,
      ),
    );
  }

  // ----------------------------------------------------------
  // 最终提交: 注册账号（或已有账号则登录）→ 上传证件 → 提交申请
  // 若邮箱已存在：先登录，若已有 merchants 记录则仅返回状态不重复提交
  // ----------------------------------------------------------
  Future<void> registerAndSubmit({
    String registrationType = 'single',
    String? brandName,
    String? brandDescription,
  }) async {
    final current = state.value;
    if (current == null) throw Exception('No application data');

    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      String? userId;
      try {
        // 1. 尝试注册 Supabase Auth 账号
        final response = await _service.registerWithEmail(
          email: _regEmail!,
          password: _regPassword!,
        );
        if (response.user == null) {
          throw Exception('Registration failed. Please try again.');
        }
        if (_service.currentUser == null) {
          await _service.signInWithEmail(
            email: _regEmail!,
            password: _regPassword!,
          );
        }
        _regPassword = null;
        userId = _service.currentUser!.id;
      } on AuthException catch (e) {
        // 邮箱已注册：改为登录，再判断是否已有申请
        final msg = (e.message ?? e.toString()).toLowerCase();
        final isAlreadyRegistered = msg.contains('already') && msg.contains('registered') ||
            msg.contains('user_already_exists');
        if (!isAlreadyRegistered) rethrow;
        await _service.signInWithEmail(
          email: _regEmail!,
          password: _regPassword!,
        );
        _regPassword = null;
        userId = _service.currentUser!.id;
        final existing = await _service.getApplicationStatus();
        if (existing != null) {
          return existing; // 已有申请，不重复提交，由 UI 跳转 /auth/review
        }
      }
      _regPassword = null;
      userId ??= _service.currentUser!.id;

      // 2. 上传所有本地暂存的证件文件
      final uploadedDocs = <MerchantDocument>[];
      for (final doc in current.documents) {
        if (doc.localPath != null && doc.localPath!.isNotEmpty) {
          final fileUrl = await _service.uploadDocument(
            localFilePath: doc.localPath!,
            documentType: doc.documentType,
            userId: userId!,
            customFileName: doc.fileName,
          );
          uploadedDocs.add(doc.copyWith(fileUrl: fileUrl));
        } else {
          uploadedDocs.add(doc);
        }
      }

      final updatedApp = current.copyWith(documents: uploadedDocs);

      // 3. 提交商家申请（含注册类型和品牌信息）
      final result = await _service.submitApplication(
        updatedApp,
        registrationType: registrationType,
        brandName: brandName,
        brandDescription: brandDescription,
      );
      final merchantId = result['merchant_id'] as String?;
      return updatedApp.copyWith(
        merchantId: merchantId,
        status: ApplicationStatus.pending,
        submittedAt: DateTime.now(),
      );
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
  // Step 4b: 暂存证件文件路径（本地记录，延迟到提交时上传）
  // ----------------------------------------------------------
  void addDocumentLocal({
    required DocumentType documentType,
    required String localFilePath,
    String? fileName,
  }) {
    final current = state.value;
    if (current == null) return;

    final updatedDocs = List<MerchantDocument>.from(current.documents)
      ..removeWhere((d) => d.documentType == documentType);
    updatedDocs.add(
      MerchantDocument(
        documentType: documentType,
        fileUrl: 'local://$localFilePath', // 标记为本地文件，提交时上传
        localPath: localFilePath,
        fileName: fileName,
      ),
    );

    state = AsyncData(current.copyWith(documents: updatedDocs));
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
    double? lat,
    double? lng,
  }) {
    final current = this.state.value;
    this.state = AsyncData(
      (current ?? const MerchantApplication()).copyWith(
        address1: address1,
        address2: address2,
        city: city,
        state: state,
        zipcode: zipcode,
        lat: lat,
        lng: lng,
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
  // 重置状态（进入注册页时清除上次错误）
  // ----------------------------------------------------------
  void resetState() {
    state = const AsyncData(null);
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

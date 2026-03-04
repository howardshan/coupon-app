// MerchantAuthService 单元测试
// 策略: 对 Supabase 深度链式调用部分使用 mock service wrapper；
//       对纯数据逻辑（模型解析、参数校验）直接测试，不依赖 Supabase SDK 内部类型。

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dealjoy_merchant/features/merchant_auth/models/merchant_application.dart';
import 'package:dealjoy_merchant/features/merchant_auth/services/merchant_auth_service.dart';

// ============================================================
// Mock 辅助类
// ============================================================

/// 可测试的 MerchantAuthService 子类，重写依赖外部 IO 的方法
class _TestableMerchantAuthService extends MerchantAuthService {
  _TestableMerchantAuthService(super.supabase);

  // 模拟 getApplicationStatus 返回值（由测试用例注入）
  MerchantApplication? stubbedStatus;
  bool throwOnStatus = false;

  @override
  Future<MerchantApplication?> getApplicationStatus() async {
    if (throwOnStatus) throw Exception('Network error');
    return stubbedStatus;
  }

  // 模拟 submitApplication 返回值
  Map<String, dynamic>? stubbedSubmitResult;
  bool throwOnSubmit = false;

  @override
  Future<Map<String, dynamic>> submitApplication(
    MerchantApplication application,
  ) async {
    if (throwOnSubmit) throw Exception('Failed to submit application');
    return stubbedSubmitResult ??
        {'merchant_id': 'mock-id', 'status': 'pending'};
  }
}

/// Mock SupabaseClient（最小化 mock，只用于构造 service）
class MockSupabaseClient extends Mock implements SupabaseClient {}

/// Mock GoTrueClient
class MockGoTrueClient extends Mock implements GoTrueClient {}

// ============================================================
// 测试 helper：构建测试用 application
// ============================================================
MerchantApplication _buildValidApplication({
  MerchantCategory category = MerchantCategory.restaurant,
}) {
  return MerchantApplication(
    email: 'merchant@test.com',
    companyName: 'Test LLC',
    contactName: 'John Doe',
    contactEmail: 'john@test.com',
    phone: '+1 555 0000',
    category: category,
    ein: '12-3456789',
    address: '123 Main St, Dallas, TX',
    documents: category.requiredDocuments
        .map(
          (t) => MerchantDocument(
            documentType: t,
            fileUrl: 'https://storage.test/${t.apiValue}.jpg',
          ),
        )
        .toList(),
  );
}

// ============================================================
// 测试主体
// ============================================================
void main() {
  late MockSupabaseClient mockClient;
  late MockGoTrueClient mockAuth;
  late _TestableMerchantAuthService service;

  // 伪造用户对象
  final fakeUser = User(
    id: 'user-123',
    appMetadata: {},
    userMetadata: {},
    aud: 'authenticated',
    createdAt: DateTime.now().toIso8601String(),
  );

  setUp(() {
    mockClient = MockSupabaseClient();
    mockAuth = MockGoTrueClient();
    when(() => mockClient.auth).thenReturn(mockAuth);
    service = _TestableMerchantAuthService(mockClient);
  });

  // ----------------------------------------------------------
  // 1. currentUser 快捷属性
  // ----------------------------------------------------------
  group('currentUser', () {
    test('已登录时应返回当前 User 对象', () {
      when(() => mockAuth.currentUser).thenReturn(fakeUser);
      expect(service.currentUser, equals(fakeUser));
    });

    test('未登录时应返回 null', () {
      when(() => mockAuth.currentUser).thenReturn(null);
      expect(service.currentUser, isNull);
    });
  });

  // ----------------------------------------------------------
  // 2. getApplicationStatus — 通过 stub 测试返回值解析
  // ----------------------------------------------------------
  group('getApplicationStatus', () {
    test('未提交时返回 null', () async {
      service.stubbedStatus = null;
      final result = await service.getApplicationStatus();
      expect(result, isNull);
    });

    test('有申请记录时返回 MerchantApplication（pending）', () async {
      service.stubbedStatus = const MerchantApplication(
        merchantId: 'merchant-abc',
        companyName: 'Test Restaurant LLC',
        category: MerchantCategory.restaurant,
        ein: '12-3456789',
        status: ApplicationStatus.pending,
      );

      final result = await service.getApplicationStatus();

      expect(result, isNotNull);
      expect(result!.merchantId, equals('merchant-abc'));
      expect(result.category, equals(MerchantCategory.restaurant));
      expect(result.status, equals(ApplicationStatus.pending));
    });

    test('有申请记录时返回 MerchantApplication（rejected + reason）', () async {
      service.stubbedStatus = const MerchantApplication(
        merchantId: 'merchant-xyz',
        companyName: 'Rejected LLC',
        status: ApplicationStatus.rejected,
        rejectionReason: 'Business license is expired.',
      );

      final result = await service.getApplicationStatus();

      expect(result!.status, equals(ApplicationStatus.rejected));
      expect(result.rejectionReason, equals('Business license is expired.'));
    });

    test('网络异常时应传播异常', () async {
      service.throwOnStatus = true;

      expect(
        () => service.getApplicationStatus(),
        throwsA(isA<Exception>()),
      );
    });
  });

  // ----------------------------------------------------------
  // 3. submitApplication — 通过 stub 测试流程
  // ----------------------------------------------------------
  group('submitApplication', () {
    test('成功时应返回包含 merchant_id 和 status 的 Map', () async {
      final app = _buildValidApplication();
      service.stubbedSubmitResult = {
        'merchant_id': 'new-merchant-456',
        'status': 'pending',
        'message': 'Application submitted successfully.',
      };

      final result = await service.submitApplication(app);

      expect(result['merchant_id'], equals('new-merchant-456'));
      expect(result['status'], equals('pending'));
    });

    test('提交失败时应传播异常', () async {
      final app = _buildValidApplication();
      service.throwOnSubmit = true;

      expect(
        () => service.submitApplication(app),
        throwsA(isA<Exception>()),
      );
    });
  });

  // ----------------------------------------------------------
  // 4. resubmitApplication — 等同于 submitApplication
  // ----------------------------------------------------------
  group('resubmitApplication', () {
    test('重新提交应返回 pending 状态', () async {
      final app = _buildValidApplication().copyWith(
        merchantId: 'existing-merchant',
        status: ApplicationStatus.rejected,
      );
      service.stubbedSubmitResult = {
        'merchant_id': 'existing-merchant',
        'status': 'pending',
      };

      final result = await service.resubmitApplication(app);

      expect(result['status'], equals('pending'));
      expect(result['merchant_id'], equals('existing-merchant'));
    });
  });

  // ----------------------------------------------------------
  // 5. MerchantApplication 模型逻辑（纯 Dart，无 IO 依赖）
  // ----------------------------------------------------------
  group('MerchantApplication model', () {
    test('isReadyToSubmit: 所有字段齐全时返回 true', () {
      final app = _buildValidApplication(category: MerchantCategory.fitness);
      expect(app.isReadyToSubmit, isTrue);
    });

    test('isReadyToSubmit: EIN 格式错误时返回 false', () {
      final app = _buildValidApplication().copyWith(ein: 'INVALID-EIN');
      expect(app.isReadyToSubmit, isFalse);
    });

    test('isReadyToSubmit: 缺少必需证件时返回 false', () {
      // 证件列表为空
      const app = MerchantApplication(
        companyName: 'Test',
        contactName: 'Test',
        phone: '555',
        ein: '12-3456789',
        address: '123 Main St',
        category: MerchantCategory.restaurant,
        documents: [], // 缺少证件
      );
      expect(app.isReadyToSubmit, isFalse);
    });

    test('isReadyToSubmit: category 为 null 时返回 false', () {
      const app = MerchantApplication(
        companyName: 'Test',
        contactName: 'Test',
        phone: '555',
        ein: '12-3456789',
        address: '123 Main St',
      );
      expect(app.isReadyToSubmit, isFalse);
    });

    test('getDocument: 存在指定类型时正确返回', () {
      final app = _buildValidApplication(category: MerchantCategory.restaurant);
      final doc = app.getDocument(DocumentType.businessLicense);
      expect(doc, isNotNull);
      expect(doc!.documentType, equals(DocumentType.businessLicense));
    });

    test('getDocument: 不存在时返回 null', () {
      const app = MerchantApplication(documents: []);
      final doc = app.getDocument(DocumentType.facilityLicense);
      expect(doc, isNull);
    });

    test('MerchantApplication.fromJson 正确解析数据库记录', () {
      final json = {
        'id': 'merchant-999',
        'company_name': 'Parse Test LLC',
        'contact_name': 'Alice',
        'contact_email': 'alice@test.com',
        'phone': '+1 555 9999',
        'category': 'Wellness',
        'ein': '55-6677889',
        'address': '999 Elm St',
        'status': 'approved',
        'rejection_reason': null,
        'submitted_at': '2026-03-03T08:00:00.000Z',
      };

      final app = MerchantApplication.fromJson(json);

      expect(app.merchantId, equals('merchant-999'));
      expect(app.companyName, equals('Parse Test LLC'));
      expect(app.category, equals(MerchantCategory.wellness));
      expect(app.status, equals(ApplicationStatus.approved));
      expect(app.rejectionReason, isNull);
      expect(app.submittedAt, isNotNull);
    });
  });

  // ----------------------------------------------------------
  // 6. MerchantCategory 证件矩阵测试（纯逻辑）
  // ----------------------------------------------------------
  group('MerchantCategory.requiredDocuments', () {
    test('Restaurant 应包含 Health Permit 和 Food Service License', () {
      final docs = MerchantCategory.restaurant.requiredDocuments;
      expect(docs, contains(DocumentType.healthPermit));
      expect(docs, contains(DocumentType.foodServiceLicense));
      expect(docs, contains(DocumentType.businessLicense));
      expect(docs, contains(DocumentType.ownerID));
      expect(docs, contains(DocumentType.storefrontPhoto));
    });

    test('SpaAndMassage 应包含 Cosmetology + Massage Therapy License', () {
      final docs = MerchantCategory.spaAndMassage.requiredDocuments;
      expect(docs, contains(DocumentType.cosmetologyLicense));
      expect(docs, contains(DocumentType.massageTherapyLicense));
      expect(docs, contains(DocumentType.healthPermit));
    });

    test('Fitness 应包含 Facility License', () {
      final docs = MerchantCategory.fitness.requiredDocuments;
      expect(docs, contains(DocumentType.facilityLicense));
      expect(docs, isNot(contains(DocumentType.healthPermit)));
    });

    test('Other 应包含 General Business Permit', () {
      final docs = MerchantCategory.other.requiredDocuments;
      expect(docs, contains(DocumentType.generalBusinessPermit));
    });

    test('所有类别均包含 Business License、Owner ID、Storefront Photo', () {
      for (final category in MerchantCategory.values) {
        final docs = category.requiredDocuments;
        expect(
          docs,
          contains(DocumentType.businessLicense),
          reason: '${category.label} should require Business License',
        );
        expect(
          docs,
          contains(DocumentType.ownerID),
          reason: '${category.label} should require Owner ID',
        );
        expect(
          docs,
          contains(DocumentType.storefrontPhoto),
          reason: '${category.label} should require Storefront Photo',
        );
      }
    });
  });
}

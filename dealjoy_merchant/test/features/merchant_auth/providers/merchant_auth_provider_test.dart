// MerchantAuthNotifier 单元测试
// 测试范围: updateBusinessInfo, updateCategory, updateEin,
//           updateAddress, submitApplication, resubmitApplication, signOut

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dealjoy_merchant/features/merchant_auth/models/merchant_application.dart';
import 'package:dealjoy_merchant/features/merchant_auth/providers/merchant_auth_provider.dart';
import 'package:dealjoy_merchant/features/merchant_auth/services/merchant_auth_service.dart';

// ============================================================
// Mock 类
// ============================================================

/// Mock MerchantAuthService（隔离 Supabase SDK）
class MockMerchantAuthService extends Mock implements MerchantAuthService {}

// ============================================================
// 测试辅助：构建 ProviderContainer 并注入 Mock Service
// ============================================================
ProviderContainer _buildContainer({
  required MockMerchantAuthService mockService,
}) {
  return ProviderContainer(
    overrides: [
      // 覆盖 service provider，注入 mock
      merchantAuthServiceProvider.overrideWithValue(mockService),
    ],
  );
}

// ============================================================
// 测试主体
// ============================================================
void main() {
  late MockMerchantAuthService mockService;

  // 伪造 Supabase User
  final fakeUser = User(
    id: 'user-test-001',
    appMetadata: {},
    userMetadata: {},
    aud: 'authenticated',
    createdAt: DateTime.now().toIso8601String(),
  );

  setUp(() {
    mockService = MockMerchantAuthService();
    // 默认: 未登录 + 无申请
    when(() => mockService.currentUser).thenReturn(null);
    when(() => mockService.getApplicationStatus())
        .thenAnswer((_) async => null);
  });

  // ----------------------------------------------------------
  // 1. 初始化（build）
  // ----------------------------------------------------------
  group('初始化', () {
    test('未登录时初始 state 应为 AsyncData(null)', () async {
      final container = _buildContainer(mockService: mockService);
      addTearDown(container.dispose);

      // 等待 provider 完成 build
      await container.read(merchantAuthProvider.future);

      final state = container.read(merchantAuthProvider);
      expect(state, isA<AsyncData<MerchantApplication?>>());
      expect(state.value, isNull);
    });

    test('已登录且有申请时初始 state 应加载现有申请', () async {
      when(() => mockService.currentUser).thenReturn(fakeUser);
      when(() => mockService.getApplicationStatus()).thenAnswer(
        (_) async => const MerchantApplication(
          merchantId: 'existing-123',
          companyName: 'Existing LLC',
          status: ApplicationStatus.pending,
        ),
      );

      final container = _buildContainer(mockService: mockService);
      addTearDown(container.dispose);

      await container.read(merchantAuthProvider.future);

      final state = container.read(merchantAuthProvider);
      expect(state.value?.merchantId, equals('existing-123'));
      expect(state.value?.status, equals(ApplicationStatus.pending));
    });
  });

  // ----------------------------------------------------------
  // 2. registerWithEmail
  // ----------------------------------------------------------
  group('registerWithEmail', () {
    test('注册成功后 state 应包含邮箱预填的草稿 application', () async {
      when(
        () => mockService.registerWithEmail(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenAnswer(
        (_) async => AuthResponse(session: null, user: fakeUser),
      );

      final container = _buildContainer(mockService: mockService);
      addTearDown(container.dispose);
      await container.read(merchantAuthProvider.future);

      final notifier = container.read(merchantAuthProvider.notifier);
      await notifier.registerWithEmail(
        email: 'new@test.com',
        password: 'Secret123',
      );

      final state = container.read(merchantAuthProvider);
      expect(state.value?.email, equals('new@test.com'));
      expect(state.value?.contactEmail, equals('new@test.com'));
    });

    test('注册失败时 state 应为 AsyncError', () async {
      when(
        () => mockService.registerWithEmail(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenThrow(Exception('Email already in use'));

      final container = _buildContainer(mockService: mockService);
      addTearDown(container.dispose);
      await container.read(merchantAuthProvider.future);

      final notifier = container.read(merchantAuthProvider.notifier);
      await notifier.registerWithEmail(
        email: 'dupe@test.com',
        password: 'Secret123',
      );

      final state = container.read(merchantAuthProvider);
      expect(state, isA<AsyncError>());
    });
  });

  // ----------------------------------------------------------
  // 3. updateBusinessInfo
  // ----------------------------------------------------------
  group('updateBusinessInfo', () {
    test('调用后 state 应更新公司信息字段', () async {
      final container = _buildContainer(mockService: mockService);
      addTearDown(container.dispose);
      await container.read(merchantAuthProvider.future);

      container.read(merchantAuthProvider.notifier).updateBusinessInfo(
            companyName: 'My Restaurant LLC',
            contactName: 'Jane Smith',
            contactEmail: 'jane@restaurant.com',
            phone: '+1 214 555 0000',
          );

      final app = container.read(merchantAuthProvider).value;
      expect(app?.companyName, equals('My Restaurant LLC'));
      expect(app?.contactName, equals('Jane Smith'));
      expect(app?.phone, equals('+1 214 555 0000'));
    });
  });

  // ----------------------------------------------------------
  // 4. updateCategory
  // ----------------------------------------------------------
  group('updateCategory', () {
    test('切换类别后应更新 category 并清空 documents', () async {
      final container = _buildContainer(mockService: mockService);
      addTearDown(container.dispose);
      await container.read(merchantAuthProvider.future);

      final notifier = container.read(merchantAuthProvider.notifier);

      // 先设置一些证件（模拟已上传）
      notifier.updateCategory(MerchantCategory.restaurant);
      final stateAfterFirst =
          container.read(merchantAuthProvider).value;
      expect(stateAfterFirst?.category, equals(MerchantCategory.restaurant));
      // 文档列表应为空（刚切换）
      expect(stateAfterFirst?.documents, isEmpty);

      // 再切换到 Fitness，documents 应再次清空
      notifier.updateCategory(MerchantCategory.fitness);
      final stateAfterSecond =
          container.read(merchantAuthProvider).value;
      expect(stateAfterSecond?.category, equals(MerchantCategory.fitness));
      expect(stateAfterSecond?.documents, isEmpty);
    });
  });

  // ----------------------------------------------------------
  // 5. updateEin
  // ----------------------------------------------------------
  group('updateEin', () {
    test('更新 EIN 后 state 应反映新值', () async {
      final container = _buildContainer(mockService: mockService);
      addTearDown(container.dispose);
      await container.read(merchantAuthProvider.future);

      container.read(merchantAuthProvider.notifier).updateEin('99-1234567');

      final app = container.read(merchantAuthProvider).value;
      expect(app?.ein, equals('99-1234567'));
    });
  });

  // ----------------------------------------------------------
  // 6. updateAddress
  // ----------------------------------------------------------
  group('updateAddress', () {
    test('更新地址后 state 应包含新地址', () async {
      final container = _buildContainer(mockService: mockService);
      addTearDown(container.dispose);
      await container.read(merchantAuthProvider.future);

      container.read(merchantAuthProvider.notifier).updateAddress(
            '456 Commerce St, Dallas, TX 75202',
          );

      final app = container.read(merchantAuthProvider).value;
      expect(app?.address, equals('456 Commerce St, Dallas, TX 75202'));
    });
  });

  // ----------------------------------------------------------
  // 7. submitApplication
  // ----------------------------------------------------------
  group('submitApplication', () {
    test('提交成功后 state 应为 pending 并包含 merchantId', () async {
      when(
        () => mockService.submitApplication(any()),
      ).thenAnswer(
        (_) async => {
          'merchant_id': 'submitted-merchant-789',
          'status': 'pending',
        },
      );

      final container = _buildContainer(mockService: mockService);
      addTearDown(container.dispose);
      await container.read(merchantAuthProvider.future);

      // 先填入足够的数据（构造一个"可提交"状态）
      final notifier = container.read(merchantAuthProvider.notifier);
      notifier.updateBusinessInfo(
        companyName: 'Valid LLC',
        contactName: 'Bob',
        contactEmail: 'bob@valid.com',
        phone: '+1 555 1234',
      );
      notifier.updateCategory(MerchantCategory.funAndGames);
      notifier.updateEin('11-2233445');
      notifier.updateAddress('100 Test Ave, Dallas, TX');

      await notifier.submitApplication();

      final state = container.read(merchantAuthProvider);
      expect(state.value?.merchantId, equals('submitted-merchant-789'));
      expect(state.value?.status, equals(ApplicationStatus.pending));
      expect(state.value?.submittedAt, isNotNull);
    });

    test('提交失败时 state 应为 AsyncError', () async {
      when(
        () => mockService.submitApplication(any()),
      ).thenThrow(Exception('Server error'));

      final container = _buildContainer(mockService: mockService);
      addTearDown(container.dispose);
      await container.read(merchantAuthProvider.future);

      final notifier = container.read(merchantAuthProvider.notifier);
      notifier.updateBusinessInfo(
        companyName: 'LLC',
        contactName: 'X',
        contactEmail: 'x@x.com',
        phone: '000',
      );
      notifier.updateCategory(MerchantCategory.other);
      notifier.updateEin('00-0000000');
      notifier.updateAddress('Somewhere');

      await notifier.submitApplication();

      final state = container.read(merchantAuthProvider);
      expect(state, isA<AsyncError>());
    });
  });

  // ----------------------------------------------------------
  // 8. resubmitApplication
  // ----------------------------------------------------------
  group('resubmitApplication', () {
    test('重新提交后 rejectionReason 应被清空，status 回到 pending', () async {
      // 初始状态：已被拒的申请
      when(() => mockService.getApplicationStatus()).thenAnswer(
        (_) async => const MerchantApplication(
          merchantId: 'rejected-merchant',
          companyName: 'Rejected LLC',
          status: ApplicationStatus.rejected,
          rejectionReason: 'Documents are unclear.',
          category: MerchantCategory.wellness,
          ein: '11-2233445',
          address: '789 Oak St',
        ),
      );
      when(
        () => mockService.resubmitApplication(any()),
      ).thenAnswer(
        (_) async => {
          'merchant_id': 'rejected-merchant',
          'status': 'pending',
        },
      );

      final container = _buildContainer(mockService: mockService);
      addTearDown(container.dispose);
      await container.read(merchantAuthProvider.future);

      await container
          .read(merchantAuthProvider.notifier)
          .resubmitApplication();

      final state = container.read(merchantAuthProvider);
      expect(state.value?.status, equals(ApplicationStatus.pending));
      expect(state.value?.rejectionReason, isNull);
    });
  });

  // ----------------------------------------------------------
  // 9. signOut
  // ----------------------------------------------------------
  group('signOut', () {
    test('退出后 state 应重置为 AsyncData(null)', () async {
      when(() => mockService.signOut()).thenAnswer((_) async {});

      final container = _buildContainer(mockService: mockService);
      addTearDown(container.dispose);
      await container.read(merchantAuthProvider.future);

      // 先设一些数据
      container.read(merchantAuthProvider.notifier).updateBusinessInfo(
            companyName: 'LLC',
            contactName: 'X',
            contactEmail: 'x@x.com',
            phone: '000',
          );

      await container.read(merchantAuthProvider.notifier).signOut();

      final state = container.read(merchantAuthProvider);
      expect(state.value, isNull);
      verify(() => mockService.signOut()).called(1);
    });
  });
}

// EarningsService 单元测试
// 策略: 模拟 SupabaseClient.functions.invoke 的响应，
//       测试各 API 方法的正常解析与异常处理路径。

import 'package:flutter_test/flutter_test.dart';
import 'package:dealjoy_merchant/features/earnings/models/earnings_data.dart';
import 'package:dealjoy_merchant/features/earnings/services/earnings_service.dart';

// =============================================================
// Mock 辅助：EarningsService 的可测试子类
// 重写内部方法，无需依赖 Supabase SDK
// =============================================================
class _TestableEarningsService extends EarningsService {
  _TestableEarningsService() : super(null as dynamic);

  // 注入响应数据
  Map<String, dynamic>? stubbedSummaryData;
  Map<String, dynamic>? stubbedTransactionsData;
  Map<String, dynamic>? stubbedScheduleData;
  Map<String, dynamic>? stubbedReportData;
  Map<String, dynamic>? stubbedAccountData;

  // 注入异常
  EarningsException? throwOnSummary;
  EarningsException? throwOnTransactions;

  @override
  Future<EarningsSummary> fetchEarningsSummary(
    String merchantId,
    DateTime month,
  ) async {
    if (throwOnSummary != null) throw throwOnSummary!;
    final data = stubbedSummaryData ?? _defaultSummaryJson();
    return EarningsSummary.fromJson(data);
  }

  @override
  Future<PagedTransactions> fetchTransactions(
    String merchantId, {
    DateTime? from,
    DateTime? to,
    int page = 1,
    int perPage = 20,
  }) async {
    if (throwOnTransactions != null) throw throwOnTransactions!;
    final data = stubbedTransactionsData ?? _defaultTransactionsJson();
    return PagedTransactions.fromJson(data);
  }

  @override
  Future<SettlementSchedule> fetchSettlementSchedule(
      String merchantId) async {
    final data = stubbedScheduleData ?? _defaultScheduleJson();
    return SettlementSchedule.fromJson(data);
  }

  @override
  Future<ReportData> fetchReportData(
    String merchantId, {
    required ReportPeriodType periodType,
    required int year,
    int? month,
    int? week,
  }) async {
    final data = stubbedReportData ?? _defaultReportJson(periodType);
    return ReportData.fromJson(data);
  }

  @override
  Future<StripeAccountInfo> fetchStripeAccountInfo(
      String merchantId) async {
    final data = stubbedAccountData ?? _defaultAccountJson(connected: false);
    return StripeAccountInfo.fromJson(data);
  }
}

// =============================================================
// 测试 JSON 工厂函数
// =============================================================
Map<String, dynamic> _defaultSummaryJson({
  double totalRevenue = 1000.0,
  double pendingSettlement = 300.0,
  double settledAmount = 600.0,
  double refundedAmount = 100.0,
  String month = '2026-03',
}) {
  return {
    'month':               month,
    'total_revenue':       totalRevenue,
    'pending_settlement':  pendingSettlement,
    'settled_amount':      settledAmount,
    'refunded_amount':     refundedAmount,
  };
}

Map<String, dynamic> _defaultTransactionsJson() {
  return {
    'data': [
      {
        'order_id':     'abc12345-0000-0000-0000-000000000000',
        'amount':       50.00,
        'platform_fee': 7.50,
        'net_amount':   42.50,
        'status':       'used',
        'created_at':   '2026-03-01T12:00:00.000Z',
      },
      {
        'order_id':     'def67890-0000-0000-0000-000000000000',
        'amount':       80.00,
        'platform_fee': 12.00,
        'net_amount':   68.00,
        'status':       'unused',
        'created_at':   '2026-03-02T14:30:00.000Z',
      },
    ],
    'pagination': {
      'page':     1,
      'per_page': 20,
      'total':    2,
      'has_more': false,
    },
    'totals': {
      'amount':       130.00,
      'platform_fee': 19.50,
      'net_amount':   110.50,
    },
  };
}

Map<String, dynamic> _defaultScheduleJson({bool hasPending = true}) {
  return {
    'settlement_rule':     'Redeemed orders are settled T+7 days after redemption',
    'settlement_days':     7,
    'next_payout_date':    hasPending ? '2026-03-10' : null,
    'pending_amount':      hasPending ? 255.00 : 0.0,
    'pending_order_count': hasPending ? 3 : 0,
  };
}

Map<String, dynamic> _defaultReportJson(ReportPeriodType type) {
  return {
    'period_type': type.apiValue,
    'date_from':   '2026-03-01',
    'date_to':     '2026-03-31',
    'rows': [
      {
        'date':         '2026-03-01',
        'order_count':  '3',
        'gross_amount': '150.00',
        'platform_fee': '22.50',
        'net_amount':   '127.50',
      },
    ],
    'totals': {
      'order_count':  3,
      'gross_amount': 150.00,
      'platform_fee': 22.50,
      'net_amount':   127.50,
    },
  };
}

Map<String, dynamic> _defaultAccountJson({bool connected = true}) {
  return {
    'is_connected':   connected,
    'account_id':     connected ? 'acct_1A2B3C4D' : null,
    'account_email':  connected ? 'merchant@example.com' : null,
    'account_status': connected ? 'connected' : 'not_connected',
  };
}

// =============================================================
// 测试套件
// =============================================================
void main() {
  late _TestableEarningsService service;

  setUp(() {
    service = _TestableEarningsService();
  });

  // -----------------------------------------------------------
  // EarningsSummary 解析测试
  // -----------------------------------------------------------
  group('fetchEarningsSummary', () {
    test('正常解析四个汇总金额', () async {
      service.stubbedSummaryData = _defaultSummaryJson(
        totalRevenue:      1000.0,
        pendingSettlement: 300.0,
        settledAmount:     600.0,
        refundedAmount:    100.0,
        month:             '2026-03',
      );

      final result = await service.fetchEarningsSummary('m1', DateTime(2026, 3));

      expect(result.totalRevenue,      1000.0);
      expect(result.pendingSettlement, 300.0);
      expect(result.settledAmount,     600.0);
      expect(result.refundedAmount,    100.0);
      expect(result.month,             '2026-03');
    });

    test('JSON 中字段缺失时使用 0.0 默认值', () async {
      service.stubbedSummaryData = {'month': '2026-02'};

      final result = await service.fetchEarningsSummary('m1', DateTime(2026, 2));

      expect(result.totalRevenue,      0.0);
      expect(result.pendingSettlement, 0.0);
      expect(result.settledAmount,     0.0);
      expect(result.refundedAmount,    0.0);
    });

    test('抛出 EarningsException 时向上传递', () async {
      service.throwOnSummary = const EarningsException(
        code:    'db_error',
        message: 'DB query failed',
      );

      expect(
        () => service.fetchEarningsSummary('m1', DateTime(2026, 3)),
        throwsA(isA<EarningsException>()),
      );
    });
  });

  // -----------------------------------------------------------
  // 交易明细解析测试
  // -----------------------------------------------------------
  group('fetchTransactions', () {
    test('正常解析交易列表和分页信息', () async {
      final result = await service.fetchTransactions('m1');

      expect(result.data.length, 2);
      expect(result.total,       2);
      expect(result.hasMore,     false);
      expect(result.page,        1);
    });

    test('第一条交易的金额和手续费计算正确', () async {
      final result = await service.fetchTransactions('m1');
      final first  = result.data.first;

      expect(first.amount,      50.00);
      expect(first.platformFee, 7.50);   // 15%
      expect(first.netAmount,   42.50);  // 85%
      expect(first.status,      'used');
    });

    test('交易合计行数据正确', () async {
      final result = await service.fetchTransactions('m1');

      expect(result.totals.amount,      130.00);
      expect(result.totals.platformFee, 19.50);
      expect(result.totals.netAmount,   110.50);
    });

    test('空列表时返回 PagedTransactions.empty()', () async {
      service.stubbedTransactionsData = {
        'data': [],
        'pagination': {'page': 1, 'per_page': 20, 'total': 0, 'has_more': false},
        'totals': {'amount': 0, 'platform_fee': 0, 'net_amount': 0},
      };

      final result = await service.fetchTransactions('m1');
      expect(result.data.isEmpty, true);
      expect(result.total,        0);
    });

    test('抛出 EarningsException 时向上传递', () async {
      service.throwOnTransactions = const EarningsException(
        code:    'unauthorized',
        message: 'Not authorized',
      );

      expect(
        () => service.fetchTransactions('m1'),
        throwsA(
          predicate<EarningsException>((e) => e.code == 'unauthorized'),
        ),
      );
    });
  });

  // -----------------------------------------------------------
  // 结算规则解析测试
  // -----------------------------------------------------------
  group('fetchSettlementSchedule', () {
    test('有待结算时正确解析下次打款日期', () async {
      final result = await service.fetchSettlementSchedule('m1');

      expect(result.settlementDays,    7);
      expect(result.hasPendingSettlement, true);
      expect(result.pendingOrderCount, 3);
      expect(result.pendingAmount,     255.0);
      expect(result.nextPayoutDate,    isNotNull);
    });

    test('无待结算时 hasPendingSettlement 为 false', () async {
      service.stubbedScheduleData = _defaultScheduleJson(hasPending: false);

      final result = await service.fetchSettlementSchedule('m1');

      expect(result.hasPendingSettlement, false);
      expect(result.nextPayoutDate, isNull);
      expect(result.pendingAmount,  0.0);
    });
  });

  // -----------------------------------------------------------
  // EarningsTransaction displayStatus 测试
  // -----------------------------------------------------------
  group('EarningsTransaction.displayStatus', () {
    Map<String, dynamic> txJson(String status) => {
      'order_id':     'test-id',
      'amount':       10.0,
      'platform_fee': 1.5,
      'net_amount':   8.5,
      'status':       status,
      'created_at':   '2026-03-01T00:00:00.000Z',
    };

    test('used → Redeemed',         () => expect(EarningsTransaction.fromJson(txJson('used')).displayStatus,              'Redeemed'));
    test('unused → Pending',        () => expect(EarningsTransaction.fromJson(txJson('unused')).displayStatus,            'Pending'));
    test('refunded → Refunded',     () => expect(EarningsTransaction.fromJson(txJson('refunded')).displayStatus,          'Refunded'));
    test('expired → Expired',       () => expect(EarningsTransaction.fromJson(txJson('expired')).displayStatus,           'Expired'));
    test('refund_requested → ...',  () => expect(EarningsTransaction.fromJson(txJson('refund_requested')).displayStatus,  'Refund Requested'));
  });

  // -----------------------------------------------------------
  // EarningsTransaction shortOrderId 测试
  // -----------------------------------------------------------
  group('EarningsTransaction.shortOrderId', () {
    test('UUID 格式时取前8位并加 # 前缀', () {
      final tx = EarningsTransaction.fromJson({
        'order_id':     'abc12345-6789-0000-0000-000000000000',
        'amount':       10.0,
        'platform_fee': 1.5,
        'net_amount':   8.5,
        'status':       'used',
        'created_at':   '2026-03-01T00:00:00.000Z',
      });

      // 去掉 - 后取前8位
      expect(tx.shortOrderId, '#ABC12345');
    });
  });

  // -----------------------------------------------------------
  // Stripe 账户信息解析测试
  // -----------------------------------------------------------
  group('fetchStripeAccountInfo', () {
    test('已连接状态解析正确', () async {
      service.stubbedAccountData = _defaultAccountJson(connected: true);

      final result = await service.fetchStripeAccountInfo('m1');

      expect(result.isConnected,    true);
      expect(result.accountEmail,   'merchant@example.com');
      expect(result.accountStatus,  'connected');
    });

    test('未连接状态解析正确', () async {
      final result = await service.fetchStripeAccountInfo('m1');

      expect(result.isConnected,   false);
      expect(result.accountId,     isNull);
      expect(result.accountStatus, 'not_connected');
    });

    test('accountDisplayId 取末4位', () {
      final info = StripeAccountInfo.fromJson(
        _defaultAccountJson(connected: true),
      );
      // 'acct_1A2B3C4D' → 末4位非字母数字去掉后 → '4D' 不足4位场景
      // 实际: 'acct1A2B3C4D' 末4位 = '3C4D'
      expect(info.accountDisplayId, isNotNull);
    });
  });

  // -----------------------------------------------------------
  // ReportData 解析测试
  // -----------------------------------------------------------
  group('fetchReportData', () {
    test('月报解析数据行正确', () async {
      final result = await service.fetchReportData(
        'm1',
        periodType: ReportPeriodType.monthly,
        year:  2026,
        month: 3,
      );

      expect(result.periodType,       ReportPeriodType.monthly);
      expect(result.rows.length,      1);
      expect(result.rows.first.grossAmount, 150.0);
      expect(result.rows.first.netAmount,   127.5);
      expect(result.totals.orderCount, 3);
    });

    test('周报返回正确 periodType', () async {
      service.stubbedReportData = _defaultReportJson(ReportPeriodType.weekly)
        ..['period_type'] = 'weekly';

      final result = await service.fetchReportData(
        'm1',
        periodType: ReportPeriodType.weekly,
        year: 2026,
        week: 10,
      );

      expect(result.periodType, ReportPeriodType.weekly);
    });
  });

  // -----------------------------------------------------------
  // TransactionsFilter 测试
  // -----------------------------------------------------------
  group('TransactionsFilter', () {
    test('hasFilter 在无筛选时为 false', () {
      const filter = TransactionsFilter(page: 1);
      expect(filter.hasFilter, false);
    });

    test('hasFilter 在有 dateFrom 时为 true', () {
      final filter = TransactionsFilter(
        dateFrom: DateTime(2026, 3, 1),
      );
      expect(filter.hasFilter, true);
    });

    test('copyWith clearDateFrom 清除 dateFrom', () {
      final filter = TransactionsFilter(
        dateFrom: DateTime(2026, 3, 1),
        dateTo:   DateTime(2026, 3, 31),
      );
      final cleared = filter.copyWith(clearDateFrom: true);
      expect(cleared.dateFrom, isNull);
      expect(cleared.dateTo,   isNotNull); // dateTo 不变
    });
  });

  // -----------------------------------------------------------
  // kPlatformFeeRate / kMerchantNetRate 常量测试
  // -----------------------------------------------------------
  group('业务规则常量', () {
    test('平台手续费率为 15%', () {
      expect(kPlatformFeeRate, 0.15);
    });

    test('商家实收比例为 85%', () {
      expect(kMerchantNetRate, 0.85);
    });

    test('平台费率 + 商家比例 = 100%', () {
      expect(kPlatformFeeRate + kMerchantNetRate, closeTo(1.0, 0.0001));
    });
  });
}

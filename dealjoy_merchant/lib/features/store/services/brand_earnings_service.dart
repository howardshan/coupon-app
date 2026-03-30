// 品牌佣金收益服务层
// 封装所有与 merchant-brand Edge Function 中佣金相关端点的通信
// 路由格式: merchant-brand/earnings/xxx (GET/POST)

import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/brand_earnings_data.dart';
import './store_service.dart';

// =============================================================
// BrandEarningsService — 品牌收益 API 调用服务类
// =============================================================
class BrandEarningsService {
  BrandEarningsService(this._supabase);

  final SupabaseClient _supabase;

  // Edge Function 名称（与 StoreService 中的 _brandFunctionName 对应）
  static const String _fn = 'merchant-brand';

  // =============================================================
  // fetchSummary — 获取品牌月度收益概览
  // =============================================================
  /// [month] — 月份 DateTime（只取年月，格式化为 YYYY-MM）
  Future<BrandEarningsSummary> fetchSummary(String month) async {
    try {
      final response = await _supabase.functions.invoke(
        '$_fn/earnings/summary?month=$month',
        method: HttpMethod.get,
        headers: StoreService.merchantIdHeaders,
      );

      final data = _parseResponse(response);
      _checkError(data);

      return BrandEarningsSummary.fromJson(data);
    } catch (e) {
      if (e is Exception) rethrow;
      return BrandEarningsSummary.empty(month);
    }
  }

  // =============================================================
  // fetchTransactions — 获取品牌佣金交易明细
  // =============================================================
  /// 返回: items 列表 + total 总条数 + totals 汇总金额
  Future<({List<BrandTransaction> items, int total, Map<String, double> totals})>
      fetchTransactions({
    String? month,
    int page = 1,
    int perPage = 20,
  }) async {
    try {
      final params = <String, String>{
        'page': page.toString(),
        'per_page': perPage.toString(),
      };
      if (month != null) params['month'] = month;

      final queryString = params.entries
          .map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
          .join('&');

      final response = await _supabase.functions.invoke(
        '$_fn/earnings/transactions?$queryString',
        method: HttpMethod.get,
        headers: StoreService.merchantIdHeaders,
      );

      final data = _parseResponse(response);
      _checkError(data);

      final itemsJson = data['data'] as List<dynamic>? ?? [];
      final items = itemsJson
          .map((e) => BrandTransaction.fromJson(e as Map<String, dynamic>))
          .toList();

      final total = (data['total'] as num?)?.toInt() ?? items.length;

      final totalsJson = data['totals'] as Map<String, dynamic>? ?? {};
      final totals = totalsJson.map(
        (k, v) => MapEntry(k, (v as num?)?.toDouble() ?? 0.0),
      );

      return (items: items, total: total, totals: totals);
    } catch (e) {
      if (e is Exception) rethrow;
      return (items: <BrandTransaction>[], total: 0, totals: <String, double>{});
    }
  }

  // =============================================================
  // fetchBalance — 获取品牌可提现余额
  // =============================================================
  Future<BrandBalance> fetchBalance() async {
    try {
      final response = await _supabase.functions.invoke(
        '$_fn/earnings/balance',
        method: HttpMethod.get,
        headers: StoreService.merchantIdHeaders,
      );

      final data = _parseResponse(response);
      _checkError(data);

      return BrandBalance.fromJson(data);
    } catch (e) {
      return BrandBalance.zero();
    }
  }

  // =============================================================
  // requestWithdrawal — 发起品牌提现申请
  // =============================================================
  Future<BrandWithdrawalRecord> requestWithdrawal(double amount) async {
    final response = await _supabase.functions.invoke(
      '$_fn/earnings/withdraw',
      method: HttpMethod.post,
      headers: StoreService.merchantIdHeaders,
      body: {'amount': amount},
    );

    final data = _parseResponse(response);
    _checkError(data);

    final recordJson = data['withdrawal'] as Map<String, dynamic>? ?? data;
    return BrandWithdrawalRecord.fromJson(recordJson);
  }

  // =============================================================
  // fetchWithdrawalHistory — 获取品牌提现记录
  // =============================================================
  Future<List<BrandWithdrawalRecord>> fetchWithdrawalHistory() async {
    try {
      final response = await _supabase.functions.invoke(
        '$_fn/earnings/withdrawal-history',
        method: HttpMethod.get,
        headers: StoreService.merchantIdHeaders,
      );

      final data = _parseResponse(response);
      _checkError(data);

      final list = (data['data'] as List<dynamic>?) ??
          (data['withdrawals'] as List<dynamic>?) ??
          [];
      return list
          .map((e) => BrandWithdrawalRecord.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      return [];
    }
  }

  // =============================================================
  // fetchStripeConnectUrl — 获取品牌 Stripe Connect onboarding URL
  // =============================================================
  Future<String> fetchStripeConnectUrl() async {
    final response = await _supabase.functions.invoke(
      '$_fn/stripe/connect',
      method: HttpMethod.post,
      headers: StoreService.merchantIdHeaders,
    );

    final data = _parseResponse(response);
    _checkError(data);

    final url = data['url'] as String?;
    if (url == null || url.isEmpty) {
      throw Exception('Invalid Stripe Connect URL received');
    }
    return url;
  }

  // =============================================================
  // refreshStripeStatus — 同步品牌 Stripe 账户状态
  // =============================================================
  Future<BrandStripeAccount> refreshStripeStatus() async {
    final response = await _supabase.functions.invoke(
      '$_fn/stripe/refresh',
      method: HttpMethod.post,
      headers: StoreService.merchantIdHeaders,
    );

    final data = _parseResponse(response);
    _checkError(data);

    return BrandStripeAccount.fromJson(data);
  }

  // =============================================================
  // fetchStripeDashboardUrl — 获取品牌 Stripe Dashboard 管理链接
  // =============================================================
  Future<String> fetchStripeDashboardUrl() async {
    final response = await _supabase.functions.invoke(
      '$_fn/stripe/dashboard',
      method: HttpMethod.get,
      headers: StoreService.merchantIdHeaders,
    );

    final data = _parseResponse(response);
    _checkError(data);

    final url = data['url'] as String?;
    if (url == null || url.isEmpty) {
      throw Exception('Invalid Stripe Dashboard URL received');
    }
    return url;
  }

  // =============================================================
  // fetchStripeAccount — 获取品牌 Stripe 账户信息
  // =============================================================
  Future<BrandStripeAccount> fetchStripeAccount() async {
    try {
      final response = await _supabase.functions.invoke(
        '$_fn/stripe/account',
        method: HttpMethod.get,
        headers: StoreService.merchantIdHeaders,
      );

      final data = _parseResponse(response);
      _checkError(data);

      return BrandStripeAccount.fromJson(data);
    } catch (e) {
      return BrandStripeAccount.notConnected();
    }
  }

  // =============================================================
  // 私有工具方法
  // =============================================================

  /// 解析 FunctionResponse 为 Map
  Map<String, dynamic> _parseResponse(FunctionResponse response) {
    final data = response.data;
    if (data is Map<String, dynamic>) return data;
    if (data is String) {
      try {
        return jsonDecode(data) as Map<String, dynamic>;
      } catch (_) {}
    }
    return {};
  }

  /// 检查响应中的 error 字段
  void _checkError(Map<String, dynamic> data) {
    if (data['error'] != null) {
      throw Exception('BrandEarningsService: ${data['error']}');
    }
  }
}

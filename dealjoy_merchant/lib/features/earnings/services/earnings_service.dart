// 财务与结算业务服务层
// 封装所有与 Edge Function merchant-earnings 的通信逻辑
// 对应路由:
//   GET /merchant-earnings/summary             — 收入概览
//   GET /merchant-earnings/transactions        — 交易明细（分页）
//   GET /merchant-earnings/settlement-schedule — 结算规则
//   GET /merchant-earnings/report              — 对账报表
//   GET /merchant-earnings/account             — Stripe 账户状态

import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/earnings_data.dart';

/// 财务服务自定义异常
class EarningsException implements Exception {
  final String message;
  final String code;

  const EarningsException({required this.message, required this.code});

  @override
  String toString() => 'EarningsException($code): $message';
}

/// 财务与结算所有 API 调用的服务类
class EarningsService {
  EarningsService(this._supabase);

  final SupabaseClient _supabase;

  // Edge Function 名称
  static const String _functionName = 'merchant-earnings';

  // =============================================================
  // fetchEarningsSummary — 获取月度收入概览
  // =============================================================
  /// 获取指定商家、指定月份的收入汇总
  /// [merchantId] — 商家 ID（通过 auth 自动鉴权，传入用于参数构造）
  /// [month]      — 月份 DateTime（只取年月部分）
  /// 抛出 [EarningsException] 如果请求失败
  Future<EarningsSummary> fetchEarningsSummary(
    String merchantId,
    DateTime month,
  ) async {
    try {
      // 格式化为 YYYY-MM（Edge Function 接受此格式）
      final monthStr = _formatMonth(month);
      final path = '$_functionName/summary?month=$monthStr';

      final response = await _supabase.functions.invoke(
        path,
        method: HttpMethod.get,
      );

      final data = _parseResponse(response);
      _checkError(data);

      return EarningsSummary.fromJson(data);
    } on EarningsException {
      rethrow;
    } on FunctionException catch (e) {
      final body = _tryParseBody(e.details);
      throw EarningsException(
        code:    body?['error'] as String? ?? 'network_error',
        message: body?['message'] as String? ?? 'Failed to fetch earnings summary.',
      );
    } catch (e) {
      if (e is EarningsException) rethrow;
      throw const EarningsException(
        code:    'network_error',
        message: 'Network error. Please check your connection.',
      );
    }
  }

  // =============================================================
  // fetchTransactions — 获取分页交易明细
  // =============================================================
  /// 获取指定商家的交易明细，支持日期筛选和分页
  /// [merchantId] — 商家 ID
  /// [from]       — 起始日期（可选）
  /// [to]         — 结束日期（可选）
  /// [page]       — 页码，从 1 开始
  /// 抛出 [EarningsException] 如果请求失败
  Future<PagedTransactions> fetchTransactions(
    String merchantId, {
    DateTime? from,
    DateTime? to,
    int page = 1,
    int perPage = 20,
  }) async {
    try {
      final params = <String, String>{
        'page':     page.toString(),
        'per_page': perPage.toString(),
      };
      if (from != null) params['date_from'] = _formatDate(from);
      if (to   != null) params['date_to']   = _formatDate(to);

      final queryString = _buildQueryString(params);
      final path = queryString.isEmpty
          ? '$_functionName/transactions'
          : '$_functionName/transactions?$queryString';

      final response = await _supabase.functions.invoke(
        path,
        method: HttpMethod.get,
      );

      final data = _parseResponse(response);
      _checkError(data);

      return PagedTransactions.fromJson(data);
    } on EarningsException {
      rethrow;
    } on FunctionException catch (e) {
      final body = _tryParseBody(e.details);
      throw EarningsException(
        code:    body?['error'] as String? ?? 'network_error',
        message: body?['message'] as String? ?? 'Failed to fetch transactions.',
      );
    } catch (e) {
      if (e is EarningsException) rethrow;
      throw const EarningsException(
        code:    'network_error',
        message: 'Network error. Please check your connection.',
      );
    }
  }

  // =============================================================
  // fetchSettlementSchedule — 获取结算规则与下次打款信息
  // =============================================================
  /// 返回 [SettlementSchedule]：规则说明 + 下次打款日期 + 待结算金额
  Future<SettlementSchedule> fetchSettlementSchedule(String merchantId) async {
    try {
      final response = await _supabase.functions.invoke(
        '$_functionName/settlement-schedule',
        method: HttpMethod.get,
      );

      final data = _parseResponse(response);
      _checkError(data);

      return SettlementSchedule.fromJson(data);
    } on EarningsException {
      rethrow;
    } on FunctionException catch (e) {
      // 结算规则加载失败时返回默认值（非阻断性错误）
      final body = _tryParseBody(e.details);
      final code = body?['error'] as String? ?? 'network_error';
      // 若是鉴权失败则抛出
      if (code == 'unauthorized' || code == 'merchant_not_found') {
        throw EarningsException(code: code, message: body?['message'] as String? ?? 'Unauthorized');
      }
      // 其他情况返回默认结算规则
      return SettlementSchedule.defaultSchedule();
    } catch (e) {
      if (e is EarningsException) rethrow;
      return SettlementSchedule.defaultSchedule();
    }
  }

  // =============================================================
  // fetchReportData — 获取对账报表（P2）
  // =============================================================
  /// 获取月度或周度对账报表数据
  /// [periodType] — 'monthly' 或 'weekly'
  /// [year]       — 年份
  /// [month]      — 月份（仅 monthly 有效）
  /// [week]       — 周次（仅 weekly 有效）
  Future<ReportData> fetchReportData(
    String merchantId, {
    required ReportPeriodType periodType,
    required int year,
    int? month,
    int? week,
  }) async {
    try {
      final params = <String, String>{
        'period_type': periodType.apiValue,
        'year':        year.toString(),
      };
      if (month != null) params['month'] = month.toString();
      if (week  != null) params['week']  = week.toString();

      final queryString = _buildQueryString(params);
      final path = '$_functionName/report?$queryString';

      final response = await _supabase.functions.invoke(
        path,
        method: HttpMethod.get,
      );

      final data = _parseResponse(response);
      _checkError(data);

      return ReportData.fromJson(data);
    } on EarningsException {
      rethrow;
    } on FunctionException catch (e) {
      final body = _tryParseBody(e.details);
      throw EarningsException(
        code:    body?['error'] as String? ?? 'network_error',
        message: body?['message'] as String? ?? 'Failed to fetch report data.',
      );
    } catch (e) {
      if (e is EarningsException) rethrow;
      throw const EarningsException(
        code:    'network_error',
        message: 'Network error. Please check your connection.',
      );
    }
  }

  // =============================================================
  // fetchStripeAccountInfo — 获取 Stripe Connect 账户状态
  // =============================================================
  /// 返回 [StripeAccountInfo]：是否连接 + 账户基本信息
  Future<StripeAccountInfo> fetchStripeAccountInfo(String merchantId) async {
    try {
      final response = await _supabase.functions.invoke(
        '$_functionName/account',
        method: HttpMethod.get,
      );

      final data = _parseResponse(response);
      _checkError(data);

      return StripeAccountInfo.fromJson(data);
    } on EarningsException {
      rethrow;
    } catch (e) {
      if (e is EarningsException) rethrow;
      // 账户信息加载失败时返回未连接状态（非阻断性）
      return StripeAccountInfo.notConnected();
    }
  }

  // =============================================================
  // 提现相关方法（调 merchant-withdrawal Edge Function）
  // =============================================================

  static const String _withdrawalFn = 'merchant-withdrawal';

  /// 获取可提现余额
  Future<WithdrawalBalance> fetchWithdrawalBalance() async {
    try {
      final response = await _supabase.functions.invoke(
        '$_withdrawalFn/balance',
        method: HttpMethod.get,
      );
      final data = _parseResponse(response);
      if (data['error'] != null) {
        throw EarningsException(
          code: 'balance_error',
          message: data['error'] as String? ?? 'Failed to fetch balance',
        );
      }
      return WithdrawalBalance.fromJson(data);
    } catch (e) {
      if (e is EarningsException) rethrow;
      return WithdrawalBalance.zero();
    }
  }

  /// 发起手动提现
  Future<WithdrawalRecord> requestWithdrawal(double amount) async {
    final response = await _supabase.functions.invoke(
      '$_withdrawalFn/withdraw',
      method: HttpMethod.post,
      body: {'amount': amount},
    );
    final data = _parseResponse(response);
    if (data['error'] != null) {
      throw EarningsException(
        code: 'withdrawal_error',
        message: data['error'] as String? ?? 'Failed to request withdrawal',
      );
    }
    return WithdrawalRecord.fromJson(
      data['withdrawal'] as Map<String, dynamic>? ?? data,
    );
  }

  /// 获取提现记录
  Future<List<WithdrawalRecord>> fetchWithdrawalHistory() async {
    try {
      final response = await _supabase.functions.invoke(
        '$_withdrawalFn/history',
        method: HttpMethod.get,
      );
      final data = _parseResponse(response);
      if (data['error'] != null) {
        throw EarningsException(
          code: 'history_error',
          message: data['error'] as String? ?? 'Failed to fetch history',
        );
      }
      final list = data['withdrawals'] as List<dynamic>? ?? [];
      return list
          .map((e) => WithdrawalRecord.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      if (e is EarningsException) rethrow;
      return [];
    }
  }

  /// 获取提现设置
  Future<WithdrawalSettings> fetchWithdrawalSettings() async {
    try {
      final response = await _supabase.functions.invoke(
        '$_withdrawalFn/settings',
        method: HttpMethod.get,
      );
      final data = _parseResponse(response);
      if (data['error'] != null) return WithdrawalSettings.defaults();
      return WithdrawalSettings.fromJson(
        data['settings'] as Map<String, dynamic>? ?? data,
      );
    } catch (_) {
      return WithdrawalSettings.defaults();
    }
  }

  /// 更新提现设置
  Future<void> updateWithdrawalSettings({
    bool? autoEnabled,
    String? frequency,
    int? day,
  }) async {
    final body = <String, dynamic>{};
    if (autoEnabled != null) body['auto_withdrawal_enabled'] = autoEnabled;
    if (frequency != null) body['auto_withdrawal_frequency'] = frequency;
    if (day != null) body['auto_withdrawal_day'] = day;

    final response = await _supabase.functions.invoke(
      '$_withdrawalFn/settings',
      method: HttpMethod.patch,
      body: body,
    );
    final data = _parseResponse(response);
    if (data['error'] != null) {
      throw EarningsException(
        code: 'settings_error',
        message: data['error'] as String? ?? 'Failed to update settings',
      );
    }
  }

  // =============================================================
  // 私有工具方法
  // =============================================================

  /// 解析 FunctionResponse 为 `Map<String, dynamic>`
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

  /// 检查响应体中是否包含 error 字段，若有则抛出 EarningsException
  void _checkError(Map<String, dynamic> data) {
    if (data['error'] != null) {
      throw EarningsException(
        code:    data['error'] as String,
        message: data['message'] as String? ?? 'Request failed',
      );
    }
  }

  /// 尝试解析错误体，失败返回 null
  Map<String, dynamic>? _tryParseBody(dynamic details) {
    try {
      if (details is Map<String, dynamic>) return details;
      if (details is String) {
        return jsonDecode(details) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  /// 格式化日期为 YYYY-MM-DD
  String _formatDate(DateTime date) {
    final y = date.year.toString();
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  /// 格式化月份为 YYYY-MM
  String _formatMonth(DateTime date) {
    final y = date.year.toString();
    final m = date.month.toString().padLeft(2, '0');
    return '$y-$m';
  }

  /// 构造 URL 查询字符串
  String _buildQueryString(Map<String, String> params) {
    if (params.isEmpty) return '';
    return params.entries
        .map((e) =>
            '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
        .join('&');
  }
}

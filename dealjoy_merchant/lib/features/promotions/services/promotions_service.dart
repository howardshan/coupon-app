// 广告推广业务服务层
// 封装所有与 Edge Function merchant-ads 和 merchant-ad-reports 的通信逻辑
// 对应路由:
//   merchant-ads:        get_account, list_campaigns, get_campaign,
//                        create_campaign, update_campaign, pause_campaign,
//                        resume_campaign, delete_campaign,
//                        create_recharge, list_recharges,
//                        get_placement_configs
//   merchant-ad-reports: overview, campaign_stats, daily_trend

import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/ad_account.dart';
import '../models/ad_campaign.dart';
import '../models/ad_recharge.dart';
import '../models/ad_daily_stat.dart';
import '../models/ad_placement_config.dart';
import '../../store/services/store_service.dart';

/// 广告推广服务自定义异常
class PromotionsException implements Exception {
  final String message;
  final String code;

  const PromotionsException({required this.message, required this.code});

  @override
  String toString() => 'PromotionsException($code): $message';
}

/// 广告推广所有 API 调用的服务类
class PromotionsService {
  PromotionsService(this._supabase);

  final SupabaseClient _supabase;

  // Edge Function 名称
  static const String _adsFn     = 'merchant-ads';
  static const String _reportsFn = 'merchant-ad-reports';

  // 复用 StoreService 的 merchantIdHeaders（品牌管理员多门店切换支持）
  Map<String, String> get _headers => StoreService.merchantIdHeaders;

  // =============================================================
  // 广告账户
  // =============================================================

  /// 获取当前商家的广告账户信息（余额、消费统计等）
  Future<AdAccount> fetchAccount() async {
    final response = await _supabase.functions.invoke(
      _adsFn,
      method: HttpMethod.post,
      headers: _headers,
      body: {'action': 'get_account'},
    );
    final data = _parseResponse(response);
    _checkError(data);
    // Edge Function 返回 { account: {...} } 或直接返回账户对象
    final accountJson = data['account'] as Map<String, dynamic>? ?? data;
    return AdAccount.fromJson(accountJson);
  }

  // =============================================================
  // 广告计划 CRUD
  // =============================================================

  /// 获取广告计划列表
  /// [status]   — 按状态筛选（active/paused/exhausted/ended/admin_paused），null 表示全部
  /// [page]     — 页码，从 1 开始
  /// [pageSize] — 每页数量
  Future<List<AdCampaign>> fetchCampaigns({
    String? status,
    int page = 1,
    int pageSize = 20,
  }) async {
    final body = <String, dynamic>{
      'action':    'list_campaigns',
      'page':      page,
      'page_size': pageSize,
    };
    if (status != null && status.isNotEmpty) body['status'] = status;

    final response = await _supabase.functions.invoke(
      _adsFn,
      method: HttpMethod.post,
      headers: _headers,
      body: body,
    );
    final data = _parseResponse(response);
    _checkError(data);

    final list = data['campaigns'] as List<dynamic>? ?? [];
    return list
        .map((e) => AdCampaign.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 获取单个广告计划详情
  Future<AdCampaign> fetchCampaign(String campaignId) async {
    final response = await _supabase.functions.invoke(
      _adsFn,
      method: HttpMethod.post,
      headers: _headers,
      body: {
        'action':      'get_campaign',
        'campaign_id': campaignId,
      },
    );
    final data = _parseResponse(response);
    _checkError(data);

    final campaignJson = data['campaign'] as Map<String, dynamic>? ?? data;
    return AdCampaign.fromJson(campaignJson);
  }

  /// 创建新广告计划
  /// [campaign] — 用 AdCampaign.toCreateJson() 序列化的参数
  Future<AdCampaign> createCampaign(AdCampaign campaign) async {
    final response = await _supabase.functions.invoke(
      _adsFn,
      method: HttpMethod.post,
      headers: _headers,
      body: {
        'action':   'create_campaign',
        'campaign': campaign.toCreateJson(),
      },
    );
    final data = _parseResponse(response);
    _checkError(data);

    final campaignJson = data['campaign'] as Map<String, dynamic>? ?? data;
    return AdCampaign.fromJson(campaignJson);
  }

  /// 更新广告计划（仅允许修改 dailyBudget / scheduleHours）
  Future<AdCampaign> updateCampaign(
    String campaignId, {
    double? dailyBudget,
    List<int>? scheduleHours,
  }) async {
    final updates = <String, dynamic>{};
    if (dailyBudget != null)    updates['daily_budget']   = dailyBudget;
    if (scheduleHours != null)  updates['schedule_hours'] = scheduleHours;

    final response = await _supabase.functions.invoke(
      _adsFn,
      method: HttpMethod.post,
      headers: _headers,
      body: {
        'action':      'update_campaign',
        'campaign_id': campaignId,
        'updates':     updates,
      },
    );
    final data = _parseResponse(response);
    _checkError(data);

    final campaignJson = data['campaign'] as Map<String, dynamic>? ?? data;
    return AdCampaign.fromJson(campaignJson);
  }

  /// 暂停广告计划
  Future<void> pauseCampaign(String campaignId) async {
    final response = await _supabase.functions.invoke(
      _adsFn,
      method: HttpMethod.post,
      headers: _headers,
      body: {
        'action':      'pause_campaign',
        'campaign_id': campaignId,
      },
    );
    final data = _parseResponse(response);
    _checkError(data);
  }

  /// 恢复广告计划投放
  Future<void> resumeCampaign(String campaignId) async {
    final response = await _supabase.functions.invoke(
      _adsFn,
      method: HttpMethod.post,
      headers: _headers,
      body: {
        'action':      'resume_campaign',
        'campaign_id': campaignId,
      },
    );
    final data = _parseResponse(response);
    _checkError(data);
  }

  /// 删除广告计划（仅 paused/ended 状态可删除）
  Future<void> deleteCampaign(String campaignId) async {
    final response = await _supabase.functions.invoke(
      _adsFn,
      method: HttpMethod.post,
      headers: _headers,
      body: {
        'action':      'delete_campaign',
        'campaign_id': campaignId,
      },
    );
    final data = _parseResponse(response);
    _checkError(data);
  }

  // =============================================================
  // 充值
  // =============================================================

  /// 发起广告余额充值，返回 Stripe PaymentIntent clientSecret
  /// [amount] — 充值金额（美元），最小 10.0
  Future<String> createRecharge(double amount) async {
    final response = await _supabase.functions.invoke(
      _adsFn,
      method: HttpMethod.post,
      headers: _headers,
      body: {
        'action': 'create_recharge',
        'amount': amount,
      },
    );
    final data = _parseResponse(response);
    _checkError(data);

    final clientSecret = data['client_secret'] as String?;
    if (clientSecret == null || clientSecret.isEmpty) {
      throw const PromotionsException(
        code:    'recharge_error',
        message: 'Failed to get payment client secret.',
      );
    }
    return clientSecret;
  }

  /// 获取充值记录列表（分页）
  Future<List<AdRecharge>> fetchRecharges({
    int page = 1,
    int pageSize = 20,
  }) async {
    final response = await _supabase.functions.invoke(
      _adsFn,
      method: HttpMethod.post,
      headers: _headers,
      body: {
        'action':    'list_recharges',
        'page':      page,
        'page_size': pageSize,
      },
    );
    final data = _parseResponse(response);
    _checkError(data);

    final list = data['recharges'] as List<dynamic>? ?? [];
    return list
        .map((e) => AdRecharge.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // =============================================================
  // 广告位配置
  // =============================================================

  /// 获取所有可投放位置的配置（最低出价、容量、计费方式）
  Future<List<AdPlacementConfig>> fetchPlacementConfigs() async {
    final response = await _supabase.functions.invoke(
      _adsFn,
      method: HttpMethod.post,
      headers: _headers,
      body: {'action': 'get_placement_configs'},
    );
    final data = _parseResponse(response);
    _checkError(data);

    final list = data['configs'] as List<dynamic>? ?? [];
    return list
        .map((e) => AdPlacementConfig.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // =============================================================
  // 报告（调 merchant-ad-reports）
  // =============================================================

  /// 获取广告推广总览数据（余额、今日/本周/本月花费、CTR 等汇总指标）
  Future<Map<String, dynamic>> fetchOverview() async {
    final response = await _supabase.functions.invoke(
      _reportsFn,
      method: HttpMethod.post,
      headers: _headers,
      body: {'action': 'overview'},
    );
    final data = _parseResponse(response);
    _checkError(data);
    return data;
  }

  /// 获取单个广告计划的每日统计数据
  /// [campaignId] — 广告计划 ID
  /// [startDate]  — 统计起始日期（可选）
  /// [endDate]    — 统计结束日期（可选）
  Future<List<AdDailyStat>> fetchCampaignStats(
    String campaignId, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final body = <String, dynamic>{
      'action':      'campaign_stats',
      'campaign_id': campaignId,
    };
    if (startDate != null) body['start_date'] = _formatDate(startDate);
    if (endDate != null)   body['end_date']   = _formatDate(endDate);

    final response = await _supabase.functions.invoke(
      _reportsFn,
      method: HttpMethod.post,
      headers: _headers,
      body: body,
    );
    final data = _parseResponse(response);
    _checkError(data);

    final list = data['stats'] as List<dynamic>? ?? [];
    return list
        .map((e) => AdDailyStat.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 获取商家所有广告计划的整体每日趋势数据（汇总所有计划）
  /// [startDate]  — 统计起始日期（可选）
  /// [endDate]    — 统计结束日期（可选）
  Future<List<AdDailyStat>> fetchDailyTrend({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final body = <String, dynamic>{'action': 'daily_trend'};
    if (startDate != null) body['start_date'] = _formatDate(startDate);
    if (endDate != null)   body['end_date']   = _formatDate(endDate);

    final response = await _supabase.functions.invoke(
      _reportsFn,
      method: HttpMethod.post,
      headers: _headers,
      body: body,
    );
    final data = _parseResponse(response);
    _checkError(data);

    final list = data['trend'] as List<dynamic>? ?? [];
    return list
        .map((e) => AdDailyStat.fromJson(e as Map<String, dynamic>))
        .toList();
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

  /// 检查响应体中是否包含 error 字段，若有则抛出 PromotionsException
  void _checkError(Map<String, dynamic> data) {
    if (data['error'] != null) {
      throw PromotionsException(
        code:    data['error'] as String? ?? 'unknown_error',
        message: data['message'] as String? ?? 'Request failed',
      );
    }
  }

  /// 格式化日期为 YYYY-MM-DD（Edge Function 统一接受此格式）
  String _formatDate(DateTime date) {
    final y = date.year.toString();
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}

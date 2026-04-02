// 广告投放模块状态管理
// 使用 Riverpod AsyncNotifier 模式
// Providers:
//   promotionsServiceProvider  — PromotionsService 单例
//   adAccountProvider          — 广告账户（余额等）
//   campaignsProvider          — Campaign 列表
//   placementConfigsProvider   — 广告位配置
//   rechargesProvider          — 充值记录

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/promotions_models.dart';
import '../services/promotions_service.dart';

// =============================================================
// 基础依赖 Provider
// =============================================================

/// PromotionsService Provider（单例）
final promotionsServiceProvider = Provider<PromotionsService>((ref) {
  return PromotionsService(Supabase.instance.client);
});

/// 当前登录用户对应的 merchant_id（从 merchants 表查询）
final _merchantIdProvider = FutureProvider<String>((ref) async {
  final supabase = Supabase.instance.client;
  final user = supabase.auth.currentUser;
  if (user == null) return '';

  try {
    final result = await supabase
        .from('merchants')
        .select('id')
        .eq('user_id', user.id)
        .maybeSingle();
    return result?['id'] as String? ?? '';
  } catch (_) {
    return '';
  }
});

// =============================================================
// AdAccountNotifier — 广告账户
// =============================================================
/// 广告账户 Notifier（余额、总消费、状态等）
class AdAccountNotifier extends AsyncNotifier<AdAccount> {
  @override
  Future<AdAccount> build() async {
    final merchantId = await ref.watch(_merchantIdProvider.future);
    if (merchantId.isEmpty) return AdAccount.empty();

    final service = ref.read(promotionsServiceProvider);
    return service.fetchAdAccount(merchantId);
  }

  /// 手动刷新（充值成功后调用）
  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => build());
  }
}

/// 广告账户 Provider
final adAccountProvider =
    AsyncNotifierProvider<AdAccountNotifier, AdAccount>(AdAccountNotifier.new);

// =============================================================
// CampaignsNotifier — Campaign 列表
// =============================================================
/// Campaign 列表 Notifier
class CampaignsNotifier extends AsyncNotifier<List<AdCampaign>> {
  @override
  Future<List<AdCampaign>> build() async {
    final merchantId = await ref.watch(_merchantIdProvider.future);
    if (merchantId.isEmpty) return [];

    final service = ref.read(promotionsServiceProvider);
    return service.fetchCampaigns(merchantId);
  }

  /// 手动刷新
  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => build());
  }

  /// 暂停 Campaign
  Future<void> pauseCampaign(String campaignId) async {
    final merchantId = await ref.read(_merchantIdProvider.future);
    if (merchantId.isEmpty) return;

    final service = ref.read(promotionsServiceProvider);
    await service.updateCampaignStatus(merchantId, campaignId, 'paused');
    await refresh();
  }

  /// 恢复 Campaign（从暂停/已结束状态变为 active）
  Future<void> resumeCampaign(String campaignId) async {
    final merchantId = await ref.read(_merchantIdProvider.future);
    if (merchantId.isEmpty) return;

    final service = ref.read(promotionsServiceProvider);
    await service.updateCampaignStatus(merchantId, campaignId, 'active');
    await refresh();
  }

  /// 删除 Campaign
  Future<void> deleteCampaign(String campaignId) async {
    final merchantId = await ref.read(_merchantIdProvider.future);
    if (merchantId.isEmpty) return;

    final service = ref.read(promotionsServiceProvider);
    await service.deleteCampaign(merchantId, campaignId);
    await refresh();
  }

  /// 创建新 Campaign
  Future<AdCampaign> createCampaign(
      String merchantId, Map<String, dynamic> params) async {
    final service = ref.read(promotionsServiceProvider);
    final campaign = await service.createCampaign(merchantId, params);
    await refresh();
    return campaign;
  }

  /// 更新 Campaign
  Future<void> updateCampaign(
      String merchantId, String campaignId, Map<String, dynamic> params) async {
    final service = ref.read(promotionsServiceProvider);
    await service.updateCampaign(merchantId, campaignId, params);
    await refresh();
  }
}

/// Campaign 列表 Provider
final campaignsProvider =
    AsyncNotifierProvider<CampaignsNotifier, List<AdCampaign>>(
        CampaignsNotifier.new);

// =============================================================
// placementConfigsProvider — 广告位配置
// =============================================================
/// 广告位配置列表（页面初始化时加载一次）
final placementConfigsProvider =
    FutureProvider<List<AdPlacementConfig>>((ref) async {
  final service = ref.read(promotionsServiceProvider);
  return service.fetchPlacementConfigs();
});

// =============================================================
// RechargesNotifier — 充值记录
// =============================================================
/// 充值记录 Notifier
class RechargesNotifier extends AsyncNotifier<List<AdRecharge>> {
  @override
  Future<List<AdRecharge>> build() async {
    final merchantId = await ref.watch(_merchantIdProvider.future);
    if (merchantId.isEmpty) return [];

    final service = ref.read(promotionsServiceProvider);
    return service.fetchRecharges(merchantId);
  }

  /// 手动刷新
  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => build());
  }
}

/// 充值记录 Provider
final rechargesProvider =
    AsyncNotifierProvider<RechargesNotifier, List<AdRecharge>>(
        RechargesNotifier.new);

// =============================================================
// campaignReportProvider — Campaign 报告数据
// =============================================================

/// 报告时间段枚举
enum ReportPeriod { sevenDays, thirtyDays, all }

/// 当前报告时间段选择
final reportPeriodProvider = StateProvider<ReportPeriod>((ref) {
  return ReportPeriod.sevenDays;
});

/// Campaign 报告数据（根据 campaignId + 时间段动态加载）
final campaignReportProvider =
    FutureProvider.family<AdCampaignReport, String>((ref, campaignId) async {
  final period = ref.watch(reportPeriodProvider);
  final merchantId = await ref.watch(_merchantIdProvider.future);
  if (merchantId.isEmpty) return AdCampaignReport.empty(campaignId);

  final service = ref.read(promotionsServiceProvider);

  // 根据选择的时间段计算 startDate
  final now = DateTime.now();
  DateTime? startDate;
  switch (period) {
    case ReportPeriod.sevenDays:
      startDate = now.subtract(const Duration(days: 7));
      break;
    case ReportPeriod.thirtyDays:
      startDate = now.subtract(const Duration(days: 30));
      break;
    case ReportPeriod.all:
      startDate = null;
      break;
  }

  return service.fetchCampaignReport(merchantId, campaignId,
      startDate: startDate);
});

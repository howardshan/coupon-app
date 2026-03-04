// ============================================================
// Influencer 合作 — Riverpod Provider 骨架
// 模块: 12. Influencer 合作
// 优先级: P2/V2 — Provider 骨架，V2 接入真实数据
// ============================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/influencer_models.dart';
import '../services/influencer_service.dart';

// ============================================================
// 聚合状态
// ============================================================

/// Influencer 模块聚合状态
class InfluencerState {
  const InfluencerState({
    this.campaigns = const [],
    this.applications = const [],
    this.performanceList = const [],
    this.isLoading = false,
    this.error,
  });

  final List<InfluencerCampaign> campaigns;
  final List<InfluencerApplication> applications;
  final List<InfluencerPerformance> performanceList;
  final bool isLoading;
  final String? error;

  /// 按状态过滤 Campaign 列表
  List<InfluencerCampaign> campaignsByStatus(CampaignStatus status) =>
      campaigns.where((c) => c.status == status).toList();

  /// 获取 Active Campaign 列表
  List<InfluencerCampaign> get activeCampaigns =>
      campaignsByStatus(CampaignStatus.active);

  /// 获取 Completed Campaign 列表
  List<InfluencerCampaign> get completedCampaigns =>
      campaignsByStatus(CampaignStatus.completed);

  /// 获取 Draft Campaign 列表
  List<InfluencerCampaign> get draftCampaigns =>
      campaignsByStatus(CampaignStatus.draft);

  /// 获取 Pending 申请列表
  List<InfluencerApplication> get pendingApplications =>
      applications.where((a) => a.status == ApplicationStatus.pending).toList();

  /// 创建副本（部分字段更新）
  InfluencerState copyWith({
    List<InfluencerCampaign>? campaigns,
    List<InfluencerApplication>? applications,
    List<InfluencerPerformance>? performanceList,
    bool? isLoading,
    String? error,
  }) {
    return InfluencerState(
      campaigns: campaigns ?? this.campaigns,
      applications: applications ?? this.applications,
      performanceList: performanceList ?? this.performanceList,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

// ============================================================
// InfluencerNotifier — AsyncNotifier
// ============================================================

/// Influencer 模块状态管理器
/// V2 实现时替换 TODO 存根为真实 API 调用
class InfluencerNotifier extends AsyncNotifier<InfluencerState> {
  @override
  Future<InfluencerState> build() async {
    // TODO: V2 — 初始化时通过 InfluencerService 加载 Campaign 列表:
    // final service = const InfluencerService();
    // final merchantId = ref.read(currentMerchantIdProvider);
    // final campaigns = await service.getCampaigns(merchantId);
    // return InfluencerState(campaigns: campaigns);
    return const InfluencerState();
  }

  /// 加载 Campaign 列表
  /// TODO: V2 — 调用 _service.getCampaigns()
  Future<void> loadCampaigns(String merchantId) async {
    state = const AsyncValue.loading();
    // V2: 服务层实例（V2 实现时取消注释下方逻辑）
    final service = const InfluencerService(); // ignore: unused_local_variable
    // TODO: V2 实现:
    // state = await AsyncValue.guard(() async {
    //   final campaigns = await service.getCampaigns(merchantId);
    //   return (state.value ?? const InfluencerState()).copyWith(campaigns: campaigns);
    // });
    state = const AsyncValue.data(InfluencerState());
  }

  /// 创建新 Campaign
  /// TODO: V2 — 调用 _service.createCampaign()
  Future<void> createCampaign(InfluencerCampaign campaign) async {
    // TODO: V2 实现:
    // final created = await _service.createCampaign(campaign);
    // final current = state.value ?? const InfluencerState();
    // state = AsyncValue.data(current.copyWith(
    //   campaigns: [created, ...current.campaigns],
    // ));
    throw UnimplementedError('createCampaign: TODO V2');
  }

  /// 加载申请列表
  /// TODO: V2 — 调用 _service.getApplications()
  Future<void> loadApplications(String campaignId) async {
    // TODO: V2 实现
  }

  /// 审批通过申请
  /// TODO: V2 — 调用 _service.approveApplication()
  Future<void> approveApplication(String applicationId) async {
    // TODO: V2 实现
    throw UnimplementedError('approveApplication: TODO V2');
  }

  /// 拒绝申请
  /// TODO: V2 — 调用 _service.rejectApplication()
  Future<void> rejectApplication(
    String applicationId, {
    String? reason,
  }) async {
    // TODO: V2 实现
    throw UnimplementedError('rejectApplication: TODO V2');
  }

  /// 加载效果追踪数据
  /// TODO: V2 — 调用 _service.getPerformance()
  Future<void> loadPerformance({String? campaignId}) async {
    // TODO: V2 实现
  }
}

// ============================================================
// Provider 定义
// ============================================================

/// Influencer 模块主 Provider
final influencerProvider =
    AsyncNotifierProvider<InfluencerNotifier, InfluencerState>(
  InfluencerNotifier.new,
);

/// 按状态过滤的 Campaign Provider（派生 Provider）
/// 用法: ref.watch(campaignsByStatusProvider(CampaignStatus.active))
final campaignsByStatusProvider = Provider.family<
    List<InfluencerCampaign>, CampaignStatus>(
  (ref, status) {
    final asyncState = ref.watch(influencerProvider);
    return asyncState.whenOrNull(
          data: (state) => state.campaignsByStatus(status),
        ) ??
        [];
  },
);

/// 待审批申请数量 Provider（用于 Dashboard 红点展示）
final pendingApplicationsCountProvider = Provider<int>((ref) {
  final asyncState = ref.watch(influencerProvider);
  return asyncState.whenOrNull(
        data: (state) => state.pendingApplications.length,
      ) ??
      0;
});

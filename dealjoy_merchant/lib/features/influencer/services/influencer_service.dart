// ============================================================
// Influencer 合作 — 业务逻辑服务层
// 模块: 12. Influencer 合作
// 优先级: P2/V2 — 方法存根，V2 接入真实 API
// ============================================================

import '../models/influencer_models.dart';

/// Influencer 合作服务
/// 封装所有与 Supabase / Edge Function 的通信
/// 当前全部为 TODO 存根，V2 实现完整业务逻辑
class InfluencerService {
  const InfluencerService();

  // ============================================================
  // Campaign CRUD
  // ============================================================

  /// 获取商家的 Campaign 列表
  /// [merchantId] 商家 ID
  /// [status] 可选筛选状态（null 表示全部）
  /// TODO: V2 — 调用 merchant-influencer Edge Function GET /campaigns
  Future<List<InfluencerCampaign>> getCampaigns(
    String merchantId, {
    CampaignStatus? status,
  }) async {
    // TODO: V2 实现以下逻辑:
    // final response = await supabase.functions.invoke(
    //   'merchant-influencer',
    //   body: {'action': 'campaigns'},
    //   headers: {'method': 'GET'},
    // );
    // return (response.data['data'] as List)
    //     .map((e) => InfluencerCampaign.fromJson(e))
    //     .toList();
    return [];
  }

  /// 创建新 Campaign
  /// [campaign] 待创建的 Campaign 数据
  /// TODO: V2 — 调用 merchant-influencer Edge Function POST /campaigns
  Future<InfluencerCampaign> createCampaign(
    InfluencerCampaign campaign,
  ) async {
    // TODO: V2 实现以下逻辑:
    // final response = await supabase.functions.invoke(
    //   'merchant-influencer',
    //   body: campaign.toJson(),
    // );
    // return InfluencerCampaign.fromJson(response.data['data']);
    throw UnimplementedError('createCampaign: TODO V2');
  }

  /// 更新 Campaign
  /// [campaign] 包含完整字段的 Campaign 数据
  /// TODO: V2 — 调用 merchant-influencer Edge Function PATCH /campaigns/:id
  Future<InfluencerCampaign> updateCampaign(
    InfluencerCampaign campaign,
  ) async {
    // TODO: V2 实现
    throw UnimplementedError('updateCampaign: TODO V2');
  }

  /// 删除草稿 Campaign（只允许删除 draft 状态）
  /// [id] Campaign ID
  /// TODO: V2 — 调用 merchant-influencer Edge Function DELETE /campaigns/:id
  Future<void> deleteCampaign(String id) async {
    // TODO: V2 实现
    throw UnimplementedError('deleteCampaign: TODO V2');
  }

  // ============================================================
  // Applications 审批
  // ============================================================

  /// 获取指定 Campaign 下的所有申请列表
  /// [campaignId] Campaign ID
  /// TODO: V2 — 调用 merchant-influencer Edge Function
  ///             GET /campaigns/:id/applications
  Future<List<InfluencerApplication>> getApplications(
    String campaignId,
  ) async {
    // TODO: V2 实现
    return [];
  }

  /// 审批通过申请，自动生成推广链接
  /// [applicationId] 申请 ID
  /// TODO: V2 — 调用 merchant-influencer Edge Function
  ///             PATCH /applications/:id/approve
  Future<InfluencerApplication> approveApplication(
    String applicationId,
  ) async {
    // TODO: V2 实现
    throw UnimplementedError('approveApplication: TODO V2');
  }

  /// 拒绝申请
  /// [applicationId] 申请 ID
  /// [reason] 拒绝原因（可选）
  /// TODO: V2 — 调用 merchant-influencer Edge Function
  ///             PATCH /applications/:id/reject
  Future<InfluencerApplication> rejectApplication(
    String applicationId, {
    String? reason,
  }) async {
    // TODO: V2 实现
    throw UnimplementedError('rejectApplication: TODO V2');
  }

  // ============================================================
  // Performance 效果追踪
  // ============================================================

  /// 获取 Campaign 效果数据
  /// [campaignId] Campaign ID（可选，null 表示全部 Campaign）
  /// TODO: V2 — 调用 merchant-influencer Edge Function GET /performance
  Future<List<InfluencerPerformance>> getPerformance({
    String? campaignId,
  }) async {
    // TODO: V2 实现
    return [];
  }
}

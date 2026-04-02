// Campaign 报告聚合模型（由每日统计汇总，供报告页展示）

import 'ad_daily_stat.dart';

/// 单个 Campaign 在选定时间段内的报告汇总
class AdCampaignReport {
  final String campaignId;
  final List<AdDailyStat> dailyStats;
  final double totalSpend;
  final int totalClicks;
  final int totalImpressions;

  const AdCampaignReport({
    required this.campaignId,
    required this.dailyStats,
    required this.totalSpend,
    required this.totalClicks,
    required this.totalImpressions,
  });

  /// 无商家或无数据时的空报告
  factory AdCampaignReport.empty(String campaignId) {
    return AdCampaignReport(
      campaignId: campaignId,
      dailyStats: const [],
      totalSpend: 0,
      totalClicks: 0,
      totalImpressions: 0,
    );
  }

  /// 由 Edge Function 返回的每日行列表构造并排序
  factory AdCampaignReport.fromDailyStats(
    String campaignId,
    List<AdDailyStat> stats,
  ) {
    var spend = 0.0;
    var clicks = 0;
    var impressions = 0;
    for (final s in stats) {
      spend += s.spend;
      clicks += s.clicks;
      impressions += s.impressions;
    }
    final sorted = [...stats]..sort((a, b) => a.date.compareTo(b.date));
    return AdCampaignReport(
      campaignId: campaignId,
      dailyStats: sorted,
      totalSpend: spend,
      totalClicks: clicks,
      totalImpressions: impressions,
    );
  }
}

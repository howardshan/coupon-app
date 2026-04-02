// 广告每日统计数据模型
// 对应后端 ad_daily_stats 表，记录广告计划每天的曝光/点击/转化/消费数据

/// 广告计划单日统计
class AdDailyStat {
  final String id;
  final String campaignId;
  final DateTime date;
  final int impressions;    // 曝光次数
  final int clicks;         // 点击次数
  final int conversions;    // 转化次数（成单）
  final double spend;       // 当日消费（美元）

  const AdDailyStat({
    required this.id,
    required this.campaignId,
    required this.date,
    required this.impressions,
    required this.clicks,
    required this.conversions,
    required this.spend,
  });

  /// 点击率（百分比），曝光为 0 时返回 0
  double get ctr => impressions > 0 ? clicks / impressions * 100 : 0.0;

  /// 转化率（百分比），点击为 0 时返回 0
  double get cvr => clicks > 0 ? conversions / clicks * 100 : 0.0;

  /// 平均点击成本（美元），点击为 0 时返回 0
  double get cpc => clicks > 0 ? spend / clicks : 0.0;

  /// 从 Edge Function 返回的 JSON 构造，所有字段 null-safe
  factory AdDailyStat.fromJson(Map<String, dynamic> json) {
    return AdDailyStat(
      id:          json['id'] as String? ?? '',
      campaignId:  json['campaign_id'] as String? ?? '',
      date:        json['date'] != null
          ? DateTime.parse(json['date'] as String)
          : DateTime.now(),
      impressions: (json['impressions'] as num?)?.toInt() ?? 0,
      clicks:      (json['clicks'] as num?)?.toInt() ?? 0,
      conversions: (json['conversions'] as num?)?.toInt() ?? 0,
      spend:       (json['spend'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

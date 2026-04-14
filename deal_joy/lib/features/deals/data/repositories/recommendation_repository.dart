import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/deal_model.dart';

/// 推荐系统 Repository
/// - fetchRecommendations: 调用 Edge Function get-recommendations 获取个性化推荐
/// - trackEvent: 直接写入 user_events 表记录用户行为
class RecommendationRepository {
  final SupabaseClient _client;

  RecommendationRepository(this._client);

  /// 获取个性化推荐 Deal 列表
  /// [lat] / [lng]: 用户 GPS 坐标（可为 null，服务端会用 IP 定位或默认城市）
  /// [limit]: 返回数量上限，默认 20
  Future<List<DealModel>> fetchRecommendations({
    double? lat,
    double? lng,
    int limit = 20,
  }) async {
    try {
      final body = <String, dynamic>{'limit': limit};
      if (lat != null) body['lat'] = lat;
      if (lng != null) body['lng'] = lng;

      final response = await _client.functions.invoke(
        'get-recommendations',
        body: body,
      );

      // Edge Function 返回 { deals: [...] } 结构
      final data = response.data;
      if (data == null) return [];

      // 支持直接返回列表，或包装在 { deals: [...] } 内
      final List<dynamic> rawList;
      if (data is List) {
        rawList = data;
      } else if (data is Map && data['deals'] is List) {
        rawList = data['deals'] as List<dynamic>;
      } else {
        debugPrint('[RecommendationRepository] 未知返回格式: ${data.runtimeType}');
        return [];
      }

      return rawList
          .map((e) => DealModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      // 推荐失败不阻断主流程，静默返回空列表
      debugPrint('[RecommendationRepository] fetchRecommendations 失败: $e');
      return [];
    }
  }

  /// 上报用户行为事件到 user_events 表
  /// [eventType]: 事件类型，可选值:
  ///   'view_deal' | 'view_merchant' | 'search' | 'purchase' |
  ///   'redeem' | 'review' | 'refund'
  /// [dealId]: 相关 deal ID（可选）
  /// [merchantId]: 相关商家 ID（可选）
  /// [metadata]: 附加数据（可选），如搜索关键词、金额等
  Future<void> trackEvent({
    required String eventType,
    String? dealId,
    String? merchantId,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final userId = _client.auth.currentUser?.id;
      // 未登录用户不上报
      if (userId == null) return;

      // 不写时间字段：表列为 occurred_at，由 DB DEFAULT now() 填充（勿用不存在的 created_at）
      final payload = <String, dynamic>{
        'user_id': userId,
        'event_type': eventType,
      };
      if (dealId != null) payload['deal_id'] = dealId;
      if (merchantId != null) payload['merchant_id'] = merchantId;
      if (metadata != null) payload['metadata'] = metadata;

      await _client.from('user_events').insert(payload);
    } catch (e) {
      // 埋点失败不阻断主流程，仅打印日志
      debugPrint('[RecommendationRepository] trackEvent 失败: $e');
    }
  }
}

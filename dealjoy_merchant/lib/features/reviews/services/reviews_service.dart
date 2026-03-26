// 评价管理业务服务层
// 封装所有与 Edge Function merchant-reviews 的通信逻辑
// 对应路由:
//   GET  /merchant-reviews          — 分页评价列表（支持 rating 筛选）
//   POST /merchant-reviews/:id/reply — 提交商家回复（限1次）
//   GET  /merchant-reviews/stats    — 评价统计数据

import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/merchant_review.dart';
import '../../store/services/store_service.dart';

// =============================================================
// ReviewsException — 评价模块自定义异常
// =============================================================
class ReviewsException implements Exception {
  final String message;
  final String code;

  const ReviewsException({required this.message, required this.code});

  @override
  String toString() => 'ReviewsException($code): $message';
}

// =============================================================
// ReviewsService — 评价 API 调用封装
// =============================================================
class ReviewsService {
  ReviewsService(this._supabase);

  final SupabaseClient _supabase;

  // Edge Function 名称
  static const String _functionName = 'merchant-reviews';

  // =============================================================
  // fetchReviews — 获取分页评价列表
  // [merchantId] — 仅用于构造参数（auth 自动鉴权）
  // [ratingFilter] — 可选，1-5 筛选对应星级
  // [page]         — 页码，从 1 开始
  // [perPage]      — 每页条数（默认 20）
  // 抛出 [ReviewsException] 如请求失败
  // =============================================================
  Future<PagedReviews> fetchReviews(
    String merchantId, {
    int? ratingFilter,
    int page = 1,
    int perPage = 20,
  }) async {
    try {
      // 构建查询字符串
      final params = <String, String>{
        'page':     page.toString(),
        'per_page': perPage.toString(),
      };
      if (ratingFilter != null && ratingFilter >= 1 && ratingFilter <= 5) {
        params['rating'] = ratingFilter.toString();
      }

      final queryString = _buildQueryString(params);
      // Edge Function 路径：函数名本身就是路由前缀
      final path = queryString.isEmpty
          ? _functionName
          : '$_functionName?$queryString';

      final response = await _supabase.functions.invoke(
        path,
        method: HttpMethod.get,
        headers: StoreService.merchantIdHeaders,
      );

      final data = _parseResponse(response);
      _checkError(data);

      return PagedReviews.fromJson(data);
    } on ReviewsException {
      rethrow;
    } on FunctionException catch (e) {
      final body = _tryParseBody(e.details);
      throw ReviewsException(
        code:    body?['error'] as String? ?? 'network_error',
        message: body?['message'] as String? ?? 'Failed to fetch reviews.',
      );
    } catch (e) {
      if (e is ReviewsException) rethrow;
      throw const ReviewsException(
        code:    'network_error',
        message: 'Network error. Please check your connection.',
      );
    }
  }

  // =============================================================
  // replyToReview — 提交商家回复
  // [reviewId] — 评价 UUID
  // [reply]    — 回复内容（最多 300 字符）
  // 抛出 [ReviewsException]:
  //   'already_replied'   — 已回复过该条评价
  //   'review_not_found'  — 评价不存在或不属于该商家
  //   'validation_error'  — 内容校验失败
  // =============================================================
  Future<void> replyToReview(String reviewId, String reply) async {
    try {
      // 客户端预校验
      if (reply.trim().isEmpty) {
        throw const ReviewsException(
          code:    'validation_error',
          message: 'Reply content cannot be empty.',
        );
      }
      if (reply.length > 300) {
        throw const ReviewsException(
          code:    'validation_error',
          message: 'Reply must be 300 characters or less.',
        );
      }

      // 路径：函数名/id/reply
      final path = '$_functionName/$reviewId/reply';

      final response = await _supabase.functions.invoke(
        path,
        method:  HttpMethod.post,
        headers: StoreService.merchantIdHeaders,
        body:    {'reply': reply.trim()},
      );

      final data = _parseResponse(response);
      _checkError(data);
    } on ReviewsException {
      rethrow;
    } on FunctionException catch (e) {
      final body = _tryParseBody(e.details);
      final code = body?['error'] as String? ?? 'network_error';
      // 将后端错误码映射为可读错误
      String message;
      switch (code) {
        case 'already_replied':
          message = 'You have already replied to this review.';
          break;
        case 'review_not_found':
          message = 'Review not found.';
          break;
        case 'validation_error':
          message = body?['message'] as String? ?? 'Invalid reply content.';
          break;
        default:
          message = 'Failed to submit reply. Please try again.';
      }
      throw ReviewsException(code: code, message: message);
    } catch (e) {
      if (e is ReviewsException) rethrow;
      throw const ReviewsException(
        code:    'network_error',
        message: 'Network error. Please check your connection.',
      );
    }
  }

  // =============================================================
  // fetchReviewStats — 获取评价统计数据
  // 返回 [ReviewStats]：平均分 + 分布 + 关键词
  // =============================================================
  Future<ReviewStats> fetchReviewStats(String merchantId) async {
    try {
      final path = '$_functionName/stats';

      final response = await _supabase.functions.invoke(
        path,
        method: HttpMethod.get,
        headers: StoreService.merchantIdHeaders,
      );

      final data = _parseResponse(response);
      _checkError(data);

      return ReviewStats.fromJson(data);
    } on ReviewsException {
      rethrow;
    } on FunctionException catch (e) {
      final body = _tryParseBody(e.details);
      final code = body?['error'] as String? ?? 'network_error';
      // stats 加载失败时返回空统计（非阻断性）
      if (code == 'unauthorized' || code == 'merchant_not_found') {
        throw ReviewsException(
          code:    code,
          message: body?['message'] as String? ?? 'Unauthorized',
        );
      }
      // 其他情况降级为空统计
      return ReviewStats.empty();
    } catch (e) {
      if (e is ReviewsException) rethrow;
      // 统计加载失败不阻断主列表
      return ReviewStats.empty();
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

  /// 检查响应体中是否包含 error 字段，若有则抛出 ReviewsException
  void _checkError(Map<String, dynamic> data) {
    if (data['error'] != null) {
      throw ReviewsException(
        code:    data['error'] as String,
        message: data['message'] as String? ?? 'Request failed',
      );
    }
  }

  /// 尝试解析错误体为 Map，失败返回 null
  Map<String, dynamic>? _tryParseBody(dynamic details) {
    try {
      if (details is Map<String, dynamic>) return details;
      if (details is String) {
        return jsonDecode(details) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
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

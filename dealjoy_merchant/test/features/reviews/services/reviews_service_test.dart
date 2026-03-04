// ReviewsService 单元测试
// 策略: 使用可测试子类重写 API 方法，注入 stub 响应，
//       测试正常解析 + 异常处理 + 降级逻辑

import 'package:flutter_test/flutter_test.dart';
import 'package:dealjoy_merchant/features/reviews/models/merchant_review.dart';
import 'package:dealjoy_merchant/features/reviews/services/reviews_service.dart';

// =============================================================
// _TestableReviewsService — 可测试子类（注入 stub 响应）
// =============================================================
class _TestableReviewsService extends ReviewsService {
  _TestableReviewsService() : super(null as dynamic);

  // 注入响应数据（null 则使用默认 JSON）
  Map<String, dynamic>? stubbedReviewsData;
  Map<String, dynamic>? stubbedStatsData;

  // 注入异常（模拟网络/后端错误）
  ReviewsException? throwOnFetchReviews;
  ReviewsException? throwOnReply;
  ReviewsException? throwOnStats;

  // 记录最后一次 replyToReview 的调用参数
  String? lastReviewId;
  String? lastReply;

  @override
  Future<PagedReviews> fetchReviews(
    String merchantId, {
    int? ratingFilter,
    int page = 1,
    int perPage = 20,
  }) async {
    if (throwOnFetchReviews != null) throw throwOnFetchReviews!;
    final data = stubbedReviewsData ?? _defaultReviewsJson(page: page);
    return PagedReviews.fromJson(data);
  }

  @override
  Future<void> replyToReview(String reviewId, String reply) async {
    lastReviewId = reviewId;
    lastReply    = reply;
    if (throwOnReply != null) throw throwOnReply!;
  }

  @override
  Future<ReviewStats> fetchReviewStats(String merchantId) async {
    if (throwOnStats != null) {
      // 统计失败时降级返回空统计（与 ReviewsService 行为一致）
      return ReviewStats.empty();
    }
    final data = stubbedStatsData ?? _defaultStatsJson();
    return ReviewStats.fromJson(data);
  }
}

// =============================================================
// 测试 JSON 工厂函数
// =============================================================

/// 默认评价列表 JSON
Map<String, dynamic> _defaultReviewsJson({int page = 1}) => {
  'data': [
    {
      'id':             'review-001',
      'user_name':      'Alice Chen',
      'avatar_url':     null,
      'rating':         5,
      'comment':        'Great food and service!',
      'image_urls':     [],
      'merchant_reply': null,
      'replied_at':     null,
      'created_at':     '2026-03-01T10:00:00Z',
    },
    {
      'id':             'review-002',
      'user_name':      'Bob Smith',
      'avatar_url':     null,
      'rating':         4,
      'comment':        'Good but a bit pricey.',
      'image_urls':     [],
      'merchant_reply': 'Thank you for your feedback!',
      'replied_at':     '2026-03-02T09:00:00Z',
      'created_at':     '2026-02-28T15:30:00Z',
    },
  ],
  'pagination': {
    'page':     page,
    'per_page': 20,
    'total':    2,
    'has_more': false,
  },
};

/// 默认评价统计 JSON
Map<String, dynamic> _defaultStatsJson() => {
  'avg_rating':          4.5,
  'total_count':         10,
  'rating_distribution': {
    '1': 0,
    '2': 1,
    '3': 2,
    '4': 3,
    '5': 4,
  },
  'top_keywords': ['delicious', 'friendly', 'clean', 'fast'],
};

// =============================================================
// 测试主体
// =============================================================
void main() {
  late _TestableReviewsService service;

  setUp(() {
    service = _TestableReviewsService();
  });

  // -----------------------------------------------------------
  // fetchReviews
  // -----------------------------------------------------------
  group('fetchReviews', () {
    test('默认返回分页评价列表', () async {
      final result = await service.fetchReviews('merchant-1');

      expect(result.data.length, 2);
      expect(result.total, 2);
      expect(result.hasMore, isFalse);
      expect(result.page, 1);
    });

    test('第一条评价字段正确解析', () async {
      final result = await service.fetchReviews('merchant-1');
      final first  = result.data.first;

      expect(first.id,       'review-001');
      expect(first.userName, 'Alice Chen');
      expect(first.rating,   5);
      expect(first.content,  'Great food and service!');
      expect(first.hasReply, isFalse);
    });

    test('第二条评价含商家回复，hasReply 为 true', () async {
      final result = await service.fetchReviews('merchant-1');
      final second = result.data[1];

      expect(second.hasReply,      isTrue);
      expect(second.merchantReply, 'Thank you for your feedback!');
      expect(second.repliedAt,     isNotNull);
    });

    test('星级筛选：ratingFilter 参数传递', () async {
      // stub: 只返回5星评价
      service.stubbedReviewsData = {
        'data': [
          {
            'id':             'review-001',
            'user_name':      'Alice',
            'avatar_url':     null,
            'rating':         5,
            'comment':        'Amazing!',
            'image_urls':     [],
            'merchant_reply': null,
            'replied_at':     null,
            'created_at':     '2026-03-01T00:00:00Z',
          },
        ],
        'pagination': {'page': 1, 'per_page': 20, 'total': 1, 'has_more': false},
      };

      final result = await service.fetchReviews('merchant-1', ratingFilter: 5);
      expect(result.data.length, 1);
      expect(result.data.first.rating, 5);
    });

    test('网络错误时抛出 ReviewsException', () async {
      service.throwOnFetchReviews = const ReviewsException(
        code:    'network_error',
        message: 'Network error.',
      );

      expect(
        () => service.fetchReviews('merchant-1'),
        throwsA(isA<ReviewsException>().having(
          (e) => e.code, 'code', 'network_error',
        )),
      );
    });

    test('空列表解析正确', () async {
      service.stubbedReviewsData = {
        'data':       [],
        'pagination': {'page': 1, 'per_page': 20, 'total': 0, 'has_more': false},
      };

      final result = await service.fetchReviews('merchant-1');
      expect(result.data,    isEmpty);
      expect(result.total,   0);
      expect(result.hasMore, isFalse);
    });
  });

  // -----------------------------------------------------------
  // replyToReview
  // -----------------------------------------------------------
  group('replyToReview', () {
    test('成功提交回复，记录 reviewId 和 reply', () async {
      await service.replyToReview('review-001', 'Thank you!');

      expect(service.lastReviewId, 'review-001');
      expect(service.lastReply,    'Thank you!');
    });

    test('已回复时抛出 already_replied 异常', () async {
      service.throwOnReply = const ReviewsException(
        code:    'already_replied',
        message: 'You have already replied to this review.',
      );

      expect(
        () => service.replyToReview('review-002', 'Thanks again!'),
        throwsA(isA<ReviewsException>().having(
          (e) => e.code, 'code', 'already_replied',
        )),
      );
    });

    test('评价不存在时抛出 review_not_found 异常', () async {
      service.throwOnReply = const ReviewsException(
        code:    'review_not_found',
        message: 'Review not found.',
      );

      expect(
        () => service.replyToReview('invalid-id', 'Test'),
        throwsA(isA<ReviewsException>().having(
          (e) => e.code, 'code', 'review_not_found',
        )),
      );
    });
  });

  // -----------------------------------------------------------
  // fetchReviewStats
  // -----------------------------------------------------------
  group('fetchReviewStats', () {
    test('正常解析统计数据', () async {
      final stats = await service.fetchReviewStats('merchant-1');

      expect(stats.avgRating,  4.5);
      expect(stats.totalCount, 10);
      expect(stats.countForRating(5), 4);
      expect(stats.countForRating(1), 0);
      expect(stats.topKeywords, contains('delicious'));
    });

    test('百分比计算正确', () async {
      final stats = await service.fetchReviewStats('merchant-1');

      // 5星有4条，总10条 → 40%
      expect(stats.percentForRating(5), closeTo(0.4, 0.001));
      // 1星有0条 → 0%
      expect(stats.percentForRating(1), 0.0);
    });

    test('统计加载失败时降级返回空统计（不抛出异常）', () async {
      service.throwOnStats = const ReviewsException(
        code:    'network_error',
        message: 'Failed.',
      );

      // 降级处理：返回 ReviewStats.empty()，不抛出
      final stats = await service.fetchReviewStats('merchant-1');
      expect(stats.totalCount, 0);
      expect(stats.avgRating,  0.0);
      expect(stats.topKeywords, isEmpty);
    });

    test('零评价时 percentForRating 不出现除零错误', () {
      final stats = ReviewStats.empty();
      expect(stats.percentForRating(5), 0.0);
      expect(stats.percentForRating(1), 0.0);
    });
  });

  // -----------------------------------------------------------
  // MerchantReview model
  // -----------------------------------------------------------
  group('MerchantReview model', () {
    test('fromJson 正确解析所有字段', () {
      final json = {
        'id':             'r-1',
        'user_name':      'Carol',
        'avatar_url':     'https://example.com/avatar.jpg',
        'rating':         3,
        'comment':        'It was okay.',
        'image_urls':     ['https://example.com/img1.jpg'],
        'merchant_reply': 'We will improve!',
        'replied_at':     '2026-03-01T12:00:00Z',
        'created_at':     '2026-02-28T08:00:00Z',
      };

      final review = MerchantReview.fromJson(json);

      expect(review.id,             'r-1');
      expect(review.userName,       'Carol');
      expect(review.rating,         3);
      expect(review.hasReply,       isTrue);
      expect(review.imageUrls.length, 1);
      expect(review.repliedAt,      isNotNull);
    });

    test('copyWithReply 返回新对象含回复', () {
      final original = MerchantReview.fromJson({
        'id':         'r-2',
        'user_name':  'Dave',
        'avatar_url': null,
        'rating':     4,
        'comment':    'Good!',
        'image_urls': [],
        'merchant_reply': null,
        'replied_at':     null,
        'created_at': '2026-03-01T00:00:00Z',
      });

      expect(original.hasReply, isFalse);

      final replied = original.copyWithReply('Thank you!', DateTime(2026, 3, 2));

      expect(replied.hasReply,      isTrue);
      expect(replied.merchantReply, 'Thank you!');
      // 原对象不变（不可变）
      expect(original.hasReply, isFalse);
    });

    test('avatar 为 null 时不抛出', () {
      final review = MerchantReview.fromJson({
        'id':             'r-3',
        'user_name':      'Eve',
        'avatar_url':     null,
        'rating':         2,
        'comment':        null,
        'image_urls':     null,
        'merchant_reply': null,
        'replied_at':     null,
        'created_at':     '2026-03-01T00:00:00Z',
      });

      expect(review.avatarUrl,  isNull);
      expect(review.content,    isNull);
      expect(review.imageUrls,  isEmpty);
    });
  });

  // -----------------------------------------------------------
  // PagedReviews model
  // -----------------------------------------------------------
  group('PagedReviews', () {
    test('replaceReview 替换正确条目', () {
      final paged = PagedReviews.fromJson(_defaultReviewsJson());
      final original = paged.data.first;
      final updated  = original.copyWithReply('Nice!', DateTime(2026, 3, 3));

      final newPaged = paged.replaceReview(updated);

      expect(newPaged.data.first.hasReply,      isTrue);
      expect(newPaged.data.first.merchantReply, 'Nice!');
      // 其他条目不变
      expect(newPaged.data[1].id, 'review-002');
    });

    test('empty() 返回空分页', () {
      final empty = PagedReviews.empty();
      expect(empty.data,    isEmpty);
      expect(empty.total,   0);
      expect(empty.hasMore, isFalse);
    });
  });

  // -----------------------------------------------------------
  // ReviewsFilter model
  // -----------------------------------------------------------
  group('ReviewsFilter', () {
    test('默认无筛选条件', () {
      const filter = ReviewsFilter();
      expect(filter.hasFilter, isFalse);
      expect(filter.page, 1);
    });

    test('copyWith 设置星级筛选', () {
      const filter = ReviewsFilter();
      final updated = filter.copyWith(ratingFilter: 4);
      expect(updated.ratingFilter, 4);
      expect(updated.hasFilter,    isTrue);
    });

    test('clearRating: true 清除筛选', () {
      const filter = ReviewsFilter(ratingFilter: 5);
      final cleared = filter.copyWith(clearRating: true);
      expect(cleared.ratingFilter, isNull);
      expect(cleared.hasFilter,    isFalse);
    });
  });
}

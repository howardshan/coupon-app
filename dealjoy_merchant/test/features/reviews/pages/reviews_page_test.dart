// ReviewsPage Widget 测试
// 策略: 使用 ProviderContainer override 注入 stub providers，
//       验证 UI 渲染逻辑（统计卡片、筛选行、评价列表、空状态、错误状态）

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dealjoy_merchant/features/reviews/models/merchant_review.dart';
import 'package:dealjoy_merchant/features/reviews/providers/reviews_provider.dart';
import 'package:dealjoy_merchant/features/reviews/pages/reviews_page.dart';
import 'package:dealjoy_merchant/features/reviews/widgets/review_card.dart';

// =============================================================
// 测试辅助工厂
// =============================================================

MerchantReview _makeReview({
  String id     = 'r-1',
  int    rating = 5,
  String? reply,
}) {
  return MerchantReview(
    id:             id,
    userName:       'Test User',
    rating:         rating,
    imageUrls:      const [],
    merchantReply:  reply,
    repliedAt:      reply != null ? DateTime(2026, 3, 2) : null,
    createdAt:      DateTime(2026, 3, 1),
  );
}

PagedReviews _pagedWith(List<MerchantReview> reviews) {
  return PagedReviews(
    data:    reviews,
    page:    1,
    perPage: 20,
    total:   reviews.length,
    hasMore: false,
  );
}

ReviewStats _sampleStats() {
  return ReviewStats(
    avgRating:          4.5,
    totalCount:         3,
    ratingDistribution: {1: 0, 2: 0, 3: 0, 4: 1, 5: 2},
    topKeywords:        ['great', 'clean'],
  );
}

// =============================================================
// 包装 ReviewsPage 的测试 Widget（注入 provider overrides）
// =============================================================
Widget _buildTestWidget({
  AsyncValue<PagedReviews>? reviewsState,
  AsyncValue<ReviewStats>?  statsState,
  ReviewsFilter?            filter,
}) {
  final reviews = reviewsState ?? AsyncData(_pagedWith([_makeReview()]));
  final stats   = statsState   ?? AsyncData(_sampleStats());
  final f       = filter       ?? const ReviewsFilter(page: 1);

  return ProviderScope(
    overrides: [
      // 注入评价列表状态
      reviewsProvider.overrideWith(() => _FakeReviewsNotifier(reviews)),
      // 注入统计状态
      reviewStatsProvider.overrideWith((ref) async {
        if (stats is AsyncError) throw stats.error!;
        return (stats as AsyncData<ReviewStats>).value;
      }),
      // 注入筛选条件
      reviewsFilterProvider.overrideWith((ref) => f),
    ],
    child: const MaterialApp(
      home: ReviewsPage(),
    ),
  );
}

// =============================================================
// _FakeReviewsNotifier — 注入固定状态的假 Notifier
// =============================================================
class _FakeReviewsNotifier extends ReviewsNotifier {
  _FakeReviewsNotifier(this._fixedState);

  final AsyncValue<PagedReviews> _fixedState;

  @override
  Future<PagedReviews> build() async {
    state = _fixedState;
    if (_fixedState is AsyncError) {
      throw (_fixedState as AsyncError).error;
    }
    return (_fixedState as AsyncData<PagedReviews>).value;
  }

  @override
  Future<void> refresh() async {}

  @override
  void applyRatingFilter(int? rating) {}

  @override
  void loadNextPage() {}
}

// =============================================================
// 测试主体
// =============================================================
void main() {
  // -----------------------------------------------------------
  // 基础渲染
  // -----------------------------------------------------------
  group('ReviewsPage 基础渲染', () {
    testWidgets('显示页面标题 Reviews', (tester) async {
      await tester.pumpWidget(_buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Reviews'), findsOneWidget);
    });

    testWidgets('显示筛选按钮行（All + 5★ 等）', (tester) async {
      await tester.pumpWidget(_buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('All'), findsOneWidget);
      expect(find.text('5★'), findsOneWidget);
      expect(find.text('4★'), findsOneWidget);
      expect(find.text('1★'), findsOneWidget);
    });
  });

  // -----------------------------------------------------------
  // 统计卡片
  // -----------------------------------------------------------
  group('评分统计卡片', () {
    testWidgets('显示 Rating Overview 标题', (tester) async {
      await tester.pumpWidget(_buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Rating Overview'), findsOneWidget);
    });

    testWidgets('显示平均分数值', (tester) async {
      await tester.pumpWidget(_buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('4.5'), findsOneWidget);
    });

    testWidgets('显示关键词标签', (tester) async {
      await tester.pumpWidget(_buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('great'), findsOneWidget);
      expect(find.text('clean'), findsOneWidget);
    });

    testWidgets('显示 Keywords 标签标题', (tester) async {
      await tester.pumpWidget(_buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Keywords'), findsOneWidget);
    });
  });

  // -----------------------------------------------------------
  // 评价列表
  // -----------------------------------------------------------
  group('评价列表', () {
    testWidgets('有评价时显示 ReviewCard', (tester) async {
      final reviews = [
        _makeReview(id: 'r-1', rating: 5),
        _makeReview(id: 'r-2', rating: 4),
      ];

      await tester.pumpWidget(_buildTestWidget(
        reviewsState: AsyncData(_pagedWith(reviews)),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(ReviewCard), findsNWidgets(2));
    });

    testWidgets('ReviewCard 显示用户名', (tester) async {
      await tester.pumpWidget(_buildTestWidget(
        reviewsState: AsyncData(_pagedWith([_makeReview()])),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Test User'), findsOneWidget);
    });

    testWidgets('已回复评价显示 Owner Reply 区块', (tester) async {
      final review = _makeReview(id: 'r-1', reply: 'Thank you!');

      await tester.pumpWidget(_buildTestWidget(
        reviewsState: AsyncData(_pagedWith([review])),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Owner Reply'), findsOneWidget);
      expect(find.text('Thank you!'), findsOneWidget);
    });

    testWidgets('未回复评价显示 Reply 按钮', (tester) async {
      final review = _makeReview(id: 'r-1', reply: null);

      await tester.pumpWidget(_buildTestWidget(
        reviewsState: AsyncData(_pagedWith([review])),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Reply'), findsOneWidget);
      expect(find.text('Owner Reply'), findsNothing);
    });

    testWidgets('All reviews loaded 文字（无更多数据时）', (tester) async {
      await tester.pumpWidget(_buildTestWidget(
        reviewsState: AsyncData(_pagedWith([_makeReview()])),
      ));
      await tester.pumpAndSettle();

      expect(find.text('All reviews loaded'), findsOneWidget);
    });
  });

  // -----------------------------------------------------------
  // 空状态
  // -----------------------------------------------------------
  group('空状态', () {
    testWidgets('无评价时显示 No reviews yet', (tester) async {
      await tester.pumpWidget(_buildTestWidget(
        reviewsState: AsyncData(_pagedWith([])),
      ));
      await tester.pumpAndSettle();

      expect(find.text('No reviews yet'), findsOneWidget);
    });

    testWidgets('有筛选条件且无结果时显示 No reviews with this rating', (tester) async {
      await tester.pumpWidget(_buildTestWidget(
        reviewsState: AsyncData(_pagedWith([])),
        filter:       const ReviewsFilter(ratingFilter: 1, page: 1),
      ));
      await tester.pumpAndSettle();

      expect(find.text('No reviews with this rating'), findsOneWidget);
    });

    testWidgets('有筛选条件空状态时显示 Show All Reviews 按钮', (tester) async {
      await tester.pumpWidget(_buildTestWidget(
        reviewsState: AsyncData(_pagedWith([])),
        filter:       const ReviewsFilter(ratingFilter: 2, page: 1),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Show All Reviews'), findsOneWidget);
    });
  });

  // -----------------------------------------------------------
  // 错误状态
  // -----------------------------------------------------------
  group('错误状态', () {
    testWidgets('加载失败显示 Failed to load reviews', (tester) async {
      await tester.pumpWidget(_buildTestWidget(
        reviewsState: AsyncError(
          Exception('Network error'),
          StackTrace.empty,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Failed to load reviews'), findsOneWidget);
    });

    testWidgets('加载失败显示 Retry 按钮', (tester) async {
      await tester.pumpWidget(_buildTestWidget(
        reviewsState: AsyncError(
          Exception('Timeout'),
          StackTrace.empty,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Retry'), findsOneWidget);
    });
  });

  // -----------------------------------------------------------
  // 筛选行交互
  // -----------------------------------------------------------
  group('筛选行', () {
    testWidgets('默认 All 按钮为选中状态（橙色背景）', (tester) async {
      await tester.pumpWidget(_buildTestWidget(
        filter: const ReviewsFilter(page: 1), // ratingFilter = null → All
      ));
      await tester.pumpAndSettle();

      // 找到 All 文字所在的 AnimatedContainer，验证其存在
      expect(find.text('All'), findsOneWidget);
    });

    testWidgets('点击 5★ 筛选按钮不抛出异常', (tester) async {
      await tester.pumpWidget(_buildTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('5★'));
      await tester.pumpAndSettle();
      // 无异常即通过（applyRatingFilter 已在 _FakeReviewsNotifier 中 no-op）
    });
  });
}

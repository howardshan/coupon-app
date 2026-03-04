// 评价管理状态管理
// 使用 Riverpod AsyncNotifier 模式
// Providers:
//   reviewsServiceProvider     — ReviewsService 单例
//   _merchantIdProvider        — 当前登录商家 ID（内部用）
//   reviewsFilterProvider      — 评价列表筛选条件（StateProvider）
//   ReviewsNotifier            — 评价列表异步 Notifier
//   reviewsProvider            — 评价列表 Provider
//   reviewStatsProvider        — 评价统计 FutureProvider
//   replyStateProvider         — 回复提交状态（StateProvider，防重复提交）

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/merchant_review.dart';
import '../services/reviews_service.dart';

// =============================================================
// 基础依赖 Provider
// =============================================================

/// 全局 SupabaseClient Provider
final _supabaseProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

/// ReviewsService Provider（单例）
final reviewsServiceProvider = Provider<ReviewsService>((ref) {
  final client = ref.watch(_supabaseProvider);
  return ReviewsService(client);
});

// =============================================================
// _merchantIdProvider — 当前登录商家 ID
// =============================================================
/// 查询当前登录用户对应的 merchant_id
/// 若未登录或无对应商家账号，返回空字符串
final _merchantIdProvider = FutureProvider<String>((ref) async {
  final supabase = ref.watch(_supabaseProvider);
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
// reviewsFilterProvider — 评价列表筛选条件
// =============================================================
/// 评价列表页当前的筛选条件（初始值：全部评价，第1页）
final reviewsFilterProvider = StateProvider<ReviewsFilter>((ref) {
  return const ReviewsFilter(page: 1);
});

// =============================================================
// ReviewsNotifier — 评价列表异步 Notifier
// =============================================================
/// 评价列表 Notifier，监听 reviewsFilterProvider 自动重建
class ReviewsNotifier extends AsyncNotifier<PagedReviews> {
  @override
  Future<PagedReviews> build() async {
    // 监听筛选条件：条件变化时自动触发重建
    final filter        = ref.watch(reviewsFilterProvider);
    final merchantId    = await ref.watch(_merchantIdProvider.future);

    if (merchantId.isEmpty) {
      return PagedReviews.empty();
    }

    final service = ref.read(reviewsServiceProvider);
    return service.fetchReviews(
      merchantId,
      ratingFilter: filter.ratingFilter,
      page:         filter.page,
      perPage:      20,
    );
  }

  // ---------------------------------------------------------
  // replyToReview — 提交商家回复，本地乐观更新
  // [reviewId] — 评价 UUID
  // [reply]    — 回复内容
  // 抛出 [ReviewsException] 若失败
  // ---------------------------------------------------------
  Future<void> replyToReview(String reviewId, String reply) async {
    final merchantId = await ref.read(_merchantIdProvider.future);
    if (merchantId.isEmpty) return;

    final service = ref.read(reviewsServiceProvider);

    // 1. 提交回复到后端
    await service.replyToReview(reviewId, reply);

    // 2. 本地乐观更新：将回复状态同步到当前列表
    final current = state.value;
    if (current != null) {
      final now = DateTime.now();
      final targetReview = current.data.firstWhere(
        (r) => r.id == reviewId,
        orElse: () => throw Exception('Review not found in local state'),
      );
      final updatedReview = targetReview.copyWithReply(reply, now);
      state = AsyncData(current.replaceReview(updatedReview));
    }
  }

  // ---------------------------------------------------------
  // applyRatingFilter — 应用星级筛选（重置到第1页）
  // ---------------------------------------------------------
  void applyRatingFilter(int? rating) {
    ref.read(reviewsFilterProvider.notifier).state = ReviewsFilter(
      ratingFilter: rating,
      page:         1,
    );
  }

  // ---------------------------------------------------------
  // refresh — 手动刷新（pull-to-refresh 用）
  // ---------------------------------------------------------
  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => build());
  }

  // ---------------------------------------------------------
  // loadNextPage — 加载下一页（无限滚动用）
  // ---------------------------------------------------------
  void loadNextPage() {
    final current = ref.read(reviewsFilterProvider);
    ref.read(reviewsFilterProvider.notifier).state =
        current.copyWith(page: current.page + 1);
  }
}

/// 评价列表 Provider
final reviewsProvider = AsyncNotifierProvider<ReviewsNotifier, PagedReviews>(
  ReviewsNotifier.new,
);

// =============================================================
// reviewStatsProvider — 评价统计 FutureProvider
// =============================================================
/// 评价统计数据（页面初始化时加载一次）
/// 刷新方式：调用 ref.invalidate(reviewStatsProvider)
final reviewStatsProvider = FutureProvider<ReviewStats>((ref) async {
  final merchantId = await ref.watch(_merchantIdProvider.future);

  if (merchantId.isEmpty) {
    return ReviewStats.empty();
  }

  final service = ref.read(reviewsServiceProvider);
  return service.fetchReviewStats(merchantId);
});

// =============================================================
// replyStateProvider — 回复提交状态
// =============================================================
/// Map<reviewId, bool>：标记哪些评价正在提交回复（防重复点击）
final replyStateProvider = StateProvider<Map<String, bool>>((ref) => {});

/// 便捷扩展：检查某条评价是否正在提交回复
extension ReplyStateExtension on Map<String, bool> {
  bool isReplying(String reviewId) => this[reviewId] == true;
}

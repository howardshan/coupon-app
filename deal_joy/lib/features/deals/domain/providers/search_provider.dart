import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/models/deal_model.dart';
import 'deals_provider.dart';

// ── 本地搜索历史 key ───────────────────────────────────────────
const _kSearchHistoryKey = 'search_history';
const _kMaxHistoryItems = 10;

// ── 排序选项枚举 ───────────────────────────────────────────────
enum SearchSortOption {
  relevance,    // 默认：相关度
  distance,     // 距离
  priceLow,     // 价格从低到高
  salesHigh,    // 销量从高到低
  ratingHigh,   // 评分从高到低
}

extension SearchSortOptionLabel on SearchSortOption {
  String get label {
    switch (this) {
      case SearchSortOption.relevance:
        return 'Relevance';
      case SearchSortOption.distance:
        return 'Distance';
      case SearchSortOption.priceLow:
        return 'Price: Low to High';
      case SearchSortOption.salesHigh:
        return 'Sales: Highest';
      case SearchSortOption.ratingHigh:
        return 'Rating: Highest';
    }
  }
}

// ── 搜索过滤条件 ───────────────────────────────────────────────
class SearchFilters {
  final String? category;       // 分类过滤
  final double? minPrice;       // 最低价格
  final double? maxPrice;       // 最高价格
  final double? minRating;      // 最低评分

  const SearchFilters({
    this.category,
    this.minPrice,
    this.maxPrice,
    this.minRating,
  });

  SearchFilters copyWith({
    String? category,
    double? minPrice,
    double? maxPrice,
    double? minRating,
    bool clearCategory = false,
    bool clearMinPrice = false,
    bool clearMaxPrice = false,
    bool clearMinRating = false,
  }) {
    return SearchFilters(
      category: clearCategory ? null : (category ?? this.category),
      minPrice: clearMinPrice ? null : (minPrice ?? this.minPrice),
      maxPrice: clearMaxPrice ? null : (maxPrice ?? this.maxPrice),
      minRating: clearMinRating ? null : (minRating ?? this.minRating),
    );
  }

  bool get hasActiveFilters =>
      category != null || minPrice != null || maxPrice != null || minRating != null;
}

// ── 排序选项状态 Provider ──────────────────────────────────────
final searchSortProvider = StateProvider<SearchSortOption>(
  (ref) => SearchSortOption.relevance,
);

// ── 过滤条件状态 Provider ──────────────────────────────────────
final searchFiltersProvider = StateProvider<SearchFilters>(
  (ref) => const SearchFilters(),
);

// ── 搜索历史 Notifier ─────────────────────────────────────────
class SearchHistoryNotifier extends AsyncNotifier<List<String>> {
  @override
  Future<List<String>> build() async {
    // 从 shared_preferences 加载历史记录
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_kSearchHistoryKey) ?? [];
  }

  // 添加搜索词到历史记录（去重 + 限制最多10条）
  Future<void> addQuery(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final current = List<String>.from(state.valueOrNull ?? []);

    // 去重：把已有的相同词移到最前
    current.remove(trimmed);
    current.insert(0, trimmed);

    // 最多保留10条
    final limited = current.take(_kMaxHistoryItems).toList();
    await prefs.setStringList(_kSearchHistoryKey, limited);
    state = AsyncData(limited);
  }

  // 删除单条历史记录
  Future<void> removeQuery(String query) async {
    final prefs = await SharedPreferences.getInstance();
    final current = List<String>.from(state.valueOrNull ?? []);
    current.remove(query);
    await prefs.setStringList(_kSearchHistoryKey, current);
    state = AsyncData(current);
  }

  // 清空所有历史记录
  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kSearchHistoryKey);
    state = const AsyncData([]);
  }
}

final searchHistoryProvider =
    AsyncNotifierProvider<SearchHistoryNotifier, List<String>>(
  SearchHistoryNotifier.new,
);

// ── 搜索建议 Provider（输入2字符后触发，防抖在UI层300ms实现）──
// family 参数为当前输入的关键词
final searchSuggestionsProvider =
    FutureProvider.family<List<DealModel>, String>((ref, query) async {
  if (query.trim().length < 2) return [];

  final repo = ref.watch(dealsRepositoryProvider);
  // 从API拉取匹配建议，最多8条
  final results = await repo.fetchDeals(search: query, page: 0);
  return results.take(8).toList();
});

// ── 搜索结果 Provider（完整带过滤+排序）─────────────────────
// family 参数为最终确认的搜索词
final searchResultsProvider =
    FutureProvider.family<List<DealModel>, String>((ref, query) async {
  if (query.trim().isEmpty) return [];

  final repo = ref.watch(dealsRepositoryProvider);
  final filters = ref.watch(searchFiltersProvider);
  final sort = ref.watch(searchSortProvider);

  // 从API拉取，带分类过滤
  var results = await repo.fetchDeals(
    search: query.trim(),
    category: filters.category,
    page: 0,
  );

  // 客户端侧价格过滤
  if (filters.minPrice != null) {
    results = results
        .where((d) => d.discountPrice >= filters.minPrice!)
        .toList();
  }
  if (filters.maxPrice != null) {
    results = results
        .where((d) => d.discountPrice <= filters.maxPrice!)
        .toList();
  }

  // 客户端侧评分过滤
  if (filters.minRating != null) {
    results = results
        .where((d) => d.rating >= filters.minRating!)
        .toList();
  }

  // 排序
  switch (sort) {
    case SearchSortOption.relevance:
      // 保持API默认排序（featured first, then newest）
      break;
    case SearchSortOption.distance:
      // 暂无真实GPS，维持原顺序
      break;
    case SearchSortOption.priceLow:
      results.sort((a, b) => a.discountPrice.compareTo(b.discountPrice));
      break;
    case SearchSortOption.salesHigh:
      results.sort((a, b) => b.totalSold.compareTo(a.totalSold));
      break;
    case SearchSortOption.ratingHigh:
      results.sort((a, b) => b.rating.compareTo(a.rating));
      break;
  }

  return results;
});

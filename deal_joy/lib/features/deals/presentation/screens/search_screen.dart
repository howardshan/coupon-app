import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shimmer/shimmer.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/models/deal_model.dart';
import '../../domain/providers/search_provider.dart';

// ── 热门搜索标签（硬编码，面向北美Dallas市场）─────────────────
const _hotSearchTags = [
  'BBQ',
  'Sushi',
  'Hot Pot',
  'Massage',
  'Coffee',
  'Dessert',
  'Korean BBQ',
  'Ramen',
  'Pizza',
  'Beauty Salon',
];

/// 搜索页面：包含热门标签、历史记录、实时建议、结果列表、过滤排序
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _searchCtrl = TextEditingController();
  final _focusNode = FocusNode();

  // 当前输入的文字（用于建议）
  String _inputQuery = '';
  // 已提交的搜索词（用于结果列表）
  String _submittedQuery = '';
  // 防抖 Timer
  Timer? _debounce;

  // 当前界面状态
  _SearchPhase _phase = _SearchPhase.idle; // idle / suggesting / results

  @override
  void initState() {
    super.initState();
    // 页面打开时自动聚焦搜索框
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // ── 输入变化处理（300ms 防抖触发建议）─────────────────────
  void _onInputChanged(String value) {
    setState(() {
      _inputQuery = value;
      if (value.trim().length >= 2) {
        _phase = _SearchPhase.suggesting;
      } else {
        _phase = _SearchPhase.idle;
      }
    });

    _debounce?.cancel();
    if (value.trim().length >= 2) {
      _debounce = Timer(const Duration(milliseconds: 300), () {
        // 触发建议 Provider 重新计算（通过 setState 更新 _inputQuery）
        if (mounted) setState(() {});
      });
    }
  }

  // ── 提交搜索 ───────────────────────────────────────────────
  void _submitSearch(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;

    _focusNode.unfocus();
    _searchCtrl.text = trimmed;

    // 保存到历史记录
    ref.read(searchHistoryProvider.notifier).addQuery(trimmed);

    // 重置过滤和排序
    ref.read(searchSortProvider.notifier).state = SearchSortOption.relevance;
    ref.read(searchFiltersProvider.notifier).state = const SearchFilters();

    setState(() {
      _inputQuery = trimmed;
      _submittedQuery = trimmed;
      _phase = _SearchPhase.results;
    });
  }

  // ── 清空搜索框 ─────────────────────────────────────────────
  void _clearSearch() {
    _searchCtrl.clear();
    setState(() {
      _inputQuery = '';
      _submittedQuery = '';
      _phase = _SearchPhase.idle;
    });
    _focusNode.requestFocus();
  }

  // ── 打开过滤底部弹窗 ───────────────────────────────────────
  void _showFilterSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _FilterSheet(
        onApply: (filters) {
          ref.read(searchFiltersProvider.notifier).state = filters;
          Navigator.of(context).pop();
          // 触发结果重新加载
          if (_submittedQuery.isNotEmpty) {
            ref.invalidate(searchResultsProvider(_submittedQuery));
          }
        },
      ),
    );
  }

  // ── 打开排序底部弹窗 ───────────────────────────────────────
  void _showSortSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _SortSheet(
        current: ref.read(searchSortProvider),
        onSelect: (option) {
          ref.read(searchSortProvider.notifier).state = option;
          Navigator.of(context).pop();
          if (_submittedQuery.isNotEmpty) {
            ref.invalidate(searchResultsProvider(_submittedQuery));
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // ── 顶部搜索栏 ──────────────────────────────────
            _SearchBar(
              controller: _searchCtrl,
              focusNode: _focusNode,
              onChanged: _onInputChanged,
              onSubmitted: _submitSearch,
              onClear: _clearSearch,
              onCancel: () => context.pop(),
            ),

            // ── 过滤/排序工具栏（仅在结果页显示）───────────
            if (_phase == _SearchPhase.results) ...[
              _FilterSortBar(
                onFilterTap: _showFilterSheet,
                onSortTap: _showSortSheet,
              ),
            ],

            // ── 主体内容 ────────────────────────────────────
            Expanded(
              child: _buildBody(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    switch (_phase) {
      case _SearchPhase.idle:
        // 显示热门标签 + 搜索历史
        return _IdleView(onTagTap: _submitSearch);

      case _SearchPhase.suggesting:
        // 显示实时建议列表
        return _SuggestionsView(
          query: _inputQuery,
          onTap: _submitSearch,
        );

      case _SearchPhase.results:
        // 显示搜索结果
        return _ResultsView(
          query: _submittedQuery,
          onRetry: () => _submitSearch(_submittedQuery),
        );
    }
  }
}

// ── 页面阶段枚举 ───────────────────────────────────────────────
enum _SearchPhase { idle, suggesting, results }

// ── 搜索栏组件 ─────────────────────────────────────────────────
class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;
  final VoidCallback onCancel;

  const _SearchBar({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onSubmitted,
    required this.onClear,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(
        children: [
          // 搜索输入框
          Expanded(
            child: Container(
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(12),
              ),
              child: TextField(
                key: const ValueKey('search_keyword_field'),
                controller: controller,
                focusNode: focusNode,
                textInputAction: TextInputAction.search,
                onChanged: onChanged,
                onSubmitted: onSubmitted,
                style: const TextStyle(
                  fontSize: 15,
                  color: AppColors.textPrimary,
                ),
                decoration: InputDecoration(
                  hintText: 'Search deals, restaurants, beauty...',
                  hintStyle: const TextStyle(
                    color: AppColors.textHint,
                    fontSize: 15,
                  ),
                  prefixIcon: const Icon(
                    Icons.search,
                    color: AppColors.textHint,
                    size: 20,
                  ),
                  suffixIcon: controller.text.isNotEmpty
                      ? GestureDetector(
                          onTap: onClear,
                          child: const Icon(
                            Icons.cancel,
                            color: AppColors.textHint,
                            size: 18,
                          ),
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          // 取消按钮
          GestureDetector(
            onTap: onCancel,
            child: const Text(
              'Cancel',
              style: TextStyle(
                color: AppColors.primary,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── 过滤/排序工具栏 ────────────────────────────────────────────
class _FilterSortBar extends ConsumerWidget {
  final VoidCallback onFilterTap;
  final VoidCallback onSortTap;

  const _FilterSortBar({
    required this.onFilterTap,
    required this.onSortTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filters = ref.watch(searchFiltersProvider);
    final sort = ref.watch(searchSortProvider);
    final hasFilters = filters.hasActiveFilters;
    final hasSort = sort != SearchSortOption.relevance;

    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Row(
        children: [
          // 过滤按钮
          _ToolbarChip(
            label: 'Filter',
            icon: Icons.tune,
            isActive: hasFilters,
            onTap: onFilterTap,
          ),
          const SizedBox(width: 8),
          // 排序按钮（显示当前排序名）
          _ToolbarChip(
            label: hasSort ? sort.label : 'Sort',
            icon: Icons.sort,
            isActive: hasSort,
            onTap: onSortTap,
          ),
        ],
      ),
    );
  }
}

class _ToolbarChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;

  const _ToolbarChip({
    required this.label,
    required this.icon,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isActive
              ? AppColors.primary.withValues(alpha: 0.1)
              : AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(20),
          border: isActive
              ? Border.all(color: AppColors.primary, width: 1)
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isActive ? AppColors.primary : AppColors.textSecondary,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: isActive ? AppColors.primary : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 空闲状态视图（热门标签 + 搜索历史）────────────────────────
class _IdleView extends ConsumerWidget {
  final ValueChanged<String> onTagTap;

  const _IdleView({required this.onTagTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(searchHistoryProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
      children: [
        // ── 热门搜索 ──────────────────────────────────────
        const Text(
          'Hot Searches',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _hotSearchTags.asMap().entries.map((entry) {
            final index = entry.key;
            final tag = entry.value;
            // 前3个高亮显示（热度最高）
            final isTop = index < 3;
            return GestureDetector(
              onTap: () => onTagTap(tag),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: isTop
                      ? AppColors.primary.withValues(alpha: 0.08)
                      : AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isTop) ...[
                      Icon(
                        Icons.local_fire_department,
                        size: 13,
                        color: isTop ? AppColors.primary : AppColors.textHint,
                      ),
                      const SizedBox(width: 3),
                    ],
                    Text(
                      tag,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight:
                            isTop ? FontWeight.w600 : FontWeight.normal,
                        color: isTop
                            ? AppColors.primary
                            : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),

        // ── 搜索历史 ──────────────────────────────────────
        const SizedBox(height: 28),
        historyAsync.when(
          data: (history) {
            if (history.isEmpty) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Search History',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    // 清空全部按钮
                    GestureDetector(
                      onTap: () =>
                          ref.read(searchHistoryProvider.notifier).clearAll(),
                      child: const Text(
                        'Clear All',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ...history.map(
                  (term) => _HistoryItem(
                    term: term,
                    onTap: () => onTagTap(term),
                    onDelete: () => ref
                        .read(searchHistoryProvider.notifier)
                        .removeQuery(term),
                  ),
                ),
              ],
            );
          },
          loading: () => const SizedBox.shrink(),
          error: (_, _) => const SizedBox.shrink(),
        ),
      ],
    );
  }
}

// ── 历史记录条目 ───────────────────────────────────────────────
class _HistoryItem extends StatelessWidget {
  final String term;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _HistoryItem({
    required this.term,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Row(
          children: [
            const Icon(
              Icons.history,
              size: 18,
              color: AppColors.textHint,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                term,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            // 单条删除按钮
            GestureDetector(
              onTap: onDelete,
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(
                  Icons.close,
                  size: 16,
                  color: AppColors.textHint,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 建议列表视图（输入中，未提交）────────────────────────────
class _SuggestionsView extends ConsumerWidget {
  final String query;
  final ValueChanged<String> onTap;

  const _SuggestionsView({required this.query, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suggestionsAsync = ref.watch(searchSuggestionsProvider(query));

    return suggestionsAsync.when(
      data: (suggestions) {
        if (suggestions.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.search_off,
                  size: 48,
                  color: AppColors.textHint,
                ),
                const SizedBox(height: 12),
                Text(
                  'No suggestions for "$query"',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Press search to find deals',
                  style: TextStyle(
                    color: AppColors.textHint,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.separated(
          padding: EdgeInsets.zero,
          itemCount: suggestions.length,
          separatorBuilder: (_, _) => const Divider(height: 1, indent: 52),
          itemBuilder: (_, i) {
            final deal = suggestions[i];
            return _SuggestionTile(
              deal: deal,
              query: query,
              onTap: () => onTap(deal.title),
            );
          },
        );
      },
      loading: () => _ShimmerSuggestions(),
      error: (_, _) => const SizedBox.shrink(),
    );
  }
}

// ── 单条建议 tile（标题高亮匹配部分）─────────────────────────
class _SuggestionTile extends StatelessWidget {
  final DealModel deal;
  final String query;
  final VoidCallback onTap;

  const _SuggestionTile({
    required this.deal,
    required this.query,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            const Icon(Icons.search, size: 18, color: AppColors.textHint),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 高亮匹配词
                  _HighlightedText(
                    text: deal.title,
                    highlight: query,
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.textPrimary,
                    ),
                    highlightStyle: const TextStyle(
                      fontSize: 14,
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (deal.merchant != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      deal.merchant!.name,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textHint,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Icon(
              Icons.north_west,
              size: 14,
              color: AppColors.textHint,
            ),
          ],
        ),
      ),
    );
  }
}

// ── 文字高亮辅助 Widget ────────────────────────────────────────
class _HighlightedText extends StatelessWidget {
  final String text;
  final String highlight;
  final TextStyle style;
  final TextStyle highlightStyle;

  const _HighlightedText({
    required this.text,
    required this.highlight,
    required this.style,
    required this.highlightStyle,
  });

  @override
  Widget build(BuildContext context) {
    if (highlight.isEmpty) {
      return Text(text, style: style);
    }

    final lowerText = text.toLowerCase();
    final lowerHighlight = highlight.toLowerCase();
    final spans = <TextSpan>[];
    int start = 0;

    while (true) {
      final idx = lowerText.indexOf(lowerHighlight, start);
      if (idx == -1) {
        spans.add(TextSpan(text: text.substring(start), style: style));
        break;
      }
      if (idx > start) {
        spans.add(TextSpan(text: text.substring(start, idx), style: style));
      }
      spans.add(
        TextSpan(
          text: text.substring(idx, idx + highlight.length),
          style: highlightStyle,
        ),
      );
      start = idx + highlight.length;
    }

    return RichText(
      text: TextSpan(children: spans),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

// ── 结果列表视图 ───────────────────────────────────────────────
class _ResultsView extends ConsumerWidget {
  final String query;
  final VoidCallback onRetry;

  const _ResultsView({required this.query, required this.onRetry});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resultsAsync = ref.watch(searchResultsProvider(query));

    return resultsAsync.when(
      data: (deals) {
        if (deals.isEmpty) {
          return _EmptyResults(query: query);
        }
        return _DealResultsList(deals: deals, query: query);
      },
      loading: () => _ShimmerResults(),
      error: (e, _) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.wifi_off, size: 48, color: AppColors.textHint),
            const SizedBox(height: 12),
            const Text(
              'Failed to load results',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            TextButton(
              key: const ValueKey('search_retry_btn'),
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 结果列表主体 ───────────────────────────────────────────────
class _DealResultsList extends StatelessWidget {
  final List<DealModel> deals;
  final String query;

  const _DealResultsList({required this.deals, required this.query});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
      itemCount: deals.length + 1, // +1 for header
      itemBuilder: (_, i) {
        if (i == 0) {
          // 结果计数 header
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'Found ${deals.length} deal${deals.length == 1 ? '' : 's'}',
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: _SearchDealCard(deal: deals[i - 1]),
        );
      },
    );
  }
}

// ── 搜索结果 deal 卡片（横向布局）────────────────────────────
class _SearchDealCard extends StatelessWidget {
  final DealModel deal;

  const _SearchDealCard({required this.deal});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('/deals/${deal.id}'),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            // 商品图片（左侧）
            ClipRRect(
              borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(14),
              ),
              child: SizedBox(
                width: 110,
                height: 110,
                child: (deal.imageUrls.isNotEmpty || deal.merchant?.homepageCoverUrl != null)
                    ? CachedNetworkImage(
                        imageUrl: deal.imageUrls.isNotEmpty
                            ? deal.imageUrls.first
                            : deal.merchant!.homepageCoverUrl!,
                        fit: BoxFit.cover,
                        errorWidget: (_, _, _) => Container(
                          color: AppColors.surfaceVariant,
                          child: const Icon(
                            Icons.image_not_supported,
                            color: AppColors.textHint,
                          ),
                        ),
                      )
                    : Container(
                        color: AppColors.surfaceVariant,
                        child: const Icon(
                          Icons.storefront,
                          color: AppColors.textHint,
                          size: 36,
                        ),
                      ),
              ),
            ),
            // 信息区（右侧）
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 折扣标签
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        deal.effectiveDiscountLabel,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 5),
                    // 标题
                    Text(
                      deal.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    // 商家名
                    Text(
                      deal.merchant?.name ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        // 价格
                        Text(
                          '\$${deal.discountPrice.toStringAsFixed(0)}',
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '\$${deal.originalPrice.toStringAsFixed(0)}',
                          style: const TextStyle(
                            color: AppColors.textHint,
                            fontSize: 11,
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                        const Spacer(),
                        // 评分
                        const Icon(
                          Icons.star,
                          size: 12,
                          color: Colors.amber,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          deal.rating.toStringAsFixed(1),
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 无结果视图 ─────────────────────────────────────────────────
class _EmptyResults extends ConsumerWidget {
  final String query;

  const _EmptyResults({required this.query});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 显示无结果 + 热门推荐
    final featuredAsync = ref.watch(
      // 用空搜索词拉取热门deals作为推荐
      searchResultsProvider('BBQ'),
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 40),
      children: [
        // 无结果提示
        Column(
          children: [
            const Icon(
              Icons.search_off,
              size: 64,
              color: AppColors.textHint,
            ),
            const SizedBox(height: 14),
            Text(
              'No results for "$query"',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Try different keywords or browse hot deals below',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 32),
        // 热门推荐
        const Text(
          'Hot Deals You Might Like',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        featuredAsync.when(
          data: (deals) => Column(
            children: deals
                .take(4)
                .map(
                  (d) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _SearchDealCard(deal: d),
                  ),
                )
                .toList(),
          ),
          loading: () => _ShimmerResults(),
          error: (_, _) => const SizedBox.shrink(),
        ),
      ],
    );
  }
}

// ── Shimmer 建议加载占位 ───────────────────────────────────────
class _ShimmerSuggestions extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppColors.surfaceVariant,
      highlightColor: Colors.white,
      child: ListView.separated(
        padding: EdgeInsets.zero,
        itemCount: 5,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (_, _) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 18,
                height: 18,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  height: 14,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(7),
                  ),
                ),
              ),
              const SizedBox(width: 40),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Shimmer 结果加载占位 ───────────────────────────────────────
class _ShimmerResults extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppColors.surfaceVariant,
      highlightColor: Colors.white,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        itemCount: 4,
        itemBuilder: (_, _) => Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Container(
            height: 110,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Container(
                  width: 110,
                  height: 110,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.horizontal(
                      left: Radius.circular(14),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        Container(
                          width: 50,
                          height: 14,
                          color: Colors.white,
                        ),
                        Container(
                          width: double.infinity,
                          height: 12,
                          color: Colors.white,
                        ),
                        Container(
                          width: 100,
                          height: 12,
                          color: Colors.white,
                        ),
                        Container(
                          width: 80,
                          height: 14,
                          color: Colors.white,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── 过滤底部弹窗 ───────────────────────────────────────────────
class _FilterSheet extends ConsumerStatefulWidget {
  final void Function(SearchFilters) onApply;

  const _FilterSheet({required this.onApply});

  @override
  ConsumerState<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends ConsumerState<_FilterSheet> {
  String? _selectedCategory;
  double? _minPrice;
  double? _maxPrice;
  double? _minRating;

  // 价格区间选项
  final _priceRanges = const [
    (label: 'Under \$20', min: 0.0, max: 20.0),
    (label: '\$20 - \$50', min: 20.0, max: 50.0),
    (label: '\$50 - \$100', min: 50.0, max: 100.0),
    (label: 'Over \$100', min: 100.0, max: null),
  ];

  // 评分选项
  final _ratingOptions = [4.5, 4.0, 3.5, 3.0];

  @override
  void initState() {
    super.initState();
    // 读取已有过滤条件初始化
    final current = ref.read(searchFiltersProvider);
    _selectedCategory = current.category;
    _minPrice = current.minPrice;
    _maxPrice = current.maxPrice;
    _minRating = current.minRating;
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      maxChildSize: 0.9,
      minChildSize: 0.4,
      expand: false,
      builder: (_, scrollCtrl) => Column(
        children: [
          // 拖拽把手
          const SizedBox(height: 8),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.textHint,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          // 标题栏
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                const Text(
                  'Filter',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                TextButton(
                  key: const ValueKey('search_reset_filters_btn'),
                  onPressed: () => setState(() {
                    _selectedCategory = null;
                    _minPrice = null;
                    _maxPrice = null;
                    _minRating = null;
                  }),
                  child: const Text(
                    'Reset',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ),
              ],
            ),
          ),
          const Divider(),
          // 内容
          Expanded(
            child: ListView(
              controller: scrollCtrl,
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              children: [
                // 分类过滤
                const Text(
                  'Category',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: AppConstants.categories
                      .where((c) => c != 'All')
                      .map((cat) {
                    final isSelected = _selectedCategory == cat;
                    return GestureDetector(
                      onTap: () => setState(() {
                        _selectedCategory = isSelected ? null : cat;
                      }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppColors.primary
                              : AppColors.surfaceVariant,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          cat,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: isSelected
                                ? Colors.white
                                : AppColors.textSecondary,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),

                const SizedBox(height: 24),
                // 价格区间过滤
                const Text(
                  'Price Range',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 10),
                ..._priceRanges.map((range) {
                  final isSelected =
                      _minPrice == range.min && _maxPrice == range.max;
                  return InkWell(
                    onTap: () => setState(() {
                      if (isSelected) {
                        _minPrice = null;
                        _maxPrice = null;
                      } else {
                        _minPrice = range.min;
                        _maxPrice = range.max;
                      }
                    }),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          // 自定义选择指示器
                          Container(
                            width: 20,
                            height: 20,
                            margin: const EdgeInsets.only(right: 12),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isSelected
                                    ? AppColors.primary
                                    : AppColors.textHint,
                                width: 2,
                              ),
                              color: isSelected
                                  ? AppColors.primary
                                  : Colors.transparent,
                            ),
                            child: isSelected
                                ? const Icon(
                                    Icons.check,
                                    size: 12,
                                    color: Colors.white,
                                  )
                                : null,
                          ),
                          Text(
                            range.label,
                            style: TextStyle(
                              fontSize: 14,
                              color: isSelected
                                  ? AppColors.primary
                                  : AppColors.textPrimary,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),

                const SizedBox(height: 16),
                // 评分过滤
                const Text(
                  'Minimum Rating',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 10),
                ..._ratingOptions.map((rating) {
                  final isSelected = _minRating == rating;
                  return InkWell(
                    onTap: () => setState(() {
                      _minRating = isSelected ? null : rating;
                    }),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          // 自定义选择指示器（替代已弃用的 Radio widget）
                          Container(
                            width: 20,
                            height: 20,
                            margin: const EdgeInsets.only(right: 12),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isSelected
                                    ? AppColors.primary
                                    : AppColors.textHint,
                                width: 2,
                              ),
                              color: isSelected
                                  ? AppColors.primary
                                  : Colors.transparent,
                            ),
                            child: isSelected
                                ? const Icon(
                                    Icons.check,
                                    size: 12,
                                    color: Colors.white,
                                  )
                                : null,
                          ),
                          Row(
                            children: List.generate(5, (i) {
                              return Icon(
                                i < rating.floor()
                                    ? Icons.star
                                    : (i < rating
                                        ? Icons.star_half
                                        : Icons.star_border),
                                size: 16,
                                color: Colors.amber,
                              );
                            }),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '$rating & up',
                            style: TextStyle(
                              fontSize: 13,
                              color: isSelected
                                  ? AppColors.primary
                                  : AppColors.textPrimary,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),

          // 应用按钮
          Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              8,
              20,
              MediaQuery.of(context).padding.bottom + 12,
            ),
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                key: const ValueKey('search_apply_filters_btn'),
                onPressed: () => widget.onApply(
                  SearchFilters(
                    category: _selectedCategory,
                    minPrice: _minPrice,
                    maxPrice: _maxPrice,
                    minRating: _minRating,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Apply Filters',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── 排序底部弹窗 ───────────────────────────────────────────────
class _SortSheet extends StatelessWidget {
  final SearchSortOption current;
  final void Function(SearchSortOption) onSelect;

  const _SortSheet({required this.current, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.textHint,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Sort By',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Divider(),
          ...SearchSortOption.values.map((option) {
            final isSelected = option == current;
            return ListTile(
              title: Text(
                option.label,
                style: TextStyle(
                  color: isSelected ? AppColors.primary : AppColors.textPrimary,
                  fontWeight:
                      isSelected ? FontWeight.w600 : FontWeight.normal,
                  fontSize: 15,
                ),
              ),
              trailing: isSelected
                  ? const Icon(Icons.check, color: AppColors.primary)
                  : null,
              onTap: () => onSelect(option),
            );
          }),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

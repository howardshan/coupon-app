import 'package:flutter_test/flutter_test.dart';
import 'package:deal_joy/features/deals/domain/providers/search_provider.dart';

void main() {
  group('SearchFilters', () {
    test('默认无激活过滤', () {
      const f = SearchFilters();
      expect(f.hasActiveFilters, false);
      expect(f.category, isNull);
      expect(f.minPrice, isNull);
      expect(f.maxPrice, isNull);
      expect(f.minRating, isNull);
    });

    test('copyWith 设置分类', () {
      const f = SearchFilters();
      final f2 = f.copyWith(category: 'Food');
      expect(f2.category, 'Food');
      expect(f2.hasActiveFilters, true);
    });

    test('copyWith 设置价格范围', () {
      const f = SearchFilters();
      final f2 = f.copyWith(minPrice: 10.0, maxPrice: 50.0);
      expect(f2.minPrice, 10.0);
      expect(f2.maxPrice, 50.0);
      expect(f2.hasActiveFilters, true);
    });

    test('copyWith 设置评分', () {
      const f = SearchFilters();
      final f2 = f.copyWith(minRating: 4.0);
      expect(f2.minRating, 4.0);
      expect(f2.hasActiveFilters, true);
    });

    test('copyWith 清除分类', () {
      final f = const SearchFilters(category: 'Food');
      final f2 = f.copyWith(clearCategory: true);
      expect(f2.category, isNull);
    });

    test('copyWith 清除价格', () {
      final f = const SearchFilters(minPrice: 10, maxPrice: 50);
      final f2 = f.copyWith(clearMinPrice: true, clearMaxPrice: true);
      expect(f2.minPrice, isNull);
      expect(f2.maxPrice, isNull);
      expect(f2.hasActiveFilters, false);
    });

    test('copyWith 保留未指定字段', () {
      final f = const SearchFilters(
        category: 'Food',
        minPrice: 10,
        maxPrice: 50,
        minRating: 3.5,
      );
      final f2 = f.copyWith(minRating: 4.0);
      expect(f2.category, 'Food');
      expect(f2.minPrice, 10);
      expect(f2.maxPrice, 50);
      expect(f2.minRating, 4.0);
    });
  });

  group('SearchSortOption', () {
    test('所有选项都有 label', () {
      for (final option in SearchSortOption.values) {
        expect(option.label, isNotEmpty);
      }
    });

    test('label 值正确', () {
      expect(SearchSortOption.relevance.label, 'Relevance');
      expect(SearchSortOption.distance.label, 'Distance');
      expect(SearchSortOption.priceLow.label, 'Price: Low to High');
      expect(SearchSortOption.salesHigh.label, 'Sales: Highest');
      expect(SearchSortOption.ratingHigh.label, 'Rating: Highest');
    });

    test('共5个排序选项', () {
      expect(SearchSortOption.values.length, 5);
    });
  });
}

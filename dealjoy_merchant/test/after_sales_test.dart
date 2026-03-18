import 'package:dealjoy_merchant/features/after_sales/data/merchant_after_sales_request.dart';
import 'package:dealjoy_merchant/features/after_sales/pages/after_sales_list_page.dart';
import 'package:dealjoy_merchant/features/after_sales/providers/after_sales_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final sampleRequest = MerchantAfterSalesRequest(
    id: 'req-123',
    status: 'pending',
    reasonCode: 'bad_experience',
    reasonDetail: 'Customer reports food arrived cold.',
    refundAmount: 18.25,
    userDisplayName: 'J***e',
    timeline: const [
      AfterSalesTimelineEntry(
        status: 'submitted',
        actor: 'user',
        timestamp: DateTime(2024, 03, 01, 12, 0),
        note: 'Initial submission',
      ),
    ],
    expiresAt: DateTime(2024, 03, 02, 12, 0),
    createdAt: DateTime(2024, 03, 01, 12, 0),
  );

  testWidgets('AfterSalesListPage renders a pending request card', (tester) async {
    final state = AfterSalesListState(
      requests: [sampleRequest],
      total: 1,
      page: 1,
      perPage: 20,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          afterSalesListProvider.overrideWith(() => _StaticAfterSalesListNotifier(state)),
        ],
        child: const MaterialApp(home: AfterSalesListPage()),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.textContaining('Customer reports food'), findsOneWidget);
    expect(find.text('J***e'), findsOneWidget);
    expect(find.text('PENDING'), findsOneWidget);
  });

  testWidgets('AfterSalesListPage empty state copy renders', (tester) async {
    const emptyState = AfterSalesListState(
      requests: [],
      total: 0,
      page: 1,
      perPage: 20,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          afterSalesListProvider.overrideWith(() => _StaticAfterSalesListNotifier(emptyState)),
        ],
        child: const MaterialApp(home: AfterSalesListPage()),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.textContaining('No Action Required requests'), findsOneWidget);
  });
}

class _StaticAfterSalesListNotifier extends MerchantAfterSalesListNotifier {
  _StaticAfterSalesListNotifier(this._state);

  final AfterSalesListState _state;

  @override
  Future<AfterSalesListState> build() async => _state;

  @override
  Future<void> refresh() async {
    state = AsyncData(_state);
  }

  @override
  Future<void> loadMore() async {}
}

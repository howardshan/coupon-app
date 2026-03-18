import 'package:deal_joy/features/after_sales/data/models/after_sales_request_model.dart';
import 'package:deal_joy/features/after_sales/domain/providers/after_sales_provider.dart';
import 'package:deal_joy/features/after_sales/presentation/pages/after_sales_screen_args.dart';
import 'package:deal_joy/features/after_sales/presentation/pages/after_sales_timeline_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const args = AfterSalesScreenArgs(
    orderId: 'order_1',
    couponId: 'coupon_1',
    dealTitle: 'Test Deal',
    totalAmount: 15.0,
    merchantName: 'Demo Store',
  );

  testWidgets('AfterSalesTimelinePage shows empty state when no request exists', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          afterSalesRequestProvider.overrideWith((ref, orderId) async => null),
        ],
        child: const MaterialApp(home: AfterSalesTimelinePage(args: args)),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.text('Need help after redemption?'), findsOneWidget);
    expect(find.text('Start After-Sales Request'), findsOneWidget);
  });

  testWidgets('AfterSalesTimelinePage renders a timeline entry when data is available', (tester) async {
    final request = AfterSalesRequestModel(
      id: 'req_1',
      orderId: 'order_1',
      couponId: 'coupon_1',
      status: 'pending',
      reasonCode: 'bad_experience',
      reasonDetail: 'Customer reported cold food.',
      refundAmount: 12.5,
      timeline: const [
        AfterSalesTimelineEntry(
          status: 'submitted',
          actor: 'user',
          timestamp: DateTime(2024, 01, 01, 10, 30),
          note: 'App-submitted request',
        ),
      ],
      createdAt: DateTime(2024, 01, 01, 10, 30),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          afterSalesRequestProvider.overrideWith((ref, orderId) async => request),
        ],
        child: const MaterialApp(home: AfterSalesTimelinePage(args: args)),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.text('Status Timeline'), findsOneWidget);
    expect(find.text('SUBMITTED'), findsOneWidget);
    expect(find.textContaining('cold food'), findsOneWidget);
  });
}

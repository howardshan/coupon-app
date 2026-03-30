// 待评价独立页（与 My Coupons → Reviews → Pending 同源数据）
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../widgets/pending_reviews_list.dart';

class ToReviewScreen extends ConsumerWidget {
  const ToReviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reviews')),
      body: const PendingReviewsList(),
    );
  }
}

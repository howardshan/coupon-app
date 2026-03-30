// 「我的评价」独立页（与 My Coupons → Reviews → Submitted 同源列表）
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../widgets/submitted_reviews_list.dart';

class MyReviewsScreen extends ConsumerWidget {
  const MyReviewsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Reviews')),
      body: const SubmittedReviewsList(),
    );
  }
}

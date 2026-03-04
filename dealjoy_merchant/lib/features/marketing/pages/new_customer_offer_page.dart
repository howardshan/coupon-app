// 新客特惠管理页（V2 骨架）
// 优先级: P2/V2 — UI 占位，功能待 V2 实现

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// TODO: V2 — 取消注释以接入真实数据
// ignore: unused_import
import '../providers/marketing_provider.dart';
import '../widgets/coming_soon_placeholder.dart';

/// 新客特惠管理页
/// V2 骨架页：展示功能预览，核心交互标注 TODO: V2
class NewCustomerOfferPage extends ConsumerWidget {
  const NewCustomerOfferPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // TODO: V2 — 接入 newCustomerOffersProvider 展示真实列表
    // final offersAsync = ref.watch(newCustomerOffersProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded,
              color: Color(0xFF1A1A1A), size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'New Customer Offer',
          style: TextStyle(
            color: Color(0xFF1A1A1A),
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: false,
        actions: [
          // TODO: V2 — 启用 Create Offer 按钮
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Opacity(
              opacity: 0.4,
              child: ElevatedButton.icon(
                onPressed: null, // TODO: V2
                icon: const Icon(Icons.add, size: 16),
                label: const Text('New'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4CAF50),
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  textStyle: const TextStyle(fontSize: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: const ComingSoonPlaceholder(
        icon: Icons.person_add_rounded,
        iconColor: Color(0xFF4CAF50),
        title: 'New Customer Offer',
        subtitle: 'Coming in V2',
        description:
            'Set a special price exclusively for first-time buyers.\n'
            'New customers see the discounted price on the deal page, '
            'while returning customers see only the regular price.',
        features: [
          'Set a special price for any of your active deals',
          'Only shown to users with zero previous orders',
          'Returning customers cannot see or use this price',
          'Automatically validates at checkout — no coupon code needed',
          'Track new customer conversion rate in Analytics (V2)',
        ],
      ),
    );
  }
}

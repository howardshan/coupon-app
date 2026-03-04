// 满减活动管理页（V2 骨架）
// 优先级: P2/V2 — UI 占位，功能待 V2 实现

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// TODO: V2 — 取消注释以接入真实数据
// ignore: unused_import
import '../providers/marketing_provider.dart';
import '../widgets/coming_soon_placeholder.dart';

/// 满减活动管理页
/// V2 骨架页：展示功能预览，核心交互标注 TODO: V2
class PromotionsPage extends ConsumerWidget {
  const PromotionsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // TODO: V2 — 接入 promotionsProvider 展示真实列表
    // final promotionsAsync = ref.watch(promotionsProvider);

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
          'Promotions',
          style: TextStyle(
            color: Color(0xFF1A1A1A),
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: false,
        actions: [
          // TODO: V2 — 启用 Create Promotion 按钮
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Opacity(
              opacity: 0.4,
              child: ElevatedButton.icon(
                onPressed: null, // TODO: V2
                icon: const Icon(Icons.add, size: 16),
                label: const Text('New'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2196F3),
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
        icon: Icons.local_offer_rounded,
        iconColor: Color(0xFF2196F3),
        title: 'Promotions',
        subtitle: 'Coming in V2',
        description:
            'Create spend-and-save campaigns for your store.\n'
            'Set a minimum spend threshold and a discount amount — '
            'customers who qualify get the savings applied automatically at checkout.',
        features: [
          'Set minimum spend amount (e.g. spend \$30)',
          'Set discount amount (e.g. get \$5 off)',
          'Apply to a specific deal or your entire store',
          'Set optional start and end dates for the campaign',
          'Discount applied automatically at checkout — no code needed',
          'Per-user usage limits to prevent abuse (V2 advanced)',
        ],
      ),
    );
  }
}

// 限时折扣管理页（V2 骨架）
// 优先级: P2/V2 — UI 占位，功能待 V2 实现

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// TODO: V2 — 取消注释以接入真实数据
// ignore: unused_import
import '../providers/marketing_provider.dart';
import '../widgets/coming_soon_placeholder.dart';

/// 限时折扣管理页
/// V2 骨架页：展示功能预览，核心交互标注 TODO: V2
class FlashDealsPage extends ConsumerWidget {
  const FlashDealsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // TODO: V2 — 接入 flashDealsProvider 展示真实列表
    // final flashDealsAsync = ref.watch(flashDealsProvider);

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
          'Flash Deals',
          style: TextStyle(
            color: Color(0xFF1A1A1A),
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: false,
        actions: [
          // TODO: V2 — 启用 Create Flash Deal 按钮
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Opacity(
              opacity: 0.4,
              child: ElevatedButton.icon(
                onPressed: null, // TODO: V2
                icon: const Icon(Icons.add, size: 16),
                label: const Text('New'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF6B35),
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
      body: ComingSoonPlaceholder(
        icon: Icons.bolt_rounded,
        iconColor: const Color(0xFFFF6B35),
        title: 'Flash Deals',
        subtitle: 'Coming in V2',
        description:
            'Create time-limited discounts on your deals.\n'
            'Flash Deals appear in the dedicated section on the customer home screen, '
            'driving urgency and boosting sales during peak hours.',
        features: const [
          'Select any active deal to add a flash discount',
          'Set extra discount percentage (e.g. extra 10% off)',
          'Choose start and end time for the promotion',
          'Deals auto-restore to original price when expired',
          'Real-time countdown shown to customers',
        ],
      ),
    );
  }
}

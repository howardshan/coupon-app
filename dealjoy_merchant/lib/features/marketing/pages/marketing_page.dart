// 营销工具主页
// 显示三个功能入口卡片，全部标注 "Coming in V2"
// 优先级: P2/V2

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'flash_deals_page.dart';
import 'new_customer_offer_page.dart';
import 'promotions_page.dart';

/// 营销工具主页
/// 三个卡片入口：Flash Deals / New Customer Offer / Promotions
class MarketingPage extends ConsumerWidget {
  const MarketingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Marketing Tools',
          style: TextStyle(
            color: Color(0xFF1A1A1A),
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: false,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 顶部说明横幅
          _ComingSoonBanner(),
          const SizedBox(height: 20),
          // Flash Deals 卡片
          _MarketingToolCard(
            icon: Icons.bolt_rounded,
            iconColor: const Color(0xFFFF6B35),
            iconBackground: const Color(0xFFFFF0EA),
            title: 'Flash Deals',
            subtitle: 'Set limited-time extra discounts on your deals',
            description:
                'Create time-limited promotions that appear in the Flash Deals section on the home screen. Boost visibility and drive impulse purchases.',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const FlashDealsPage()),
            ),
          ),
          const SizedBox(height: 12),
          // New Customer Offer 卡片
          _MarketingToolCard(
            icon: Icons.person_add_rounded,
            iconColor: const Color(0xFF4CAF50),
            iconBackground: const Color(0xFFE8F5E9),
            title: 'New Customer Offer',
            subtitle: 'Special price for first-time buyers only',
            description:
                'Set an exclusive price that only new customers can see and purchase. Existing customers will not see this price.',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const NewCustomerOfferPage()),
            ),
          ),
          const SizedBox(height: 12),
          // Promotions 卡片
          _MarketingToolCard(
            icon: Icons.local_offer_rounded,
            iconColor: const Color(0xFF2196F3),
            iconBackground: const Color(0xFFE3F2FD),
            title: 'Promotions',
            subtitle: 'Spend X get Y off campaigns',
            description:
                'Set up spend-and-save promotions. Customers who meet the minimum spend automatically get a discount at checkout.',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const PromotionsPage()),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ============================================================
// 顶部 Coming Soon 横幅
// ============================================================
class _ComingSoonBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFF6B35), Color(0xFFFF8C5A)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.rocket_launch_rounded,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Boost your sales with powerful marketing tools',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Coming Soon — Full features launching in V2',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// 营销工具卡片组件
// ============================================================
class _MarketingToolCard extends StatelessWidget {
  const _MarketingToolCard({
    required this.icon,
    required this.iconColor,
    required this.iconBackground,
    required this.title,
    required this.subtitle,
    required this.description,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final Color iconBackground;
  final String title;
  final String subtitle;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // 图标
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: iconBackground,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: iconColor, size: 24),
                  ),
                  const SizedBox(width: 12),
                  // 标题和副标题
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1A1A1A),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF888888),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Coming in V2 Badge
                  _ComingInV2Badge(),
                ],
              ),
              const SizedBox(height: 12),
              // 功能描述
              Text(
                description,
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF666666),
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 12),
              // 底部箭头提示
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    'Learn more',
                    style: TextStyle(
                      fontSize: 13,
                      color: iconColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 12,
                    color: iconColor,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// Coming in V2 Badge
// ============================================================
class _ComingInV2Badge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFFFCC80), width: 1),
      ),
      child: const Text(
        'Coming in V2',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: Color(0xFFE65100),
        ),
      ),
    );
  }
}

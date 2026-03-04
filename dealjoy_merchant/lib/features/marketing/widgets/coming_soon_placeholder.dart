// 营销工具 "Coming Soon" 占位组件
// 供 FlashDealsPage / NewCustomerOfferPage / PromotionsPage 共享使用

import 'package:flutter/material.dart';

/// V2 功能占位组件
/// 展示功能图标、标题、描述和预计功能列表
class ComingSoonPlaceholder extends StatelessWidget {
  const ComingSoonPlaceholder({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.description,
    required this.features,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final String description;

  /// V2 将实现的功能要点列表
  final List<String> features;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 24),
          // 功能图标
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor, size: 40),
          ),
          const SizedBox(height: 20),
          // 标题
          Text(
            title,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 8),
          // Coming in V2 Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF3E0),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFFFCC80)),
            ),
            child: Text(
              subtitle,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFFE65100),
              ),
            ),
          ),
          const SizedBox(height: 20),
          // 功能描述
          Text(
            description,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF666666),
              height: 1.6,
            ),
          ),
          const SizedBox(height: 28),
          // 分隔线 + 功能列表标题
          Row(
            children: [
              Expanded(child: Divider(color: Colors.grey.shade200)),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  'What\'s coming in V2',
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF999999),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Expanded(child: Divider(color: Colors.grey.shade200)),
            ],
          ),
          const SizedBox(height: 16),
          // 功能要点列表
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade100),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: features
                  .map(
                    (feature) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            margin: const EdgeInsets.only(top: 5),
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: iconColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              feature,
                              style: const TextStyle(
                                fontSize: 13,
                                color: Color(0xFF444444),
                                height: 1.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          const SizedBox(height: 32),
          // 底部提示文案
          Text(
            'This feature is under development.\nStay tuned for the V2 update!',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade400,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

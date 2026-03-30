// 品牌管理页面
// 品牌管理员可以：编辑品牌信息、查看旗下门店列表、管理品牌管理员
// Phase 4: 功能点 #28-#33

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/store_provider.dart';
import '../models/brand_info.dart';

// 品牌管理网格入口数据
class _BrandMenuItem {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final String route;

  const _BrandMenuItem({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.route,
  });
}

class BrandManagePage extends ConsumerWidget {
  const BrandManagePage({super.key});

  static const _primaryOrange = Color(0xFFFF6B35);

  // 固定功能入口（始终显示）
  static const List<_BrandMenuItem> _baseMenuItems = [
    _BrandMenuItem(
      icon: Icons.info_outline,
      label: 'Brand Info',
      subtitle: 'Name, logo & details',
      color: Color(0xFFFF6B35),
      route: '/brand-manage/info',
    ),
    _BrandMenuItem(
      icon: Icons.storefront_outlined,
      label: 'Stores',
      subtitle: 'Manage locations',
      color: Color(0xFF4CAF50),
      route: '/brand-manage/stores',
    ),
    _BrandMenuItem(
      icon: Icons.admin_panel_settings_outlined,
      label: 'Admins',
      subtitle: 'Team access',
      color: Color(0xFF9C27B0),
      route: '/brand-manage/admins',
    ),
    _BrandMenuItem(
      icon: Icons.local_offer_outlined,
      label: 'Deals',
      subtitle: 'Multi-store deals',
      color: Color(0xFF2196F3),
      route: '/brand-manage/deals',
    ),
    _BrandMenuItem(
      icon: Icons.dashboard_outlined,
      label: 'Overview',
      subtitle: 'Stats & trends',
      color: Color(0xFFFF9800),
      route: '/brand-overview',
    ),
  ];

  // 品牌佣金功能入口（仅 commissionRate > 0 时显示）
  static const List<_BrandMenuItem> _commissionMenuItems = [
    _BrandMenuItem(
      icon: Icons.account_balance_wallet_outlined,
      label: 'Earnings',
      subtitle: 'Brand commission',
      color: Color(0xFF4CAF50),
      route: '/brand-manage/earnings',
    ),
    _BrandMenuItem(
      icon: Icons.payment_outlined,
      label: 'Stripe Connect',
      subtitle: 'Payout account',
      color: Color(0xFF635BFF),
      route: '/brand-manage/stripe-connect',
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storeAsync = ref.watch(storeProvider);

    return Scaffold(
      key: const ValueKey('brand_manage_page'),
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          key: const ValueKey('brand_manage_back_btn'),
          icon: const Icon(Icons.arrow_back, color: Color(0xFF212121)),
          onPressed: () {
            if (Navigator.canPop(context)) {
              Navigator.pop(context);
            } else {
              context.go('/dashboard');
            }
          },
        ),
        title: const Text(
          'Brand Management',
          style: TextStyle(
            color: Color(0xFF212121),
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
      ),
      body: storeAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: _primaryOrange),
        ),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (storeInfo) {
          final brand = storeInfo.brand;
          if (brand == null) {
            return const Center(
              child: Text(
                'No brand associated with this store.',
                style: TextStyle(color: Color(0xFF757575)),
              ),
            );
          }

          // 动态构建菜单列表：基础入口 + 佣金入口（commissionRate > 0 时追加）
          final menuItems = [
            ..._baseMenuItems,
            if (brand.commissionRate > 0) ..._commissionMenuItems,
          ];

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 品牌信息头部
                _BrandHeaderCard(brand: brand),
                const SizedBox(height: 20),
                // 功能入口网格
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.2,
                  children: menuItems.map((item) => _MenuCard(
                    item: item,
                    onTap: () => context.push(item.route),
                  )).toList(),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// 品牌信息头部卡片
class _BrandHeaderCard extends StatelessWidget {
  const _BrandHeaderCard({required this.brand});
  final BrandInfo brand;

  static const _primaryOrange = Color(0xFFFF6B35);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFF6B35), Color(0xFFFF8F65)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(51),
              borderRadius: BorderRadius.circular(12),
            ),
            child: brand.logoUrl != null && brand.logoUrl!.isNotEmpty
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(brand.logoUrl!, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.business, color: Colors.white, size: 28,
                      ),
                    ),
                  )
                : const Icon(Icons.business, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  brand.name,
                  style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white,
                  ),
                ),
                if (brand.description != null && brand.description!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    brand.description!,
                    style: TextStyle(fontSize: 13, color: Colors.white.withAlpha(204)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (brand.storeCount != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${brand.storeCount} locations',
                    style: TextStyle(fontSize: 12, color: Colors.white.withAlpha(179)),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// 功能入口卡片
class _MenuCard extends StatelessWidget {
  const _MenuCard({required this.item, required this.onTap});
  final _BrandMenuItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey.shade100),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: item.color.withAlpha(26),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(item.icon, color: item.color, size: 20),
              ),
              const SizedBox(height: 8),
              Text(
                item.label,
                style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF212121),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                item.subtitle,
                style: const TextStyle(fontSize: 11, color: Color(0xFF9E9E9E)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}


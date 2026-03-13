// 商家设置主页面
// 结构: Profile 区块 / Account 分组（V2）/ Notifications / Support / Sign Out

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/settings_provider.dart';
import '../widgets/settings_section.dart';
import '../widgets/settings_tile.dart';
import '../../store/providers/store_provider.dart';

// ============================================================
// SettingsPage — 商家设置主入口（ConsumerWidget）
// ============================================================
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.watch(settingsServiceProvider);
    final email = service.currentUserEmail;

    // 获取门店信息，判断是否为连锁店、是否有品牌管理权限
    final storeInfo = ref.watch(storeProvider).valueOrNull;
    final isChainStore = storeInfo?.isChainStore ?? false;
    final isStoreOwner = storeInfo?.currentRole == 'store_owner';
    final hasBrandPermission = storeInfo?.hasPermission('brand') ?? false;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A1A1A),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 16),
        children: [
          // --------------------------------------------------
          // Profile 区块：商家名/邮箱（只读展示）
          // --------------------------------------------------
          _buildProfileSection(context, email),
          const SizedBox(height: 8),

          // --------------------------------------------------
          // Account 分组：账号安全 + 员工子账号（V2 骨架）
          // --------------------------------------------------
          SettingsSection(
            title: 'Account',
            children: [
              SettingsTile(
                icon: Icons.lock_outline,
                title: 'Account Security',
                subtitle: 'Password, phone, 2FA',
                onTap: () => context.push('/me/account-security'),
              ),
              SettingsTile(
                icon: Icons.group_outlined,
                title: 'Staff Accounts',
                subtitle: 'Manage employee access',
                showDivider: false,
                onTap: () => context.push('/me/staff'),
              ),
            ],
          ),

          // --------------------------------------------------
          // Store & Brand 分组（根据角色动态显示）
          // --------------------------------------------------
          if (isChainStore && hasBrandPermission)
            SettingsSection(
              title: 'Brand',
              children: [
                SettingsTile(
                  key: const ValueKey('settings_brand_management_btn'),
                  icon: Icons.business,
                  title: 'Brand Management',
                  subtitle: 'Manage your brand and stores',
                  onTap: () => context.push('/brand-manage'),
                ),
                SettingsTile(
                  icon: Icons.swap_horiz,
                  title: 'Switch Store',
                  subtitle: 'Select a different location',
                  showDivider: false,
                  onTap: () => context.go('/store-selector'),
                ),
              ],
            ),
          // 独立门店 + store_owner → 显示"升级为连锁"入口
          if (!isChainStore && isStoreOwner)
            SettingsSection(
              title: 'Growth',
              children: [
                SettingsTile(
                  key: const ValueKey('settings_upgrade_chain_btn'),
                  icon: Icons.trending_up,
                  title: 'Upgrade to Chain',
                  subtitle: 'Expand your business to multiple locations',
                  showDivider: false,
                  onTap: () => _showUpgradeDialog(context, ref),
                ),
              ],
            ),

          // --------------------------------------------------
          // Notifications 分组
          // --------------------------------------------------
          SettingsSection(
            title: 'Notifications',
            children: [
              SettingsTile(
                icon: Icons.notifications_outlined,
                title: 'Notification Preferences',
                subtitle: 'Choose what alerts you receive',
                showDivider: false,
                onTap: () => context.push('/me/notifications'),
              ),
            ],
          ),

          // --------------------------------------------------
          // Support 分组：帮助中心 + 关于
          // --------------------------------------------------
          SettingsSection(
            title: 'Support',
            children: [
              SettingsTile(
                icon: Icons.help_outline,
                title: 'Help Center',
                subtitle: 'FAQ and contact support',
                onTap: () => context.push('/me/help'),
              ),
              SettingsTile(
                icon: Icons.info_outline,
                title: 'About DealJoy',
                subtitle: 'Version 1.0.0',
                showDivider: false,
                onTap: () => _showAboutDialog(context),
              ),
            ],
          ),

          // --------------------------------------------------
          // Danger Zone（仅 store_owner 显示）
          // --------------------------------------------------
          if (isStoreOwner)
            SettingsSection(
              title: 'Danger Zone',
              children: [
                if (isChainStore)
                  SettingsTile(
                    key: const ValueKey('settings_leave_brand_btn'),
                    icon: Icons.link_off,
                    title: 'Leave Brand',
                    subtitle: 'Disconnect from brand, become independent',
                    onTap: () => _confirmLeaveBrand(context, ref),
                  ),
                SettingsTile(
                  key: const ValueKey('settings_close_store_btn'),
                  icon: Icons.store_outlined,
                  title: 'Close Store',
                  subtitle: 'Permanently close and refund all vouchers',
                  showDivider: false,
                  onTap: () => _confirmCloseStore(context, ref),
                ),
              ],
            ),

          // --------------------------------------------------
          // Sign Out 按钮（红色，独立区块）
          // --------------------------------------------------
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: OutlinedButton.icon(
              onPressed: () => _confirmSignOut(context, ref),
              icon: const Icon(Icons.logout, size: 18),
              label: const Text('Sign Out'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                side: const BorderSide(color: Colors.red),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                minimumSize: const Size(double.infinity, 48),
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // ----------------------------------------------------------
  // Profile 区块：显示邮箱头像和账号信息
  // ----------------------------------------------------------
  Widget _buildProfileSection(BuildContext context, String email) {
    // 头像首字母：取邮箱 @ 前第一个字符大写
    final initial = email.isNotEmpty ? email[0].toUpperCase() : 'M';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16).copyWith(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // 头像圆圈
            CircleAvatar(
              radius: 28,
              backgroundColor: const Color(0xFFFF6B35),
              child: Text(
                initial,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 16),
            // 邮箱信息
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Merchant Account',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1A1A1A),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    email.isNotEmpty ? email : 'Not signed in',
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF6B7280),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ----------------------------------------------------------
  // 退出登录确认 Dialog
  // ----------------------------------------------------------
  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text(
          'Are you sure you want to sign out of your merchant account?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      try {
        final service = ref.read(settingsServiceProvider);
        await service.signOut();
        if (context.mounted) {
          context.go('/auth/login');
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Sign out failed: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  // ----------------------------------------------------------
  // 升级为连锁确认弹窗
  // ----------------------------------------------------------
  Future<void> _showUpgradeDialog(BuildContext context, WidgetRef ref) async {
    // 预填品牌名为当前门店的公司名（#11）
    final storeInfo = ref.read(storeProvider).valueOrNull;
    final brandNameCtrl = TextEditingController(
      text: storeInfo?.companyName ?? storeInfo?.name ?? '',
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Upgrade to Chain'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Create a brand to manage multiple store locations. Your current store will be the first location.',
              style: TextStyle(fontSize: 14, color: Color(0xFF757575)),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey('settings_brand_name_field'),
              controller: brandNameCtrl,
              decoration: const InputDecoration(
                labelText: 'Brand Name',
                hintText: 'Enter your brand name',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            key: const ValueKey('settings_confirm_btn'),
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF6B35),
              foregroundColor: Colors.white,
            ),
            child: const Text('Create Brand'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      final brandName = brandNameCtrl.text.trim();
      if (brandName.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Brand name is required'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      try {
        final storeService = ref.read(storeServiceProvider);
        await storeService.createBrand(name: brandName);
        // 刷新门店信息以反映品牌关联
        ref.invalidate(storeProvider);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Brand created successfully!'),
              backgroundColor: Color(0xFF2E7D32),
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to create brand: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
    brandNameCtrl.dispose();
  }

  // ----------------------------------------------------------
  // 闭店确认弹窗
  // ----------------------------------------------------------
  Future<void> _confirmCloseStore(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Close Store'),
        content: const Text(
          'This will:\n'
          '• Set your store status to Closed\n'
          '• Deactivate all active deals\n'
          '• Trigger refunds for unused vouchers\n\n'
          'This action cannot be easily undone. Are you sure?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Close Store'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      try {
        final storeService = ref.read(storeServiceProvider);
        final pendingRefunds = await storeService.closeStore();
        ref.invalidate(storeProvider);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Store closed. $pendingRefunds vouchers pending refund.',
              ),
              backgroundColor: const Color(0xFF2E7D32),
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to close store: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  // ----------------------------------------------------------
  // 解除品牌合作确认弹窗
  // ----------------------------------------------------------
  Future<void> _confirmLeaveBrand(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave Brand'),
        content: const Text(
          'This will disconnect your store from the brand.\n\n'
          '• Your store will become independent\n'
          '• Multi-store deals will no longer apply here\n'
          '• You can rejoin a brand later\n\n'
          'Are you sure?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Leave Brand'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      try {
        final storeService = ref.read(storeServiceProvider);
        await storeService.leaveBrand();
        ref.invalidate(storeProvider);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Successfully left the brand.'),
              backgroundColor: Color(0xFF2E7D32),
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to leave brand: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  // ----------------------------------------------------------
  // 关于弹窗
  // ----------------------------------------------------------
  void _showAboutDialog(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: 'DealJoy Merchant',
      applicationVersion: '1.0.0',
      applicationLegalese: '© 2026 DealJoy Inc. All rights reserved.',
    );
  }
}

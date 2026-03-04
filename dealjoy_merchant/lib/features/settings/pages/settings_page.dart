// 商家设置主页面
// 结构: Profile 区块 / Account 分组（V2）/ Notifications / Support / Sign Out

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/settings_provider.dart';
import '../widgets/settings_section.dart';
import '../widgets/settings_tile.dart';

// ============================================================
// SettingsPage — 商家设置主入口（ConsumerWidget）
// ============================================================
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 通过 SettingsService 获取当前邮箱，避免直接访问 Supabase.instance
    // 测试环境中 Supabase 未初始化时仍可正常渲染
    final service = ref.watch(settingsServiceProvider);
    final email = service.currentUserEmail;

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
                onTap: () => context.push('/settings/account-security'),
              ),
              SettingsTile(
                icon: Icons.group_outlined,
                title: 'Staff Accounts',
                subtitle: 'Manage employee access',
                showDivider: false,
                onTap: () => context.push('/settings/staff'),
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
                onTap: () => context.push('/settings/notifications'),
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
                onTap: () => context.push('/settings/help'),
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
          context.go('/login');
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

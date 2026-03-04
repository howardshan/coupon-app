// 账号安全页面（V2 骨架）
// 当前版本: 显示当前邮箱 + Coming in V2 各入口占位
// V2 实现: 修改密码 / 绑定手机号 / 两步验证；修改后强制重新登录

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ============================================================
// AccountSecurityPage — 账号安全（V2 骨架，ConsumerWidget）
// ============================================================
class AccountSecurityPage extends ConsumerWidget {
  const AccountSecurityPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 读取当前登录邮箱（只读展示）
    final email =
        Supabase.instance.client.auth.currentUser?.email ?? 'Not signed in';

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text('Account Security'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A1A1A),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // --------------------------------------------------
          // 当前账号信息卡片
          // --------------------------------------------------
          _buildCurrentAccountCard(email),
          const SizedBox(height: 24),

          // --------------------------------------------------
          // V2 功能占位列表
          // --------------------------------------------------
          _buildV2PlaceholderCard(context),
          const SizedBox(height: 24),

          // --------------------------------------------------
          // V2 说明横幅
          // --------------------------------------------------
          _buildV2Banner(),
        ],
      ),
    );
  }

  // ----------------------------------------------------------
  // 当前账号信息卡片（邮箱只读）
  // ----------------------------------------------------------
  Widget _buildCurrentAccountCard(String email) {
    return Container(
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Current Account',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF6B7280),
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF6B35).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.email_outlined,
                  size: 20,
                  color: Color(0xFFFF6B35),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Email Address',
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF9CA3AF),
                      ),
                    ),
                    Text(
                      email,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF1A1A1A),
                      ),
                    ),
                  ],
                ),
              ),
              // 已验证标记
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'Verified',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.green,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------
  // V2 功能占位列表
  // ----------------------------------------------------------
  Widget _buildV2PlaceholderCard(BuildContext context) {
    final items = [
      (Icons.lock_reset_outlined, 'Change Password',
          'Update your login password'),
      (Icons.phone_outlined, 'Link Phone Number',
          'Add phone for account recovery'),
      (Icons.security_outlined, 'Two-Factor Authentication',
          'Add an extra layer of security'),
    ];

    return Container(
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
      child: Column(
        children: [
          for (int i = 0; i < items.length; i++) ...[
            _buildLockedTile(
              icon: items[i].$1,
              title: items[i].$2,
              subtitle: items[i].$3,
              context: context,
            ),
            if (i < items.length - 1)
              Divider(
                height: 1,
                indent: 64,
                color: Colors.grey.withValues(alpha: 0.15),
              ),
          ],
        ],
      ),
    );
  }

  // ----------------------------------------------------------
  // 单条锁定功能行（灰色 + V2 badge）
  // ----------------------------------------------------------
  Widget _buildLockedTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required BuildContext context,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 20, color: Colors.grey[400]),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey[400],
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                ),
              ],
            ),
          ),
          // V2 标记
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: Colors.orange.withValues(alpha: 0.3),
              ),
            ),
            child: const Text(
              'V2',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.orange,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------
  // V2 说明横幅
  // ----------------------------------------------------------
  Widget _buildV2Banner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFF6B35).withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFFF6B35).withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline,
            size: 20,
            color: const Color(0xFFFF6B35).withValues(alpha: 0.8),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Advanced security features are coming in V2. '
              'Stay tuned for updates!',
              style: TextStyle(
                fontSize: 13,
                color: Color(0xFFFF6B35),
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

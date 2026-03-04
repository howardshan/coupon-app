// 员工子账号页面（V2 骨架）
// 当前版本: 显示功能说明 + Coming in V2 placeholder
// V2 实现: 添加员工 / 分配角色（scan_only / full_access）/ 移除员工

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ============================================================
// StaffAccountsPage — 员工子账号（V2 骨架，ConsumerWidget）
// ============================================================
class StaffAccountsPage extends ConsumerWidget {
  const StaffAccountsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text('Staff Accounts'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A1A1A),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // --------------------------------------------------
            // Coming Soon 插图区域
            // --------------------------------------------------
            const SizedBox(height: 32),
            Center(
              child: Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: const Color(0xFFFF6B35).withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.group_outlined,
                  size: 48,
                  color: Color(0xFFFF6B35),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // 标题
            const Text(
              'Staff Accounts',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1A1A1A),
              ),
            ),
            const SizedBox(height: 12),

            // 说明文字
            Text(
              'Invite employees to help manage your store. '
              'Assign different permission levels to control what they can access.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[500],
                height: 1.6,
              ),
            ),
            const SizedBox(height: 32),

            // --------------------------------------------------
            // 功能预览卡片
            // --------------------------------------------------
            _buildFeatureCard(
              icon: Icons.qr_code_scanner,
              title: 'Scan Only',
              description:
                  'Staff can scan and redeem customer vouchers. '
                  'No access to orders, earnings, or settings.',
            ),
            const SizedBox(height: 12),
            _buildFeatureCard(
              icon: Icons.manage_accounts_outlined,
              title: 'Full Access',
              description:
                  'Full management access — same as the owner account, '
                  'excluding payment and staff management.',
            ),
            const SizedBox(height: 32),

            // --------------------------------------------------
            // V2 Coming Soon 按钮（禁用状态）
            // --------------------------------------------------
            ElevatedButton.icon(
              onPressed: null, // V2 前禁用
              icon: const Icon(Icons.person_add_outlined, size: 18),
              label: const Text('Invite Staff Member'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // V2 标记说明
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: Colors.orange.withValues(alpha: 0.3),
                    ),
                  ),
                  child: const Text(
                    'Coming in V2',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.orange,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'We are working on this feature',
                  style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ----------------------------------------------------------
  // 功能预览卡片
  // ----------------------------------------------------------
  Widget _buildFeatureCard({
    required IconData icon,
    required String title,
    required String description,
  }) {
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
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFFFF6B35).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 22, color: const Color(0xFFFF6B35)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[500],
                    height: 1.5,
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

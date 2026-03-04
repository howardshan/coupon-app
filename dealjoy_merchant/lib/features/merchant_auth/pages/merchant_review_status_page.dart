// 商家审核状态页
// 提交申请后显示 "Under Review"，显示提交时间和预计审核时间
// 审核被拒时显示原因和 "Edit & Resubmit" 按钮

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../router/app_router.dart';
import '../models/merchant_application.dart';
import '../providers/merchant_auth_provider.dart';

// ============================================================
// MerchantReviewStatusPage — 审核状态页（ConsumerWidget）
// ============================================================
class MerchantReviewStatusPage extends ConsumerStatefulWidget {
  const MerchantReviewStatusPage({super.key});

  @override
  ConsumerState<MerchantReviewStatusPage> createState() =>
      _MerchantReviewStatusPageState();
}

class _MerchantReviewStatusPageState
    extends ConsumerState<MerchantReviewStatusPage> {
  static const _primaryOrange = Color(0xFFFF6B35);
  static const _bgColor = Color(0xFFF8F9FA);

  @override
  void initState() {
    super.initState();
    // 进入页面时刷新状态（可能从 push 通知跳转过来）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 清除缓存，确保拿到最新状态
      MerchantStatusCache.clear();
      ref.read(merchantAuthProvider.notifier).refreshStatus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(merchantAuthProvider);

    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Application Status',
          style: TextStyle(
            color: Color(0xFF212121),
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
        actions: [
          // 手动刷新按钮
          IconButton(
            icon: const Icon(Icons.refresh, color: Color(0xFF212121)),
            onPressed: () {
              MerchantStatusCache.clear();
              ref.read(merchantAuthProvider.notifier).refreshStatus();
            },
          ),
        ],
      ),
      body: authState.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: _primaryOrange),
        ),
        error: (error, _) => _buildErrorState(error.toString()),
        data: (application) => _buildContent(application),
      ),
    );
  }

  // ----------------------------------------------------------
  // 根据申请状态构建不同内容
  // ----------------------------------------------------------
  Widget _buildContent(MerchantApplication? application) {
    if (application == null) {
      // 尚未提交申请
      return _buildNotSubmittedState();
    }

    switch (application.status) {
      case ApplicationStatus.pending:
        return _buildPendingState(application);
      case ApplicationStatus.approved:
        return _buildApprovedState(application);
      case ApplicationStatus.rejected:
        return _buildRejectedState(application);
    }
  }

  // ----------------------------------------------------------
  // 审核中状态
  // ----------------------------------------------------------
  Widget _buildPendingState(MerchantApplication application) {
    final submittedAt = application.submittedAt;
    final dateStr = submittedAt != null
        ? DateFormat('MMM d, yyyy · h:mm a').format(submittedAt.toLocal())
        : 'Just now';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 40),

          // 插图图标
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: _primaryOrange.withAlpha(25),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.hourglass_top_rounded,
              size: 64,
              color: _primaryOrange,
            ),
          ),
          const SizedBox(height: 32),

          // 标题
          const Text(
            'Application Under Review',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: Color(0xFF212121),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),

          // 说明文字
          const Text(
            'Our team is reviewing your application.\nWe\'ll notify you via email once a decision is made.',
            style: TextStyle(
              fontSize: 15,
              color: Color(0xFF757575),
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),

          // 时间信息卡片
          _InfoCard(
            children: [
              _InfoRow(
                icon: Icons.schedule,
                label: 'Submitted',
                value: dateStr,
              ),
              const Divider(height: 24),
              _InfoRow(
                icon: Icons.timer_outlined,
                label: 'Expected Review Time',
                value: '24–48 hours',
              ),
            ],
          ),
          const SizedBox(height: 24),

          // 提示文字
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue.shade600, size: 20),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'You can close the app and come back. We\'ll send you an email when your application is reviewed.',
                    style: TextStyle(
                      fontSize: 13,
                      color: Color(0xFF1565C0),
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),

          // 退出登录按钮
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              onPressed: () async {
                final router = GoRouter.of(context);
                await ref.read(merchantAuthProvider.notifier).signOut();
                if (mounted) {
                  router.go('/auth/login');
                }
              },
              icon: const Icon(Icons.logout, size: 18),
              label: const Text(
                'Sign Out',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF757575),
                side: const BorderSide(color: Color(0xFFE0E0E0)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------
  // 审核通过状态
  // ----------------------------------------------------------
  Widget _buildApprovedState(MerchantApplication application) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 40),

          // 通过图标
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.check_circle_rounded,
              size: 64,
              color: Colors.green.shade600,
            ),
          ),
          const SizedBox(height: 32),

          Text(
            'You\'re Approved!',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: Colors.green.shade700,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          const Text(
            'Welcome to DealJoy! Your merchant account is now active. Start creating deals and reaching customers.',
            style: TextStyle(
              fontSize: 15,
              color: Color(0xFF757575),
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 40),

          // 进入仪表盘按钮
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: () {
                // 跳转到商家仪表盘（清除缓存让 redirect 重新检查状态）
                MerchantStatusCache.clear();
                GoRouter.of(context).go('/dashboard');
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryOrange,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'Go to Dashboard',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------
  // 审核被拒状态（显示原因 + 重新提交按钮）
  // ----------------------------------------------------------
  Widget _buildRejectedState(MerchantApplication application) {
    final rejectionReason = application.rejectionReason ??
        'Your application did not meet our requirements.';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 40),

          // 被拒图标
          Container(
            width: 120,
            height: 120,
            decoration: const BoxDecoration(
              color: Color(0xFFFFEBEE),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.cancel_rounded,
              size: 64,
              color: Color(0xFFD32F2F),
            ),
          ),
          const SizedBox(height: 32),

          const Text(
            'Application Not Approved',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: Color(0xFF212121),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          const Text(
            'Don\'t worry — you can update your information and resubmit.',
            style: TextStyle(
              fontSize: 15,
              color: Color(0xFF757575),
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),

          // 拒绝原因卡片
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFFFEBEE),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFEF9A9A)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: Color(0xFFD32F2F),
                      size: 20,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Reason for Rejection',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFD32F2F),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  rejectionReason,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF212121),
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),

          // Edit & Resubmit 按钮
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: () {
                // 跳转到注册页（预填已有数据）
                GoRouter.of(context).go('/auth/register');
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryOrange,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'Edit & Resubmit',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 联系支持
          TextButton(
            onPressed: () {
              // 打开帮助/联系页面（后续 Sprint 实现）
            },
            child: const Text(
              'Contact Support',
              style: TextStyle(
                color: Color(0xFF757575),
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------
  // 未提交状态（理论上不应出现，做保护）
  // ----------------------------------------------------------
  Widget _buildNotSubmittedState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.assignment_outlined,
              size: 64,
              color: Color(0xFFBDBDBD),
            ),
            const SizedBox(height: 24),
            const Text(
              'No Application Found',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: Color(0xFF212121),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'You haven\'t submitted a merchant application yet.',
              style: TextStyle(color: Color(0xFF757575)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: () {
                GoRouter.of(context).go('/auth/register');
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6B35),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('Start Application'),
            ),
          ],
        ),
      ),
    );
  }

  // ----------------------------------------------------------
  // 错误状态
  // ----------------------------------------------------------
  Widget _buildErrorState(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.wifi_off_rounded,
              size: 64,
              color: Color(0xFFBDBDBD),
            ),
            const SizedBox(height: 24),
            const Text(
              'Something went wrong',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Color(0xFF212121),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              message,
              style: const TextStyle(color: Color(0xFF9E9E9E)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () {
                ref.read(merchantAuthProvider.notifier).refreshStatus();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6B35),
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// 信息卡片（私有组件）
// ============================================================
class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(13),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

// ============================================================
// 单行信息展示（私有组件）
// ============================================================
class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: const Color(0xFF9E9E9E)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF9E9E9E),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF212121),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

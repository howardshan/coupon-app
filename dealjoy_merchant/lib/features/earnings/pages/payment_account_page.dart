// 收款账户页面
// 展示 Stripe Connect 账户状态
// V1: 仅显示状态，OAuth 流程 V2 实现

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/earnings_data.dart';
import '../providers/earnings_provider.dart';

// =============================================================
// PaymentAccountPage — 收款账户状态页（ConsumerWidget）
// =============================================================
class PaymentAccountPage extends ConsumerWidget {
  const PaymentAccountPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stripeAsync = ref.watch(stripeAccountProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: _buildAppBar(context),
      body: stripeAsync.when(
        loading: () => _buildLoading(),
        error:   (err, st) => _buildError(context, ref, err),
        data:    (info) => _buildContent(context, ref, info),
      ),
    );
  }

  // ----------------------------------------------------------
  // AppBar
  // ----------------------------------------------------------
  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new, size: 18),
        color: const Color(0xFF1A1A2E),
        onPressed: () => Navigator.of(context).pop(),
      ),
      title: const Text(
        'Payment Account',
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: Color(0xFF1A1A2E),
        ),
      ),
    );
  }

  // ----------------------------------------------------------
  // 主内容
  // ----------------------------------------------------------
  Widget _buildContent(
    BuildContext context,
    WidgetRef ref,
    StripeAccountInfo info,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 顶部说明区
          _InfoBanner(isConnected: info.isConnected),
          const SizedBox(height: 20),

          // 账户状态卡片
          _AccountStatusCard(info: info),
          const SizedBox(height: 20),

          // 操作按钮区
          _ActionButtons(
            isConnected: info.isConnected,
            onConnectTap: () => _showComingSoonTip(context, 'Connect Stripe Account'),
            onManageTap:  () => _showComingSoonTip(context, 'Manage on Stripe'),
            onDisconnectTap: () => _showDisconnectConfirm(context),
          ),
          const SizedBox(height: 24),

          // 结算说明
          _SettlementExplainer(),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // ----------------------------------------------------------
  // 加载中骨架屏
  // ----------------------------------------------------------
  Widget _buildLoading() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: List.generate(
          3,
          (i) => Container(
            margin: const EdgeInsets.only(bottom: 16),
            height: i == 0 ? 80 : 120,
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
    );
  }

  // ----------------------------------------------------------
  // 错误状态
  // ----------------------------------------------------------
  Widget _buildError(BuildContext context, WidgetRef ref, Object err) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined, size: 56, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              'Failed to load account info',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => ref.invalidate(stripeAccountProvider),
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6B35),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ----------------------------------------------------------
  // V1 提示：功能即将上线
  // ----------------------------------------------------------
  void _showComingSoonTip(BuildContext context, String action) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$action — coming soon!'),
        backgroundColor: const Color(0xFFFF6B35),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // ----------------------------------------------------------
  // 断开连接确认对话框（V1 仅提示）
  // ----------------------------------------------------------
  Future<void> _showDisconnectConfirm(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Disconnect Stripe'),
        content: const Text(
          'Disconnecting your Stripe account will pause all payouts. '
          'This feature will be available in the next update.',
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

// =============================================================
// _InfoBanner — 顶部状态说明横幅
// =============================================================
class _InfoBanner extends StatelessWidget {
  final bool isConnected;

  const _InfoBanner({required this.isConnected});

  @override
  Widget build(BuildContext context) {
    if (isConnected) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF4CAF50).withAlpha(20),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: const Color(0xFF4CAF50).withAlpha(60),
          ),
        ),
        child: Row(
          children: [
            const Icon(Icons.check_circle, color: Color(0xFF4CAF50), size: 20),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Your Stripe account is connected. Payouts are processed T+7 days after redemption.',
                style: TextStyle(
                  fontSize: 13,
                  color: Color(0xFF2E7D32),
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFF9800).withAlpha(20),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFFF9800).withAlpha(60),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_outlined, color: Color(0xFFFF9800), size: 20),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Connect your Stripe account to start receiving payouts from DealJoy.',
              style: TextStyle(
                fontSize: 13,
                color: Color(0xFFE65100),
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================
// _AccountStatusCard — 账户详情卡片
// =============================================================
class _AccountStatusCard extends StatelessWidget {
  final StripeAccountInfo info;

  const _AccountStatusCard({required this.info});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(8),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题行
          Row(
            children: [
              // Stripe 品牌色图标
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFF635BFF).withAlpha(20),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.credit_card_outlined,
                  color: Color(0xFF635BFF),
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Stripe Connect',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1A1A2E),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Payout partner for DealJoy',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ),
              // 连接状态 badge
              _StatusBadge(status: info.accountStatus),
            ],
          ),

          if (info.isConnected) ...[
            const SizedBox(height: 20),
            Divider(height: 1, color: Colors.grey.shade100),
            const SizedBox(height: 16),
            // 账户信息行
            if (info.accountEmail != null)
              _InfoRow(
                label: 'Account Email',
                value: info.accountEmail!,
                icon: Icons.email_outlined,
              ),
            if (info.accountDisplayId != null) ...[
              const SizedBox(height: 10),
              _InfoRow(
                label: 'Account ID',
                value: info.accountDisplayId!,
                icon: Icons.fingerprint_outlined,
              ),
            ],
          ] else ...[
            const SizedBox(height: 16),
            Text(
              'No Stripe account connected',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade500,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// 账户状态 badge
class _StatusBadge extends StatelessWidget {
  final String status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final (color, label) = _resolve(status);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withAlpha(60)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  (Color, String) _resolve(String status) {
    switch (status) {
      case 'connected':
        return (const Color(0xFF4CAF50), 'Connected');
      case 'restricted':
        return (const Color(0xFFFF9800), 'Restricted');
      default:
        return (Colors.grey, 'Not Connected');
    }
  }
}

// 信息行（label + value）
class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _InfoRow({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey.shade400),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
              ),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF1A1A2E),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// =============================================================
// _ActionButtons — 操作按钮区
// =============================================================
class _ActionButtons extends StatelessWidget {
  final bool isConnected;
  final VoidCallback onConnectTap;
  final VoidCallback onManageTap;
  final VoidCallback onDisconnectTap;

  const _ActionButtons({
    required this.isConnected,
    required this.onConnectTap,
    required this.onManageTap,
    required this.onDisconnectTap,
  });

  @override
  Widget build(BuildContext context) {
    if (isConnected) {
      // 已连接：显示 Manage + Disconnect
      return Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onManageTap,
              icon: const Icon(Icons.open_in_new, size: 16),
              label: const Text('Manage on Stripe'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF635BFF),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: onDisconnectTap,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.grey.shade600,
                side: BorderSide(color: Colors.grey.shade300),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('Disconnect Account'),
            ),
          ),
        ],
      );
    }

    // 未连接：显示 Connect 按钮
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onConnectTap,
        icon: const Icon(Icons.link, size: 18),
        label: const Text('Connect Stripe Account'),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFFF6B35),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }
}

// =============================================================
// _SettlementExplainer — 结算规则说明区
// =============================================================
class _SettlementExplainer extends StatelessWidget {
  const _SettlementExplainer();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(8),
            blurRadius: 6,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'How Payouts Work',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1A1A2E),
            ),
          ),
          const SizedBox(height: 12),
          ..._steps.map((step) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 22,
                      height: 22,
                      decoration: const BoxDecoration(
                        color: Color(0xFFFF6B35),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          '${_steps.indexOf(step) + 1}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        step,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade700,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  static const List<String> _steps = [
    'Customer purchases a deal and pays via Stripe.',
    'Customer redeems the voucher at your store.',
    'DealJoy processes settlement T+7 days after redemption.',
    'Net amount (85% of deal price) is transferred to your Stripe account.',
  ];
}

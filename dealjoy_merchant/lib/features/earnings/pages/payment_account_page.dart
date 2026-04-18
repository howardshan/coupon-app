// 收款账户页面
// 实现 Stripe Connect Express 账户绑定、状态刷新、Dashboard 管理

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../store/models/store_info.dart';
import '../../store/providers/store_provider.dart';
import '../models/earnings_data.dart';
import '../providers/earnings_provider.dart';
import '../services/earnings_service.dart';
import '../widgets/stripe_unlink_status_banner.dart';

// =============================================================
// PaymentAccountPage — 收款账户页（ConsumerStatefulWidget）
// 支持 Stripe Connect Express onboarding、状态刷新、Dashboard 管理
// =============================================================
class PaymentAccountPage extends ConsumerStatefulWidget {
  const PaymentAccountPage({super.key});

  @override
  ConsumerState<PaymentAccountPage> createState() => _PaymentAccountPageState();
}

class _PaymentAccountPageState extends ConsumerState<PaymentAccountPage> {
  // 按钮操作中的加载状态
  bool _isConnecting = false;
  bool _isRefreshing = false;
  bool _isOpeningDashboard = false;

  @override
  Widget build(BuildContext context) {
    final stripeAsync = ref.watch(stripeAccountProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: _buildAppBar(),
      body: stripeAsync.when(
        loading: () => _buildLoading(),
        error:   (err, st) => _buildError(err),
        data:    (info) => _buildContent(info),
      ),
    );
  }

  // ----------------------------------------------------------
  // AppBar
  // ----------------------------------------------------------
  PreferredSizeWidget _buildAppBar() {
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
  Widget _buildContent(StripeAccountInfo info) {
    final store         = ref.watch(storeProvider).valueOrNull;
    final canUnlink     = _canRequestMerchantUnlink(store);
    final unlinkAsync   = ref.watch(stripeUnlinkRequestsMerchantProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _InfoBanner(isConnected: info.isConnected),
          const SizedBox(height: 20),

          _AccountStatusCard(info: info),
          const SizedBox(height: 20),

          unlinkAsync.when(
            data:   (items) {
              if (items.isEmpty) {
                return const SizedBox.shrink();
              }
              return Column(
                children: [
                  StripeUnlinkRequestStatusBanner(items: items),
                  const SizedBox(height: 20),
                ],
              );
            },
            loading: () => const SizedBox.shrink(),
            error:   (e, _) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  'Could not load unlink request status. Try again later.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.orange.shade800,
                  ),
                ),
              );
            },
          ),

          // 操作按钮区
          _ActionButtons(
            isConnected:     info.isConnected,
            isConnecting:    _isConnecting,
            isOpeningDashboard: _isOpeningDashboard,
            canRequestUnlink:  info.isConnected && canUnlink,
            onConnectTap:    _handleConnect,
            onManageTap:     _handleManage,
            onRequestUnlinkTap: _handleRequestUnlink,
            onUnlinkingPolicyTap: _showUnlinkingPolicyDialog,
          ),
          if (info.isConnected && !canUnlink) ...[
            const SizedBox(height: 8),
            Text(
              'Only the store owner or brand owner can submit a Stripe disconnect request for this store.',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
                height: 1.3,
              ),
            ),
          ],
          const SizedBox(height: 16),

          // Refresh Status 按钮（onboarding 完成后点击同步）
          _RefreshStatusButton(
            isRefreshing: _isRefreshing,
            onTap: _handleRefreshStatus,
          ),
          const SizedBox(height: 24),

          const _SettlementExplainer(),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // ----------------------------------------------------------
  // 点击 "Connect Stripe Account" — 跳转到 Stripe onboarding
  // ----------------------------------------------------------
  Future<void> _handleConnect() async {
    setState(() => _isConnecting = true);
    try {
      final service = ref.read(earningsServiceProvider);
      final url = await service.fetchStripeConnectUrl();
      final uri = Uri.parse(url);
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        if (mounted) _showError('Could not open Stripe. Please try again.');
      }
    } on Exception catch (e) {
      if (mounted) _showError(e.toString());
    } finally {
      if (mounted) setState(() => _isConnecting = false);
    }
  }

  // ----------------------------------------------------------
  // 点击 "Refresh Status" — 同步 Stripe 账户状态后刷新页面
  // ----------------------------------------------------------
  Future<void> _handleRefreshStatus() async {
    setState(() => _isRefreshing = true);
    try {
      final service = ref.read(earningsServiceProvider);
      await service.refreshStripeAccountStatus();
      // 刷新 stripeAccountProvider，重新加载页面
      ref.invalidate(stripeAccountProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Account status updated'),
            backgroundColor: const Color(0xFF4CAF50),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      _invalidateStripeIfUnlinkedError(e);
      if (mounted) _showError(e.toString());
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  // ----------------------------------------------------------
  // 点击 "Manage on Stripe" — 打开 Stripe Express Dashboard
  // ----------------------------------------------------------
  Future<void> _handleManage() async {
    setState(() => _isOpeningDashboard = true);
    try {
      final service = ref.read(earningsServiceProvider);
      final url = await service.fetchStripeManageUrl();
      final uri = Uri.parse(url);
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        if (mounted) _showError('Could not open Stripe Dashboard. Please try again.');
      }
    } catch (e) {
      _invalidateStripeIfUnlinkedError(e);
      if (mounted) _showError(e.toString());
    } finally {
      if (mounted) setState(() => _isOpeningDashboard = false);
    }
  }

  /// 服务端已无 Stripe 账户但本页仍显示已连接时，重拉 merchant-earnings/account
  void _invalidateStripeIfUnlinkedError(Object e) {
    if (e.toString().contains('No Stripe account linked')) {
      ref.invalidate(stripeAccountProvider);
    }
  }

  // 与 Edge 一致：仅 store_owner / brand_owner 可提交
  static bool _canRequestMerchantUnlink(StoreInfo? s) {
    if (s == null) {
      return false;
    }
    return s.currentRole == 'store_owner' || s.currentRole == 'brand_owner';
  }

  // 提交解绑申请（单店/门店维度 subject_type=merchant）
  Future<void> _handleRequestUnlink() async {
    final existing = ref.read(stripeUnlinkRequestsMerchantProvider).valueOrNull;
    if (existing != null) {
      final p = existing.where((e) => e.status == 'pending').isNotEmpty;
      if (p) {
        _showError('A request is already pending. Please wait for a decision.');
        return;
      }
    }

    final r = await showStripeUnlinkRequestSheet(
      context,
      title: 'Request to Unlink Stripe',
      subtitle: 'We will review your request. You will get an email when there is an update. '
          'A pending in-flight withdrawal must be completed first.',
    );
    if (!mounted) {
      return;
    }
    if (r == null || r.cancel) {
      return;
    }

    try {
      final service = ref.read(earningsServiceProvider);
      await service.submitStripeUnlinkRequest(
        subjectType:  'merchant',
        requestNote:  r.note,
      );
      if (!mounted) {
        return;
      }
      ref.invalidate(stripeAccountProvider);
      ref.invalidate(stripeUnlinkRequestsMerchantProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Request submitted. Check your email for next steps.'),
          backgroundColor: const Color(0xFF4CAF50),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          duration: const Duration(seconds: 3),
        ),
      );
    } on EarningsException catch (e) {
      if (mounted) {
        _showError(e.message);
      }
    } catch (e) {
      if (mounted) {
        _showError(e.toString());
      }
    }
  }

  Future<void> _showUnlinkingPolicyDialog() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unlinking Stripe on DealJoy'),
        content: const Text(
          'Disconnecting a payout account is a manual, reviewed process. '
          'If your store is under a brand-level Stripe account, a brand owner must request '
          'disconnect on the brand Stripe page. If you are not the owner, ask your owner to submit. '
          'After our team processes an approved request, use Refresh Status on this screen to sync.',
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
  Widget _buildError(Object err) {
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
  // 错误提示 SnackBar
  // ----------------------------------------------------------
  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        duration: const Duration(seconds: 4),
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
// _ActionButtons — 操作按钮区（支持 loading 状态）
// =============================================================
class _ActionButtons extends StatelessWidget {
  final bool isConnected;
  final bool isConnecting;
  final bool isOpeningDashboard;
  /// 当前用户是否可看到「申请解绑」主按钮
  final bool canRequestUnlink;
  final VoidCallback onConnectTap;
  final VoidCallback onManageTap;
  final VoidCallback onRequestUnlinkTap;
  final VoidCallback onUnlinkingPolicyTap;

  const _ActionButtons({
    required this.isConnected,
    required this.isConnecting,
    required this.isOpeningDashboard,
    required this.canRequestUnlink,
    required this.onConnectTap,
    required this.onManageTap,
    required this.onRequestUnlinkTap,
    required this.onUnlinkingPolicyTap,
  });

  @override
  Widget build(BuildContext context) {
    if (isConnected) {
      // 已连接：Manage + 解绑/政策
      return Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: isOpeningDashboard ? null : onManageTap,
              icon: isOpeningDashboard
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.open_in_new, size: 16),
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
          if (canRequestUnlink) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: onRequestUnlinkTap,
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF635BFF),
                  side: const BorderSide(color: Color(0xFF635BFF)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text('Request to Unlink Stripe'),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: onUnlinkingPolicyTap,
              child: const Text('How does unlinking work?'),
            ),
          ),
        ],
      );
    }

    // 未连接：显示 Connect 按钮
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: isConnecting ? null : onConnectTap,
        icon: isConnecting
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.link, size: 18),
        label: Text(isConnecting ? 'Opening Stripe...' : 'Connect Stripe Account'),
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
// _RefreshStatusButton — 刷新账户状态按钮
// 商家完成 Stripe onboarding 后点击，同步最新状态
// =============================================================
class _RefreshStatusButton extends StatelessWidget {
  final bool isRefreshing;
  final VoidCallback onTap;

  const _RefreshStatusButton({
    required this.isRefreshing,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: isRefreshing ? null : onTap,
        icon: isRefreshing
            ? SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.grey.shade500,
                ),
              )
            : const Icon(Icons.sync, size: 16),
        label: Text(isRefreshing ? 'Refreshing...' : 'Refresh Status'),
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.grey.shade600,
          side: BorderSide(color: Colors.grey.shade300),
          padding: const EdgeInsets.symmetric(vertical: 12),
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

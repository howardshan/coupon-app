// 品牌 Stripe Connect 页面
// 未连接时显示大图标 + 说明文字 + 连接按钮
// 已连接时显示账户信息 + Dashboard 按钮 + 刷新状态按钮

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_branding.dart';
import '../../earnings/providers/earnings_provider.dart';
import '../../earnings/services/earnings_service.dart';
import '../../earnings/widgets/stripe_unlink_status_banner.dart';
import '../models/brand_earnings_data.dart';
import '../providers/brand_earnings_provider.dart';
import '../providers/store_provider.dart';

// =============================================================
// BrandStripeConnectPage — 品牌 Stripe Connect 页面
// =============================================================
class BrandStripeConnectPage extends ConsumerStatefulWidget {
  const BrandStripeConnectPage({super.key});

  @override
  ConsumerState<BrandStripeConnectPage> createState() =>
      _BrandStripeConnectPageState();
}

class _BrandStripeConnectPageState
    extends ConsumerState<BrandStripeConnectPage> {
  bool _isConnecting = false;
  bool _isRefreshing = false;
  bool _isOpeningDashboard = false;

  @override
  Widget build(BuildContext context) {
    final stripeAsync = ref.watch(brandStripeAccountProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: _buildAppBar(),
      body: stripeAsync.when(
        loading: () => _buildLoading(),
        error: (e, _) => _buildError(e),
        data: (info) => _buildContent(info),
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
        'Brand Stripe Connect',
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
  Widget _buildContent(BrandStripeAccount info) {
    final store   = ref.watch(storeProvider).valueOrNull;
    final brand   = ref.watch(stripeUnlinkRequestsBrandProvider);
    final isOwner = store != null && store.currentRole == 'brand_owner';
    // 与 Edge 一致：仅 brand owner 可提交品牌维度的解绑申请
    final canUnlink = info.isConnected && isOwner;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 状态说明横幅
          _InfoBanner(isConnected: info.isConnected),
          const SizedBox(height: 20),

          // 账户详情卡片
          _AccountCard(info: info),
          const SizedBox(height: 20),

          // 解绑申请状态
          brand.when(
            data:   (items) {
              if (items.isEmpty) {
                return const SizedBox.shrink();
              }
              return Column(
                children: [
                  StripeUnlinkRequestStatusBanner(
                    items:             items,
                    isStripeConnected: info.isConnected,
                  ),
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

          // 操作按钮
          if (info.isConnected) ...[
            // 已连接：打开 Dashboard
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isOpeningDashboard ? null : _handleOpenDashboard,
                icon: _isOpeningDashboard
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.open_in_new, size: 16),
                label: const Text('Open Dashboard'),
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
            if (canUnlink) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _handleRequestBrandUnlink,
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
            if (info.isConnected && !isOwner) ...[
              const SizedBox(height: 8),
              Text(
                'Only the brand owner can request to disconnect the brand-level Stripe account.',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                  height: 1.3,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Center(
              child: TextButton(
                onPressed: _showUnlinkingPolicy,
                child: const Text('How does unlinking work?'),
              ),
            ),
          ] else ...[
            // 未连接：Connect 按钮
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isConnecting ? null : _handleConnect,
                icon: _isConnecting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.link, size: 18),
                label: Text(
                  _isConnecting
                      ? 'Opening Stripe...'
                      : 'Connect Stripe Account',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF6B35),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),

          // 刷新状态按钮（始终显示）
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _isRefreshing ? null : _handleRefreshStatus,
              icon: _isRefreshing
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.grey.shade500,
                      ),
                    )
                  : const Icon(Icons.sync, size: 16),
              label: Text(_isRefreshing ? 'Refreshing...' : 'Refresh Status'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.grey.shade600,
                side: BorderSide(color: Colors.grey.shade300),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // 说明区块
          const _HowItWorks(),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // ----------------------------------------------------------
  // 点击 "Connect Stripe Account"
  // ----------------------------------------------------------
  Future<void> _handleConnect() async {
    setState(() => _isConnecting = true);
    try {
      final service = ref.read(brandEarningsServiceProvider);
      final url = await service.fetchStripeConnectUrl();
      final uri = Uri.parse(url);
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        if (mounted) _showError('Could not open Stripe. Please try again.');
      }
    } catch (e) {
      if (mounted) _showError(e.toString());
    } finally {
      if (mounted) setState(() => _isConnecting = false);
    }
  }

  // ----------------------------------------------------------
  // 点击 "Refresh Status"
  // ----------------------------------------------------------
  Future<void> _handleRefreshStatus() async {
    setState(() => _isRefreshing = true);
    try {
      final service = ref.read(brandEarningsServiceProvider);
      await service.refreshStripeStatus();
      ref.invalidate(brandStripeAccountProvider);
      ref.invalidate(stripeUnlinkRequestsBrandProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Account status updated'),
            backgroundColor: const Color(0xFF4CAF50),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      _invalidateBrandStripeIfUnlinkedError(e);
      if (!mounted) {
        return;
      }
      final friendly = _friendlyMessageForNoStripeError(e);
      if (friendly != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendly),
            backgroundColor: const Color(0xFF546E7A),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            duration: const Duration(seconds: 4),
          ),
        );
      } else {
        _showError(e.toString());
      }
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  String? _friendlyMessageForNoStripeError(Object e) {
    final s = e.toString();
    if (s.contains('No Stripe account linked') ||
        s.contains('connect first') ||
        s.contains('Please connect')) {
      return 'No Stripe account is connected. Connect when you are ready to receive payouts.';
    }
    return null;
  }

  void _invalidateBrandStripeIfUnlinkedError(Object e) {
    final s = e.toString();
    if (s.contains('No Stripe account linked') ||
        s.contains('connect first') ||
        s.contains('Please connect')) {
      ref.invalidate(brandStripeAccountProvider);
      ref.invalidate(stripeUnlinkRequestsBrandProvider);
    }
  }

  // ----------------------------------------------------------
  // 点击 "Open Dashboard"
  // ----------------------------------------------------------
  Future<void> _handleOpenDashboard() async {
    setState(() => _isOpeningDashboard = true);
    try {
      final service = ref.read(brandEarningsServiceProvider);
      final url = await service.fetchStripeDashboardUrl();
      final uri = Uri.parse(url);
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        if (mounted) {
          _showError('Could not open Stripe Dashboard. Please try again.');
        }
      }
    } catch (e) {
      _invalidateBrandStripeIfUnlinkedError(e);
      if (!mounted) {
        return;
      }
      final friendly = _friendlyMessageForNoStripeError(e);
      if (friendly != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendly),
            backgroundColor: const Color(0xFF546E7A),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            duration: const Duration(seconds: 4),
          ),
        );
      } else {
        _showError(e.toString());
      }
    } finally {
      if (mounted) setState(() => _isOpeningDashboard = false);
    }
  }

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
              onPressed: () => ref.invalidate(brandStripeAccountProvider),
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

  // 品牌维度解绑：subject_type=brand（仅 brand owner）
  Future<void> _handleRequestBrandUnlink() async {
    final existing = ref.read(stripeUnlinkRequestsBrandProvider).valueOrNull;
    if (existing != null) {
      if (existing.any((e) => e.status == 'pending')) {
        _showError('A request is already pending. Please wait for a decision.');
        return;
      }
    }

    final r = await showStripeUnlinkRequestSheet(
      context,
      title: 'Request to Unlink Brand Stripe',
      subtitle: 'We will review your request. The brand owner is notified by email. '
          'A pending in-flight withdrawal on this store must be completed first.',
    );
    if (!mounted) {
      return;
    }
    if (r == null || r.cancel) {
      return;
    }
    try {
      await ref.read(earningsServiceProvider).submitStripeUnlinkRequest(
            subjectType:  'brand',
            requestNote:  r.note,
          );
      if (!mounted) {
        return;
      }
      ref.invalidate(brandStripeAccountProvider);
      ref.invalidate(stripeUnlinkRequestsBrandProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Request submitted. Check your email for next steps.'),
          backgroundColor: const Color(0xFF4CAF50),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
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

  Future<void> _showUnlinkingPolicy() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Unlinking brand Stripe on ${AppBranding.displayName}'),
        content: Text(
          'Only the brand owner can request to disconnect a brand-level Stripe account. '
          'Requests are reviewed by ${AppBranding.displayName}. You will get an email when a decision is made. '
          'If approved, the platform unlinks the account; then use Refresh Status to sync. '
          'In-flight withdrawals must finish before a new request can be processed in some cases.',
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
          border: Border.all(color: const Color(0xFF4CAF50).withAlpha(60)),
        ),
        child: const Row(
          children: [
            Icon(Icons.check_circle, color: Color(0xFF4CAF50), size: 20),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Your brand Stripe account is connected. Brand earnings will be paid out directly.',
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
        border: Border.all(color: const Color(0xFFFF9800).withAlpha(60)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_outlined,
              color: Color(0xFFFF9800), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Connect a Stripe account to receive brand commission payouts from ${AppBranding.displayName}.',
              style: const TextStyle(
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
// _AccountCard — 账户详情卡片
// =============================================================
class _AccountCard extends StatelessWidget {
  final BrandStripeAccount info;

  const _AccountCard({required this.info});

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
          Row(
            children: [
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
                      'Brand Stripe Connect',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1A1A2E),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Brand-level payout account',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                    ),
                  ],
                ),
              ),
              _StatusBadge(status: info.accountStatus),
            ],
          ),
          if (info.isConnected) ...[
            const SizedBox(height: 20),
            Divider(height: 1, color: Colors.grey.shade100),
            const SizedBox(height: 16),
            if (info.accountEmail != null)
              _InfoRow(
                label: 'Account Email',
                value: info.accountEmail!,
                icon: Icons.email_outlined,
              ),
            if (info.accountId != null) ...[
              const SizedBox(height: 10),
              _InfoRow(
                label: 'Account ID',
                value: info.accountId!,
                icon: Icons.fingerprint_outlined,
              ),
            ],
          ] else ...[
            const SizedBox(height: 16),
            Text(
              'No Stripe account connected',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
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

// 信息行
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
// _HowItWorks — 品牌收款说明区块
// =============================================================
class _HowItWorks extends StatelessWidget {
  const _HowItWorks();

  @override
  Widget build(BuildContext context) {
    final steps = <String>[
      'Customer purchases a brand deal at any of your locations.',
      'Store scans and redeems the voucher.',
      '${AppBranding.displayName} calculates brand commission from the redemption amount.',
      'Brand commission is settled and transferred to this Stripe account.',
    ];
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
            'How Brand Payouts Work',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1A1A2E),
            ),
          ),
          const SizedBox(height: 12),
          ...steps.asMap().entries.map(
                (entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 22,
                        height: 22,
                        decoration: const BoxDecoration(
                          color: Color(0xFF635BFF),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            '${entry.key + 1}',
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
                          entry.value,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade700,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

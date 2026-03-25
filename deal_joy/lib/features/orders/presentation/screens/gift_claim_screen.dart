// 受赠方 App 内领取礼品券页面
// 通过 deep link crunchyplum://gift?token=xxx 打开，调用 claim-gift Edge Function 完成绑定

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/theme/app_colors.dart';

// 领取结果数据结构
class _ClaimResult {
  final String dealTitle;
  final String merchantName;
  final String couponCode;
  final String? expiresAt;

  const _ClaimResult({
    required this.dealTitle,
    required this.merchantName,
    required this.couponCode,
    this.expiresAt,
  });
}

// 领取状态枚举
enum _ClaimStatus { loading, success, recalled, expired, error }

class GiftClaimScreen extends ConsumerStatefulWidget {
  final String claimToken;

  const GiftClaimScreen({super.key, required this.claimToken});

  @override
  ConsumerState<GiftClaimScreen> createState() => _GiftClaimScreenState();
}

class _GiftClaimScreenState extends ConsumerState<GiftClaimScreen> {
  _ClaimStatus _status = _ClaimStatus.loading;
  _ClaimResult? _result;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _claimGift();
  }

  // 调用 claim-gift Edge Function 领取礼品券
  Future<void> _claimGift() async {
    if (widget.claimToken.isEmpty) {
      setState(() {
        _status = _ClaimStatus.error;
        _errorMessage = 'Invalid gift link. Please check the link and try again.';
      });
      return;
    }

    try {
      final client = Supabase.instance.client;
      final response = await client.functions.invoke(
        'claim-gift',
        body: {'claim_token': widget.claimToken},
      );

      final data = response.data as Map<String, dynamic>?;

      if (data == null) {
        setState(() {
          _status = _ClaimStatus.error;
          _errorMessage = 'Something went wrong. Please try again.';
        });
        return;
      }

      // 解析 Edge Function 返回的状态
      final resultStatus = data['status'] as String? ?? '';

      switch (resultStatus) {
        case 'success':
          final coupon = data['coupon'] as Map<String, dynamic>? ?? {};
          final deal = coupon['deal'] as Map<String, dynamic>? ?? {};
          final merchant = deal['merchant'] as Map<String, dynamic>? ?? {};
          setState(() {
            _status = _ClaimStatus.success;
            _result = _ClaimResult(
              dealTitle: deal['title'] as String? ?? 'Gift',
              merchantName: merchant['name'] as String? ?? '',
              couponCode: coupon['qr_code'] as String? ?? '',
              expiresAt: coupon['expires_at'] as String?,
            );
          });
        case 'recalled':
          setState(() => _status = _ClaimStatus.recalled);
        case 'expired':
          setState(() => _status = _ClaimStatus.expired);
        default:
          // 处理 Edge Function 返回的错误消息
          final message = data['message'] as String? ?? 'Unable to claim this gift.';
          setState(() {
            _status = _ClaimStatus.error;
            _errorMessage = message;
          });
      }
    } on FunctionException catch (e) {
      // Edge Function 返回的业务错误
      final body = e.details as Map<String, dynamic>?;
      final msg = body?['message'] as String? ?? e.toString();

      // 根据错误信息判断具体状态
      if (msg.contains('recalled')) {
        setState(() => _status = _ClaimStatus.recalled);
      } else if (msg.contains('expired')) {
        setState(() => _status = _ClaimStatus.expired);
      } else {
        setState(() {
          _status = _ClaimStatus.error;
          _errorMessage = msg;
        });
      }
    } catch (e) {
      setState(() {
        _status = _ClaimStatus.error;
        _errorMessage = 'Something went wrong. Please try again.';
      });
    }
  }

  // 格式化过期时间显示
  String _formatExpiry(String? isoString) {
    if (isoString == null || isoString.isEmpty) return 'No expiry';
    try {
      final dt = DateTime.parse(isoString).toLocal();
      return DateFormat('MMM d, yyyy').format(dt);
    } catch (_) {
      return isoString;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gift'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/home');
            }
          },
        ),
      ),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: _buildBody(context),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    switch (_status) {
      case _ClaimStatus.loading:
        return _buildLoading();
      case _ClaimStatus.success:
        return _buildSuccess(context);
      case _ClaimStatus.recalled:
        return _buildStatusMessage(
          icon: Icons.undo_rounded,
          iconColor: AppColors.textHint,
          title: 'Gift Recalled',
          subtitle: 'This gift has been recalled by the sender.',
        );
      case _ClaimStatus.expired:
        return _buildStatusMessage(
          icon: Icons.timer_off_outlined,
          iconColor: AppColors.textHint,
          title: 'Gift Expired',
          subtitle: 'This coupon has expired.',
        );
      case _ClaimStatus.error:
        return _buildStatusMessage(
          icon: Icons.error_outline_rounded,
          iconColor: Colors.redAccent,
          title: 'Unable to Claim',
          subtitle: _errorMessage,
          showRetry: true,
        );
    }
  }

  // 加载中状态
  Widget _buildLoading() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: const [
        CircularProgressIndicator(),
        SizedBox(height: 24),
        Text(
          'Claiming your gift...',
          style: TextStyle(fontSize: 16, color: AppColors.textSecondary),
        ),
      ],
    );
  }

  // 领取成功状态 — 显示券信息
  Widget _buildSuccess(BuildContext context) {
    final result = _result!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 成功图标
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.card_giftcard_rounded,
            size: 40,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'Gift Claimed!',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Your gift coupon has been added to your account.',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 14,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 32),

        // 券信息卡片
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.surfaceVariant),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Deal 标题
              Text(
                result.dealTitle,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              // 商家名
              Text(
                result.merchantName,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                ),
              ),
              const Divider(height: 24),
              // 券码
              Row(
                children: [
                  const Icon(Icons.qr_code_2, size: 18, color: AppColors.textHint),
                  const SizedBox(width: 8),
                  const Text(
                    'Coupon Code:',
                    style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      result.couponCode,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textPrimary,
                        fontFamily: 'monospace',
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // 过期时间
              Row(
                children: [
                  const Icon(Icons.calendar_today_outlined, size: 16, color: AppColors.textHint),
                  const SizedBox(width: 8),
                  const Text(
                    'Valid until:',
                    style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _formatExpiry(result.expiresAt),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 32),

        // 跳转到 My Coupons 按钮
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => context.go('/coupons'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Go to My Coupons',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    );
  }

  // 通用状态提示（已撤回 / 已过期 / 错误）
  Widget _buildStatusMessage({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    bool showRetry = false,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 72, color: iconColor),
        const SizedBox(height: 20),
        Text(
          title,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 14,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 32),
        if (showRetry)
          OutlinedButton(
            onPressed: () {
              setState(() => _status = _ClaimStatus.loading);
              _claimGift();
            },
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Try Again'),
          ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => context.go('/home'),
          child: const Text(
            'Back to Home',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
      ],
    );
  }
}

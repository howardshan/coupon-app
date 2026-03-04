// 帮助中心页面
// 功能: 5 条 FAQ（ExpansionTile）+ Contact Support 邮件入口
// 注意: 纯静态 UI，无需状态管理

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

// ============================================================
// _FaqItem — FAQ 数据结构（纯数据，无状态）
// ============================================================
class _FaqItem {
  const _FaqItem({required this.question, required this.answer});
  final String question;
  final String answer;
}

// ============================================================
// FAQ 内容（写死，V2 可从后端拉取）
// ============================================================
const _faqItems = [
  _FaqItem(
    question: 'How do I create a new deal?',
    answer:
        'Go to the Deals tab → tap the + button → fill in deal details including '
        'title, price, stock and validity period → tap Submit for Review. '
        'Our team reviews deals within 24 hours on business days.',
  ),
  _FaqItem(
    question: 'When will I receive my payout?',
    answer:
        'Payouts are processed T+7 business days after each successful redemption. '
        'Funds are transferred directly to your connected Stripe bank account. '
        'You can view all transactions and settlement status in the Earnings tab.',
  ),
  _FaqItem(
    question: 'How do I scan a customer voucher?',
    answer:
        'Tap the Scan tab at the bottom of the screen → point your camera at the '
        "customer's QR code → review the voucher details → tap Confirm Redemption. "
        'You can also enter the voucher code manually if the camera cannot read it.',
  ),
  _FaqItem(
    question: 'Can I edit a deal after it is published?',
    answer:
        'You can edit most deal details while it is active. However, price changes '
        'require re-approval by our team. Stock quantity and expiry date can be '
        'updated immediately without review.',
  ),
  _FaqItem(
    question: 'How does the refund policy work?',
    answer:
        'DealJoy offers automatic refunds — customers can request a full refund '
        'any time before the voucher is redeemed. Once a voucher is confirmed as '
        'redeemed, it cannot be refunded. You can view all refunds in the Orders '
        'tab. Refunded amounts are deducted from your next payout.',
  ),
];

// ============================================================
// HelpCenterPage — 帮助中心（StatelessWidget）
// ============================================================
class HelpCenterPage extends StatelessWidget {
  const HelpCenterPage({super.key});

  /// 客服邮箱
  static const String _supportEmail = 'support@dealjoy.com';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text('Help Center'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A1A1A),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // --------------------------------------------------
          // 页面标题说明
          // --------------------------------------------------
          const Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: Text(
              'Frequently Asked Questions',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1A1A1A),
              ),
            ),
          ),

          // --------------------------------------------------
          // FAQ 列表卡片
          // --------------------------------------------------
          Container(
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
                for (int i = 0; i < _faqItems.length; i++)
                  _buildFaqTile(context, _faqItems[i], isLast: i == _faqItems.length - 1),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // --------------------------------------------------
          // Contact Support 按钮（底部）
          // --------------------------------------------------
          _buildContactButton(context),

          const SizedBox(height: 16),

          // 联系邮箱提示文字
          Text(
            'Or email us at $_supportEmail',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey[500],
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // ----------------------------------------------------------
  // FAQ 可展开行
  // ----------------------------------------------------------
  Widget _buildFaqTile(
    BuildContext context,
    _FaqItem item, {
    bool isLast = false,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Theme(
          // 去掉 ExpansionTile 默认的分隔线效果，由我们自己控制
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 16),
            childrenPadding:
                const EdgeInsets.only(left: 16, right: 16, bottom: 16),
            iconColor: const Color(0xFFFF6B35),
            collapsedIconColor: Colors.grey,
            title: Text(
              item.question,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Color(0xFF1A1A1A),
              ),
            ),
            children: [
              Text(
                item.answer,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[600],
                  height: 1.6,
                ),
              ),
            ],
          ),
        ),
        // 非最后一项显示分隔线
        if (!isLast)
          Divider(
            height: 1,
            indent: 16,
            color: Colors.grey.withValues(alpha: 0.15),
          ),
      ],
    );
  }

  // ----------------------------------------------------------
  // 联系客服按钮（打开系统邮件 App）
  // ----------------------------------------------------------
  Widget _buildContactButton(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: () => _launchSupportEmail(context),
      icon: const Icon(Icons.mail_outline, size: 18),
      label: const Text('Contact Support'),
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFFFF6B35),
        foregroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        elevation: 0,
      ),
    );
  }

  // ----------------------------------------------------------
  // 打开 mailto: 链接
  // ----------------------------------------------------------
  Future<void> _launchSupportEmail(BuildContext context) async {
    final uri = Uri(
      scheme: 'mailto',
      path: _supportEmail,
      queryParameters: {
        'subject': 'DealJoy Merchant Support Request',
      },
    );

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      // 无法打开邮件应用时提示用户
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not open mail app. Please email $_supportEmail directly.',
            ),
          ),
        );
      }
    }
  }
}

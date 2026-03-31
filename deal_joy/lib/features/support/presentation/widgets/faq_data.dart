// 预设问答树数据
// 每个 FaqItem 代表一个客服快捷问题

enum FaqAction {
  /// 展示用户最近订单列表
  showOrders,

  /// 展示可退款的订单列表
  showRefundableOrders,

  /// 返回主菜单
  goBack,

  /// 无特殊动作，纯文字回复
  none,
}

class FaqItem {
  final String id;
  final String label;
  final List<String> keywords;
  final String response;
  final FaqAction action;

  const FaqItem({
    required this.id,
    required this.label,
    required this.keywords,
    required this.response,
    this.action = FaqAction.none,
  });
}

const List<FaqItem> kFaqItems = [
  FaqItem(
    id: 'check_order',
    label: 'Check Order Status',
    keywords: ['order', 'status', 'where', 'track', 'my order'],
    response: 'Here are your recent orders:',
    action: FaqAction.showOrders,
  ),
  FaqItem(
    id: 'request_refund',
    label: 'Request a Refund',
    keywords: ['refund', 'return', 'money back', 'cancel'],
    response: 'Here are your orders eligible for refund. Tap one to start the refund process:',
    action: FaqAction.showRefundableOrders,
  ),
  FaqItem(
    id: 'how_to_use_coupon',
    label: 'How to Use Coupons',
    keywords: ['coupon', 'use', 'redeem', 'qr', 'scan', 'how to'],
    response:
        'To use your coupon:\n\n'
        '1. Go to "My Coupons" from your Profile page\n'
        '2. Find your unused coupon and tap it\n'
        '3. Show the QR code to the merchant staff\n'
        '4. The merchant will scan it to complete redemption\n\n'
        'Each coupon can only be used once. Make sure to use it before the expiration date!',
  ),
  FaqItem(
    id: 'refund_policy',
    label: 'Refund Policy',
    keywords: ['policy', 'rule', 'how long', 'when refund'],
    response:
        'DealJoy Refund Policy:\n\n'
        '• Unused coupons can be refunded anytime — no questions asked!\n'
        '• Refunds are processed within 1-3 business days\n'
        '• The refund goes back to your original payment method or store credit\n'
        '• Used or expired coupons cannot be refunded\n\n'
        'That\'s our "Buy anytime, refund anytime" promise!',
  ),
  FaqItem(
    id: 'contact_merchant',
    label: 'Contact Merchant',
    keywords: ['merchant', 'store', 'contact', 'phone', 'call', 'address'],
    response:
        'To contact a merchant:\n\n'
        '1. Go to the deal or order page\n'
        '2. Tap the merchant name to visit their store page\n'
        '3. You\'ll find their phone number, address, and business hours there\n\n'
        'You can also call them directly from the store page!',
  ),
  FaqItem(
    id: 'other',
    label: 'Other Questions',
    keywords: [],
    response:
        'I\'m sorry I couldn\'t find an answer to your question.\n\n'
        'For further assistance, you can:\n'
        '• Email us at support@dealjoy.com\n'
        '• Request a call back from our support team\n\n'
        'Go back to the Support page to choose these options.',
    action: FaqAction.goBack,
  ),
];

/// 根据用户输入匹配最佳 FAQ 项
/// 返回 null 表示无匹配，使用兜底项
FaqItem? matchFaq(String input) {
  final lower = input.toLowerCase().trim();
  if (lower.isEmpty) return null;

  // 精确匹配 label
  for (final item in kFaqItems) {
    if (item.label.toLowerCase() == lower) return item;
  }

  // 关键词匹配（找匹配关键词最多的）
  FaqItem? bestMatch;
  int bestScore = 0;

  for (final item in kFaqItems) {
    if (item.keywords.isEmpty) continue;
    int score = 0;
    for (final kw in item.keywords) {
      if (lower.contains(kw.toLowerCase())) score++;
    }
    if (score > bestScore) {
      bestScore = score;
      bestMatch = item;
    }
  }

  return bestMatch;
}

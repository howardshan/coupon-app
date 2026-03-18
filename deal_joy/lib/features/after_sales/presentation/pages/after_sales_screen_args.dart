class AfterSalesScreenArgs {
  const AfterSalesScreenArgs({
    required this.orderId,
    required this.couponId,
    required this.dealTitle,
    required this.totalAmount,
    this.merchantName,
    this.couponCode,
    this.couponUsedAt,
  });

  final String orderId;
  final String couponId;
  final String dealTitle;
  final double totalAmount;
  final String? merchantName;
  final String? couponCode;
  final DateTime? couponUsedAt;
}

// 购物车单项模型

class CartItemModel {
  final String dealId;
  final String dealTitle;
  final String? dealImageUrl;
  final double discountPrice;
  final double originalPrice;
  final String merchantName;
  final String merchantId;
  int quantity;

  CartItemModel({
    required this.dealId,
    required this.dealTitle,
    this.dealImageUrl,
    required this.discountPrice,
    required this.originalPrice,
    required this.merchantName,
    required this.merchantId,
    this.quantity = 1,
  });

  /// 小计
  double get subtotal => discountPrice * quantity;

  CartItemModel copyWith({int? quantity}) {
    return CartItemModel(
      dealId: dealId,
      dealTitle: dealTitle,
      dealImageUrl: dealImageUrl,
      discountPrice: discountPrice,
      originalPrice: originalPrice,
      merchantName: merchantName,
      merchantId: merchantId,
      quantity: quantity ?? this.quantity,
    );
  }
}

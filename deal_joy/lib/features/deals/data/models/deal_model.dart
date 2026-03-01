class DealModel {
  final String id;
  final String merchantId;
  final String title;
  final String description;
  final String category;
  final double originalPrice;
  final double discountPrice;
  final int discountPercent;
  final String discountLabel; // e.g. "40% OFF", "BUY 1 GET 1"
  final List<String> imageUrls;
  final List<String> dishes; // included dishes list
  final double rating;
  final int reviewCount;
  final int totalSold;
  final int stockLimit;
  final DateTime expiresAt;
  final bool isFeatured;
  final String refundPolicy;
  final double? lat;
  final double? lng;
  final String? address;
  final String? merchantHours;
  final MerchantSummary? merchant;

  const DealModel({
    required this.id,
    required this.merchantId,
    required this.title,
    required this.description,
    required this.category,
    required this.originalPrice,
    required this.discountPrice,
    required this.discountPercent,
    this.discountLabel = '',
    required this.imageUrls,
    this.dishes = const [],
    this.rating = 0.0,
    this.reviewCount = 0,
    this.totalSold = 0,
    required this.stockLimit,
    required this.expiresAt,
    this.isFeatured = false,
    this.refundPolicy = 'Risk-Free Refund within 7 days',
    this.lat,
    this.lng,
    this.address,
    this.merchantHours,
    this.merchant,
  });

  factory DealModel.fromJson(Map<String, dynamic> json) => DealModel(
        id: json['id'] as String,
        merchantId: json['merchant_id'] as String,
        title: json['title'] as String,
        description: json['description'] as String,
        category: json['category'] as String,
        originalPrice: (json['original_price'] as num).toDouble(),
        discountPrice: (json['discount_price'] as num).toDouble(),
        discountPercent: json['discount_percent'] as int? ??
            ((1 - (json['discount_price'] as num) / (json['original_price'] as num)) * 100).round(),
        discountLabel: json['discount_label'] as String? ?? '',
        imageUrls: List<String>.from(json['image_urls'] as List? ?? []),
        dishes: List<String>.from(json['dishes'] as List? ?? []),
        rating: (json['rating'] as num?)?.toDouble() ?? 0.0,
        reviewCount: json['review_count'] as int? ?? 0,
        totalSold: json['total_sold'] as int? ?? 0,
        stockLimit: json['stock_limit'] as int? ?? 100,
        expiresAt: DateTime.parse(json['expires_at'] as String),
        isFeatured: json['is_featured'] as bool? ?? false,
        refundPolicy: json['refund_policy'] as String? ??
            'Risk-Free Refund within 7 days',
        lat: (json['lat'] as num?)?.toDouble(),
        lng: (json['lng'] as num?)?.toDouble(),
        address: json['address'] as String?,
        merchantHours: json['merchant_hours'] as String?,
        merchant: json['merchants'] != null
            ? MerchantSummary.fromJson(
                json['merchants'] as Map<String, dynamic>)
            : null,
      );

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  Duration get timeLeft => expiresAt.difference(DateTime.now());

  double get savingsAmount => originalPrice - discountPrice;

  String get effectiveDiscountLabel => discountLabel.isNotEmpty
      ? discountLabel
      : '$discountPercent% OFF';
}

class MerchantSummary {
  final String id;
  final String name;
  final String? logoUrl;
  final String? phone;
  final String? address;
  final String? hours;
  final double rating;
  final int reviewCount;

  const MerchantSummary({
    required this.id,
    required this.name,
    this.logoUrl,
    this.phone,
    this.address,
    this.hours,
    this.rating = 0.0,
    this.reviewCount = 0,
  });

  factory MerchantSummary.fromJson(Map<String, dynamic> json) =>
      MerchantSummary(
        id: json['id'] as String,
        name: json['name'] as String,
        logoUrl: json['logo_url'] as String?,
        phone: json['phone'] as String?,
        address: json['address'] as String?,
        hours: json['hours'] as String?,
        rating: (json['rating'] as num?)?.toDouble() ?? 0.0,
        reviewCount: json['review_count'] as int? ?? 0,
      );
}

import 'package:flutter/material.dart';

class CategoryItem {
  final String id;
  final String name;
  final IconData icon;
  const CategoryItem(this.id, this.name, this.icon);
}

class AppConstants {
  static const String appName = 'DealJoy';
  static const String appVersion = '1.0.0';

  // Supabase tables
  static const String tableUsers = 'users';
  static const String tableMerchants = 'merchants';
  static const String tableDeals = 'deals';
  static const String tableOrders = 'orders';
  static const String tableCoupons = 'coupons';
  static const String tableReviews = 'reviews';
  static const String tablePayments = 'payments';
  static const String tableCategories = 'categories';
  static const String tableSavedDeals = 'saved_deals';

  // Deal categories — single source of truth (used by HomeScreen icons + filters)
  static const List<CategoryItem> categoryItems = [
    CategoryItem('hot', 'Hot Deals', Icons.local_fire_department),
    CategoryItem('bbq', 'BBQ', Icons.outdoor_grill),
    CategoryItem('hotpot', 'Hot Pot', Icons.ramen_dining),
    CategoryItem('coffee', 'Coffee', Icons.coffee),
    CategoryItem('dessert', 'Dessert', Icons.cake),
    CategoryItem('massage', 'Massage', Icons.spa),
    CategoryItem('sushi', 'Sushi', Icons.set_meal),
    CategoryItem('pizza', 'Pizza', Icons.local_pizza),
    CategoryItem('ramen', 'Ramen', Icons.ramen_dining),
    CategoryItem('korean', 'Korean', Icons.rice_bowl),
  ];

  // Filter-only category names (includes "All" for filter dropdowns)
  static const List<String> categories = [
    'All',
    'BBQ',
    'Hot Pot',
    'Coffee',
    'Dessert',
    'Massage',
    'Sushi',
    'Pizza',
    'Ramen',
    'Korean',
  ];

  // Order status
  static const String orderStatusUnused = 'unused';
  static const String orderStatusUsed = 'used';
  static const String orderStatusRefunded = 'refunded';
  static const String orderStatusExpired = 'expired';

  // Merchant status
  static const String merchantStatusPending = 'pending';
  static const String merchantStatusApproved = 'approved';
  static const String merchantStatusRejected = 'rejected';

  // Pagination
  static const int pageSize = 20;

  // Dallas coordinates
  static const double dallasLat = 32.7767;
  static const double dallasLng = -96.7970;
  static const double defaultRadiusKm = 10.0;
}

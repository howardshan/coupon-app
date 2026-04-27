import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Opens merchant deal detail. If the route pops with `true` (deal deleted),
/// shows a success snackbar on the underlying scaffold.
Future<void> openMerchantDealDetail(BuildContext context, String dealId) async {
  final deleted = await context.push<bool>('/deals/$dealId');
  if (!context.mounted) return;
  if (deleted == true) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Deal deleted successfully.'),
        backgroundColor: Color(0xFF4CAF50),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

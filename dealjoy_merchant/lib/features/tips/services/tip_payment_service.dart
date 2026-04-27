import 'package:supabase_flutter/supabase_flutter.dart';
import '../../store/services/store_service.dart';

/// Calls Edge Function `create-tip-payment-intent` (merchant JWT + X-Merchant-Id).
class TipPaymentService {
  TipPaymentService(this._supabase);

  final SupabaseClient _supabase;

  static const _fn = 'create-tip-payment-intent';

  Future<Map<String, dynamic>> createPaymentIntent({
    required String couponId,
    required int amountCents,
    String? presetChoice,
    String? signaturePngBase64,
  }) async {
    final response = await _supabase.functions.invoke(
      _fn,
      method: HttpMethod.post,
      headers: StoreService.merchantIdHeaders,
      body: {
        'coupon_id': couponId,
        'amount_cents': amountCents,
        if (presetChoice != null) 'preset_choice': presetChoice,
        if (signaturePngBase64 != null && signaturePngBase64.isNotEmpty)
          'signature_png_base64': signaturePngBase64,
      },
    );

    final data = response.data;
    if (data is! Map<String, dynamic>) {
      throw TipPaymentException('Invalid response');
    }
    if (data['error'] != null) {
      throw TipPaymentException(data['message'] as String? ?? 'Request failed');
    }
    return data;
  }
}

class TipPaymentException implements Exception {
  TipPaymentException(this.message);
  final String message;

  @override
  String toString() => message;
}

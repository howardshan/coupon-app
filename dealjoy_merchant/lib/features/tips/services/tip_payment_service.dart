import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../store/services/store_service.dart';

/// Calls Edge Function `create-tip-payment-intent` (merchant JWT + X-Merchant-Id).
///
/// Success JSON includes `flow`: `completed` \| `processing` \| `requires_customer_action`
/// \| `merchant_fallback`; only `merchant_fallback` returns `client_secret` for PaymentSheet.
class TipPaymentService {
  TipPaymentService(this._supabase);

  final SupabaseClient _supabase;

  static const _fn = 'create-tip-payment-intent';
  static const _invokeTimeout = Duration(seconds: 45);

  Future<Map<String, dynamic>> createPaymentIntent({
    required String couponId,
    required int amountCents,
    String? presetChoice,
    String? signaturePngBase64,
  }) async {
    try {
      final response = await _supabase.functions
          .invoke(
            _fn,
            method: HttpMethod.post,
            headers: StoreService.merchantIdHeaders,
            body: {
              'coupon_id': couponId,
              'amount_cents': amountCents,
              'preset_choice': ?presetChoice,
              if (signaturePngBase64 != null && signaturePngBase64.isNotEmpty)
                'signature_png_base64': signaturePngBase64,
            },
          )
          .timeout(_invokeTimeout);

      if (kDebugMode) {
        debugPrint(
          '[CollectTip] create-tip-payment-intent HTTP ${response.status}',
        );
      }

      final data = _parseResponse(response);
      if (data['error'] != null) {
        final code = data['error'] as String? ?? '';
        final msg = data['message'] as String? ?? 'Request failed';
        if (kDebugMode) {
          debugPrint('[CollectTip] edge error body: $code — $msg');
        }
        throw TipPaymentException(_messageForEdgeError(code, msg, data));
      }
      return data;
    } on TipPaymentException {
      rethrow;
    } on FunctionException catch (e) {
      final body = _tryParseBody(e.details);
      final code = body?['error'] as String? ?? 'unknown';
      final msg = body?['message'] as String? ?? e.reasonPhrase ?? 'Request failed';
      if (kDebugMode) {
        debugPrint(
          '[CollectTip] FunctionException status=${e.status} code=$code msg=$msg',
        );
      }
      throw TipPaymentException(_messageForEdgeError(code, msg, body ?? {}));
    } on TimeoutException {
      throw TipPaymentException(
        'Request timed out. Check your connection and try again.',
      );
    } catch (e) {
      if (e is TipPaymentException) rethrow;
      throw TipPaymentException('Network error: $e');
    }
  }

  /// 将 Edge 错误码映射为面向店员的可读英文（UI 全英文）
  String _messageForEdgeError(
    String code,
    String message,
    Map<String, dynamic> data,
  ) {
    if (code == 'pending_exists') {
      final sec = data['retry_after_seconds'];
      final suffix = sec is int && sec > 0 ? ' Retry in ~$sec s.' : '';
      return 'A tip payment is already in progress for this voucher.$suffix';
    }
    return message;
  }

  Map<String, dynamic> _parseResponse(FunctionResponse response) {
    final data = response.data;
    if (data is Map<String, dynamic>) return data;
    if (data is String) {
      try {
        return jsonDecode(data) as Map<String, dynamic>;
      } catch (_) {}
    }
    return {};
  }

  Map<String, dynamic>? _tryParseBody(dynamic details) {
    try {
      if (details is Map<String, dynamic>) return details;
      if (details is String) return jsonDecode(details) as Map<String, dynamic>;
    } catch (_) {}
    return null;
  }
}

class TipPaymentException implements Exception {
  TipPaymentException(this.message);
  final String message;

  @override
  String toString() => message;
}

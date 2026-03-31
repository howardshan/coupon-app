import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/errors/app_exception.dart';

class SupportRepository {
  final SupabaseClient _client;

  SupportRepository(this._client);

  /// 提交回拨请求
  Future<void> submitCallbackRequest({
    required String phone,
    required String timeSlot,
    String? description,
  }) async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) {
        throw const AppAuthException('Please sign in first.');
      }

      await _client.from('support_callbacks').insert({
        'user_id': userId,
        'phone': phone,
        'preferred_time_slot': timeSlot,
        if (description != null && description.isNotEmpty)
          'description': description,
      });
    } on PostgrestException catch (e) {
      throw AppException(
        'Failed to submit callback request: ${e.message}',
        code: e.code,
      );
    }
  }
}

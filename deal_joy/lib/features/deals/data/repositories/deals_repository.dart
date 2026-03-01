import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/errors/app_exception.dart';
import '../models/deal_model.dart';

class DealsRepository {
  final SupabaseClient _client;

  DealsRepository(this._client);

  Future<List<DealModel>> fetchDeals({
    String? category,
    String? search,
    int page = 0,
  }) async {
    try {
      var query = _client
          .from('deals')
          .select('*, merchants(id, name, logo_url, phone)')
          .eq('is_active', true)
          .gt('expires_at', DateTime.now().toIso8601String());

      if (category != null && category != 'All') {
        query = query.eq('category', category);
      }

      if (search != null && search.isNotEmpty) {
        query = query.ilike('title', '%$search%');
      }

      final data = await query
          .order('is_featured', ascending: false)
          .order('created_at', ascending: false)
          .range(
            page * AppConstants.pageSize,
            (page + 1) * AppConstants.pageSize - 1,
          );

      return (data as List).map((e) => DealModel.fromJson(e)).toList();
    } on PostgrestException catch (e) {
      throw AppException('Failed to load deals: ${e.message}', code: e.code);
    }
  }

  Future<List<DealModel>> fetchFeaturedDeals() async {
    try {
      final data = await _client
          .from('deals')
          .select('*, merchants(id, name, logo_url, phone)')
          .eq('is_active', true)
          .eq('is_featured', true)
          .gt('expires_at', DateTime.now().toIso8601String())
          .order('created_at', ascending: false)
          .limit(10);
      return (data as List).map((e) => DealModel.fromJson(e)).toList();
    } on PostgrestException catch (e) {
      throw AppException('Failed to load featured deals: ${e.message}',
          code: e.code);
    }
  }

  Future<DealModel> fetchDealById(String dealId) async {
    try {
      final data = await _client
          .from('deals')
          .select('*, merchants(id, name, logo_url, phone)')
          .eq('id', dealId)
          .single();
      return DealModel.fromJson(data);
    } on PostgrestException catch (e) {
      throw AppException('Deal not found: ${e.message}', code: e.code);
    }
  }

  Future<void> saveDeal(String userId, String dealId) async {
    try {
      await _client.from('saved_deals').upsert({
        'user_id': userId,
        'deal_id': dealId,
      });
    } on PostgrestException catch (e) {
      throw AppException('Failed to save deal: ${e.message}', code: e.code);
    }
  }

  Future<void> unsaveDeal(String userId, String dealId) async {
    try {
      await _client
          .from('saved_deals')
          .delete()
          .eq('user_id', userId)
          .eq('deal_id', dealId);
    } on PostgrestException catch (e) {
      throw AppException('Failed to unsave deal: ${e.message}', code: e.code);
    }
  }

  Future<List<DealModel>> fetchSavedDeals(String userId) async {
    try {
      final data = await _client
          .from('saved_deals')
          .select('deals(*, merchants(id, name, logo_url, phone))')
          .eq('user_id', userId);
      return (data as List)
          .map(
              (e) => DealModel.fromJson(e['deals'] as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (e) {
      throw AppException('Failed to load saved deals: ${e.message}',
          code: e.code);
    }
  }
}

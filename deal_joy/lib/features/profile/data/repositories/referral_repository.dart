import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/referral_model.dart';

class ReferralRepository {
  ReferralRepository(this._supabase);
  final SupabaseClient _supabase;

  /// 读取 referral_config（enabled + bonus_amount），anon 可访问
  Future<ReferralConfig> fetchConfig() async {
    final data = await _supabase
        .from('referral_config')
        .select('enabled, bonus_amount')
        .eq('id', 1)
        .single();
    return ReferralConfig.fromJson(data);
  }

  /// 读取当前用户的 referral_code 和是否已被推荐
  Future<({String code, bool hasReferrer})> fetchMyReferralInfo() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return (code: '', hasReferrer: false);

    final data = await _supabase
        .from('users')
        .select('referral_code, referred_by')
        .eq('id', user.id)
        .single();

    return (
      code: data['referral_code'] as String? ?? '',
      hasReferrer: data['referred_by'] != null,
    );
  }

  /// 读取我作为推荐人的所有推荐记录（JOIN users 获取被推荐人名字）
  Future<List<ReferralRecord>> fetchMyReferrals() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return [];

    final data = await _supabase
        .from('referrals')
        .select('id, referee_id, bonus_amount, status, created_at, credited_at, users!referrals_referee_id_fkey(full_name)')
        .eq('referrer_id', user.id)
        .order('created_at', ascending: false);

    return (data as List).map((e) => ReferralRecord.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// 绑定推荐码（由 deep link 注册后自动调用）
  /// 返回 RPC 结果字符串：'ok:<amount>' 或 错误码
  Future<String> applyCode(String code) async {
    final result = await _supabase.rpc(
      'apply_referral_code',
      params: {'p_code': code.trim().toUpperCase()},
    );
    return result as String? ?? 'error';
  }
}

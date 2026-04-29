import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/models/referral_model.dart';
import '../../data/repositories/referral_repository.dart';

final referralRepositoryProvider = Provider<ReferralRepository>((ref) {
  return ReferralRepository(Supabase.instance.client);
});

/// 读取 referral_config（程序是否开启 + 奖励金额）
/// autoDispose：每次页面重新挂载时都重新拉取，确保 admin 改配置后客户端能实时感知
final referralConfigProvider = FutureProvider.autoDispose<ReferralConfig>((ref) async {
  return ref.read(referralRepositoryProvider).fetchConfig();
});

/// 读取当前用户的邀请码和是否被推荐状态
final myReferralInfoProvider = FutureProvider<({String code, bool hasReferrer})>((ref) async {
  return ref.read(referralRepositoryProvider).fetchMyReferralInfo();
});

/// 读取我推荐出去的好友列表
final myReferralsProvider = FutureProvider<List<ReferralRecord>>((ref) async {
  return ref.read(referralRepositoryProvider).fetchMyReferrals();
});

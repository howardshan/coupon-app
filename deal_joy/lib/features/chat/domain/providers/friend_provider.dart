import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../shared/providers/supabase_provider.dart';
import '../../../auth/domain/providers/auth_provider.dart';
import '../../data/models/friend_model.dart';
import '../../data/repositories/friend_repository.dart';

// ---- Repository Provider ----

final friendRepositoryProvider = Provider<FriendRepository>((ref) {
  return FriendRepository(ref.watch(supabaseClientProvider));
});

// ---- 好友列表 ----

/// 获取当前用户已接受的好友列表
final friendsProvider = FutureProvider<List<FriendModel>>((ref) async {
  final user = await ref.watch(currentUserProvider.future);
  if (user == null) return [];
  return ref.watch(friendRepositoryProvider).fetchFriends(user.id);
});

// ---- 待处理的好友申请 ----

/// 获取发送给当前用户且状态为 pending 的好友申请列表
final pendingFriendRequestsProvider =
    FutureProvider<List<FriendRequestModel>>((ref) async {
  final user = await ref.watch(currentUserProvider.future);
  if (user == null) return [];
  return ref
      .watch(friendRepositoryProvider)
      .fetchPendingRequests(user.id);
});

// ---- 待处理好友申请数量（用于 badge 展示）----

/// 同步派生自 pendingFriendRequestsProvider，无需额外请求
final pendingRequestCountProvider = Provider<int>((ref) {
  return ref.watch(pendingFriendRequestsProvider).valueOrNull?.length ?? 0;
});

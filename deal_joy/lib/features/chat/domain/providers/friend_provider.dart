// 好友系统 Providers — Realtime 自动刷新

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../shared/providers/supabase_provider.dart';
import '../../../auth/domain/providers/auth_provider.dart';
import '../../data/models/friend_model.dart';
import '../../data/repositories/friend_repository.dart';

// ── Repository Provider ─────────────────────────────────────

final friendRepositoryProvider = Provider<FriendRepository>((ref) {
  return FriendRepository(ref.watch(supabaseClientProvider));
});

// ── 好友列表（Realtime 自动刷新）──────────────────────────

final friendsProvider =
    AutoDisposeAsyncNotifierProvider<FriendsNotifier, List<FriendModel>>(
        FriendsNotifier.new);

class FriendsNotifier extends AutoDisposeAsyncNotifier<List<FriendModel>> {
  RealtimeChannel? _channel;

  @override
  Future<List<FriendModel>> build() async {
    final user = await ref.watch(currentUserProvider.future);
    if (user == null) return [];

    // 订阅 friendships 表变化（INSERT / DELETE），自动刷新
    _channel?.unsubscribe();
    _channel = Supabase.instance.client
        .channel('friendships:${user.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'friendships',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: user.id,
          ),
          callback: (_) => _refresh(),
        )
        .subscribe();

    // 同时订阅 friend_requests 表（收到新申请时刷新）
    Supabase.instance.client
        .channel('friend_requests:${user.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'friend_requests',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'receiver_id',
            value: user.id,
          ),
          callback: (_) {
            // 刷新待处理申请
            ref.invalidate(pendingFriendRequestsProvider);
          },
        )
        .subscribe();

    // provider dispose 时取消订阅
    ref.onDispose(() {
      _channel?.unsubscribe();
    });

    return ref.watch(friendRepositoryProvider).fetchFriends(user.id);
  }

  Future<void> _refresh() async {
    final user = await ref.read(currentUserProvider.future);
    if (user == null) return;
    state = await AsyncValue.guard(
      () => ref.read(friendRepositoryProvider).fetchFriends(user.id),
    );
    // 好友列表变化时也刷新会话列表
    ref.invalidate(conversationsRefreshProvider);
  }
}

// ── 会话列表刷新触发器（好友列表变化时级联刷新）─────────

final conversationsRefreshProvider = Provider<int>((ref) => 0);

// ── 待处理的好友申请 ────────────────────────────────────

final pendingFriendRequestsProvider =
    FutureProvider.autoDispose<List<FriendRequestModel>>((ref) async {
  final user = await ref.watch(currentUserProvider.future);
  if (user == null) return [];
  return ref
      .watch(friendRepositoryProvider)
      .fetchPendingRequests(user.id);
});

// ── 待处理好友申请数量（用于 badge 展示）────────────────

final pendingRequestCountProvider = Provider<int>((ref) {
  return ref.watch(pendingFriendRequestsProvider).valueOrNull?.length ?? 0;
});

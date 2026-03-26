// FriendRepository — 好友关系数据访问层
// 操作 friendships / friend_requests 表
// 搜索用户走 users 表直查

import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/errors/app_exception.dart';
import '../models/friend_model.dart';

class FriendRepository {
  final SupabaseClient _client;

  FriendRepository(this._client);

  // ================================================================
  // 用户搜索
  // ================================================================

  /// 搜索用户（通过用户名 / 邮箱 / 手机号模糊匹配）
  /// 排除当前用户自身，返回原始 Map 列表供 UI 层渲染
  Future<List<Map<String, dynamic>>> searchUsers(
    String query,
    String currentUserId,
  ) async {
    try {
      // 同时搜索 username / email / phone 三个字段（ilike 大小写不敏感）
      final data = await _client
          .from('users')
          .select('id, full_name, username, avatar_url, email, phone')
          .or(
            'username.ilike.%$query%,'
            'email.ilike.%$query%,'
            'phone.ilike.%$query%',
          )
          .neq('id', currentUserId)
          .limit(20);

      return (data as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } on PostgrestException catch (e) {
      throw AppException(
        'Failed to search users: ${e.message}',
        code: e.code,
      );
    }
  }

  // ================================================================
  // 好友申请
  // ================================================================

  /// 向目标用户发送好友申请
  /// 若已存在 pending 申请则抛出异常避免重复发送
  Future<void> sendFriendRequest(String senderId, String receiverId) async {
    try {
      await _client.from('friend_requests').insert({
        'sender_id': senderId,
        'receiver_id': receiverId,
        'status': 'pending',
      });
    } on PostgrestException catch (e) {
      // 唯一约束冲突：已发过申请
      if (e.code == '23505') {
        throw const AppException(
          'Friend request already sent',
          code: 'duplicate_request',
        );
      }
      throw AppException(
        'Failed to send friend request: ${e.message}',
        code: e.code,
      );
    }
  }

  /// 接受或拒绝好友申请
  /// [accept] true = 接受，false = 拒绝
  /// 接受时数据库触发器应自动在 friendships 表中插入双向记录
  Future<void> respondToFriendRequest(String requestId, bool accept) async {
    try {
      await _client
          .from('friend_requests')
          .update({'status': accept ? 'accepted' : 'rejected'})
          .eq('id', requestId);
    } on PostgrestException catch (e) {
      throw AppException(
        'Failed to respond to friend request: ${e.message}',
        code: e.code,
      );
    }
  }

  /// 获取当前用户发出的待处理好友申请列表
  Future<List<FriendRequestModel>> fetchSentRequests(String userId) async {
    try {
      final data = await _client
          .from('friend_requests')
          .select('id, sender_id, receiver_id, status, created_at')
          .eq('sender_id', userId)
          .eq('status', 'pending')
          .order('created_at', ascending: false);

      final rows = data as List;
      if (rows.isEmpty) return [];

      // 批量查接收者信息
      final receiverIds = rows.map((r) => r['receiver_id'] as String).toSet().toList();
      final userMap = await _fetchUserInfoMap(receiverIds);

      return rows.map((r) {
        final rid = r['receiver_id'] as String;
        final receiverInfo = userMap[rid];
        return FriendRequestModel(
          id: r['id'] as String? ?? '',
          senderId: r['sender_id'] as String? ?? '',
          receiverId: rid,
          status: r['status'] as String? ?? 'pending',
          createdAt: r['created_at'] != null
              ? DateTime.parse(r['created_at'] as String)
              : DateTime.now(),
          receiverName: receiverInfo?['full_name'] as String?,
          receiverUsername: receiverInfo?['username'] as String?,
          receiverAvatarUrl: receiverInfo?['avatar_url'] as String?,
        );
      }).toList();
    } on PostgrestException catch (e) {
      throw AppException(
        'Failed to fetch sent requests: ${e.message}',
        code: e.code,
      );
    }
  }

  /// 取消当前用户发出的好友申请（将状态改为 cancelled）
  Future<void> cancelFriendRequest(String requestId) async {
    try {
      await _client
          .from('friend_requests')
          .update({'status': 'cancelled'})
          .eq('id', requestId);
    } on PostgrestException catch (e) {
      throw AppException(
        'Failed to cancel friend request: ${e.message}',
        code: e.code,
      );
    }
  }

  /// 获取发送给当前用户的待处理好友申请列表
  Future<List<FriendRequestModel>> fetchPendingRequests(String userId) async {
    try {
      final data = await _client
          .from('friend_requests')
          .select('id, sender_id, receiver_id, status, created_at')
          .eq('receiver_id', userId)
          .eq('status', 'pending')
          .order('created_at', ascending: false);

      final rows = data as List;
      if (rows.isEmpty) return [];

      // 批量查发送者信息
      final senderIds = rows.map((r) => r['sender_id'] as String).toSet().toList();
      final userMap = await _fetchUserInfoMap(senderIds);

      return rows.map((r) {
        final sid = r['sender_id'] as String;
        final senderInfo = userMap[sid];
        return FriendRequestModel(
          id: r['id'] as String? ?? '',
          senderId: sid,
          receiverId: r['receiver_id'] as String? ?? '',
          status: r['status'] as String? ?? 'pending',
          createdAt: r['created_at'] != null
              ? DateTime.parse(r['created_at'] as String)
              : DateTime.now(),
          senderName: senderInfo?['full_name'] as String?,
          senderUsername: senderInfo?['username'] as String?,
          senderAvatarUrl: senderInfo?['avatar_url'] as String?,
        );
      }).toList();
    } on PostgrestException catch (e) {
      throw AppException(
        'Failed to fetch friend requests: ${e.message}',
        code: e.code,
      );
    }
  }

  // ================================================================
  // 辅助：批量查询用户信息
  // ================================================================

  Future<Map<String, Map<String, dynamic>>> _fetchUserInfoMap(
      List<String> userIds) async {
    if (userIds.isEmpty) return {};
    final rows = await _client
        .from('users')
        .select('id, full_name, username, avatar_url')
        .inFilter('id', userIds);
    final map = <String, Map<String, dynamic>>{};
    for (final u in rows as List) {
      map[u['id'] as String] = u as Map<String, dynamic>;
    }
    return map;
  }

  // ================================================================
  // 好友列表
  // ================================================================

  /// 获取当前用户的好友列表
  /// friendships 表无 status 字段，存在即代表已是好友
  Future<List<FriendModel>> fetchFriends(String userId) async {
    try {
      // 先查 friendships 获取好友 ID
      final data = await _client
          .from('friendships')
          .select('id, friend_id, created_at')
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      final rows = data as List;
      if (rows.isEmpty) return [];

      // 批量查询好友用户信息
      final friendIds = rows.map((r) => r['friend_id'] as String).toList();
      final userRows = await _client
          .from('users')
          .select('id, full_name, username, avatar_url')
          .inFilter('id', friendIds);

      final userMap = <String, Map<String, dynamic>>{};
      for (final u in userRows as List) {
        userMap[u['id'] as String] = u as Map<String, dynamic>;
      }

      // 组装 FriendModel
      return rows.map((r) {
        final fid = r['friend_id'] as String;
        final userInfo = userMap[fid];
        return FriendModel(
          id: r['id'] as String? ?? '',
          friendId: fid,
          fullName: userInfo?['full_name'] as String?,
          username: userInfo?['username'] as String?,
          avatarUrl: userInfo?['avatar_url'] as String?,
          createdAt: r['created_at'] != null
              ? DateTime.parse(r['created_at'] as String)
              : DateTime.now(),
        );
      }).toList();
    } on PostgrestException catch (e) {
      throw AppException(
        'Failed to fetch friends: ${e.message}',
        code: e.code,
      );
    }
  }

  // ================================================================
  // 删除好友
  // ================================================================

  /// 删除好友关系（同时删除 friendships 表中的双向记录）
  Future<void> removeFriend(String userId, String friendId) async {
    try {
      // 删除双向记录：(userId -> friendId) 和 (friendId -> userId)
      await _client.from('friendships').delete().or(
            'and(user_id.eq.$userId,friend_id.eq.$friendId),'
            'and(user_id.eq.$friendId,friend_id.eq.$userId)',
          );
    } on PostgrestException catch (e) {
      throw AppException(
        'Failed to remove friend: ${e.message}',
        code: e.code,
      );
    }
  }
}

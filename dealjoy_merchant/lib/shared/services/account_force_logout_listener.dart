import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/store/services/store_service.dart';
import '../../router/app_router.dart';
import '../account_deletion_self_initiated.dart';

/// 订阅 auth_force_logout_signals：用户端或其他设备触发整账号删除时提示并登出
class MerchantAccountForceLogoutListener {
  MerchantAccountForceLogoutListener();

  RealtimeChannel? _channel;
  String? _boundUserId;

  void bindSession(String? userId) {
    if (userId == null || userId.isEmpty) {
      unbind();
      return;
    }
    if (_boundUserId == userId && _channel != null) return;
    unbind();
    _boundUserId = userId;
    _channel = Supabase.instance.client
        .channel('merchant_auth_force_logout_$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'auth_force_logout_signals',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (_) {
            Future.microtask(() => _handleSignal());
          },
        )
        .subscribe();
  }

  void unbind() {
    _channel?.unsubscribe();
    _channel = null;
    _boundUserId = null;
  }

  Future<void> _handleSignal() async {
    if (AccountDeletionSelfInitiated.active) return;

    final ctx = merchantAppRootNavigatorKey.currentContext;
    if (ctx != null && ctx.mounted) {
      await showDialog<void>(
        context: ctx,
        barrierDismissible: false,
        builder: (dCtx) => AlertDialog(
          title: const Text('Signed out'),
          content: const Text(
            'Your Crunchy Plum account was deleted from another app or device. '
            'You will now be signed out.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dCtx).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }

    await StoreService.clearPersistedMerchantId();
    StoreService.globalActiveMerchantId = null;
    await Supabase.instance.client.auth.signOut();
  }

  void dispose() => unbind();
}

final merchantAccountForceLogoutListenerProvider =
    Provider<MerchantAccountForceLogoutListener>((ref) {
  final listener = MerchantAccountForceLogoutListener();
  ref.onDispose(listener.dispose);
  return listener;
});

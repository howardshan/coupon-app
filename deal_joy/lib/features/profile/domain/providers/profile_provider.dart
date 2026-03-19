import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../shared/providers/supabase_provider.dart';
import '../../../auth/domain/providers/auth_provider.dart';
import '../../data/repositories/profile_repository.dart';

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return ProfileRepository(ref.watch(supabaseClientProvider));
});

/// 编辑 Profile 的状态管理
class ProfileEditNotifier extends AutoDisposeNotifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncValue.data(null);

  /// 保存 profile（头像 + 文本字段）
  Future<bool> saveProfile({
    required String userId,
    File? avatarFile,
    required String displayName,
    required String bio,
  }) async {
    state = const AsyncValue.loading();
    try {
      final repo = ref.read(profileRepositoryProvider);
      String? avatarUrl;

      // 有新头像则先上传
      if (avatarFile != null) {
        avatarUrl = await repo.uploadAvatar(userId, avatarFile);
      }

      // 更新 profile 文本字段
      await repo.updateProfile(
        userId: userId,
        displayName: displayName,
        bio: bio,
        avatarUrl: avatarUrl,
      );

      // 刷新 currentUserProvider 使首页头像即时更新
      ref.invalidate(currentUserProvider);

      state = const AsyncValue.data(null);
      return true;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return false;
    }
  }
}

final profileEditProvider =
    NotifierProvider.autoDispose<ProfileEditNotifier, AsyncValue<void>>(
        ProfileEditNotifier.new);

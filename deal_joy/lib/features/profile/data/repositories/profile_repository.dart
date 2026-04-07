import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProfileRepository {
  final SupabaseClient _client;

  ProfileRepository(this._client);

  /// 上传头像到 Supabase Storage，返回公开 URL
  Future<String> uploadAvatar(String userId, File imageFile) async {
    final ext = imageFile.path.split('.').last.toLowerCase();
    final path = '$userId/${DateTime.now().millisecondsSinceEpoch}.$ext';

    await _client.storage.from('avatars').upload(
      path,
      imageFile,
      fileOptions: const FileOptions(upsert: true),
    );

    final publicUrl = _client.storage.from('avatars').getPublicUrl(path);
    return publicUrl;
  }

  /// 更新 users 表的 profile 字段
  Future<void> updateProfile({
    required String userId,
    String? displayName,
    String? bio,
    String? avatarUrl,
  }) async {
    final updates = <String, dynamic>{
      'updated_at': DateTime.now().toIso8601String(),
    };
    if (displayName != null) updates['full_name'] = displayName;
    if (bio != null) updates['bio'] = bio;
    if (avatarUrl != null) updates['avatar_url'] = avatarUrl;

    await _client.from('users').update(updates).eq('id', userId);
  }

  /// 更新用户生日
  Future<void> updateDateOfBirth({
    required String userId,
    required DateTime dateOfBirth,
  }) async {
    await _client.from('users').update({
      'date_of_birth': dateOfBirth.toIso8601String().split('T').first,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', userId);
  }
}

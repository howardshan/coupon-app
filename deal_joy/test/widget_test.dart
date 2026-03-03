// 基本 smoke 测试 — 验证 DealJoyApp 可以正常构建
// 注：完整 app 需要 Supabase 初始化，此处仅验证 import 正确

import 'package:flutter_test/flutter_test.dart';
import 'package:deal_joy/features/auth/data/models/user_model.dart';

void main() {
  group('UserModel', () {
    test('fromJson creates model correctly', () {
      final json = {
        'id': 'test-id-123',
        'email': 'test@example.com',
        'username': 'testuser',
        'full_name': 'Test User',
        'avatar_url': null,
        'phone': null,
        'role': 'user',
        'created_at': '2026-01-01T00:00:00.000Z',
        'updated_at': '2026-01-01T00:00:00.000Z',
      };

      final user = UserModel.fromJson(json);

      expect(user.id, 'test-id-123');
      expect(user.email, 'test@example.com');
      expect(user.username, 'testuser');
      expect(user.fullName, 'Test User');
      expect(user.role, 'user');
    });

    test('toJson serializes correctly', () {
      final user = UserModel(
        id: 'id-1',
        email: 'a@b.com',
        username: 'alice',
        fullName: 'Alice',
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      );

      final json = user.toJson();

      expect(json['id'], 'id-1');
      expect(json['email'], 'a@b.com');
      expect(json['username'], 'alice');
      expect(json['full_name'], 'Alice');
      expect(json['role'], 'user');
    });

    test('copyWith creates modified copy', () {
      final user = UserModel(
        id: 'id-1',
        email: 'a@b.com',
        username: 'alice',
        fullName: 'Alice',
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      );

      final updated = user.copyWith(fullName: 'Alice Smith', phone: '1234');

      expect(updated.fullName, 'Alice Smith');
      expect(updated.phone, '1234');
      expect(updated.email, 'a@b.com'); // 不变
      expect(updated.username, 'alice'); // 不变
    });
  });
}

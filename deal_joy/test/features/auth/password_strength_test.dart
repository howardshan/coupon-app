// 密码强度计算逻辑的单元测试

import 'package:flutter_test/flutter_test.dart';
import 'package:deal_joy/features/auth/presentation/widgets/password_strength_indicator.dart';

void main() {
  group('calculatePasswordStrength', () {
    test('returns none for empty password', () {
      expect(calculatePasswordStrength(''), PasswordStrength.none);
    });

    test('returns weak for short password', () {
      expect(calculatePasswordStrength('abc'), PasswordStrength.weak);
      expect(calculatePasswordStrength('1234567'), PasswordStrength.weak);
    });

    test('returns weak for simple 8-char password', () {
      // 只有小写字母，虽然长度够但复杂度低
      expect(calculatePasswordStrength('abcdefgh'), PasswordStrength.weak);
    });

    test('returns medium for moderate complexity', () {
      // 大小写+数字，8位
      expect(calculatePasswordStrength('Abcdef12'), PasswordStrength.medium);
    });

    test('returns strong for high complexity', () {
      // 大小写+数字+特殊字符+长度 >= 12
      expect(
        calculatePasswordStrength('MyP@ssw0rd123!'),
        PasswordStrength.strong,
      );
    });

    test('returns strong for long complex password', () {
      expect(
        calculatePasswordStrength('SuperSecure123!@#'),
        PasswordStrength.strong,
      );
    });
  });
}

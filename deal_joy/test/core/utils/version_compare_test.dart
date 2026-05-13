import 'package:flutter_test/flutter_test.dart';

import 'package:deal_joy/core/utils/version_compare.dart';

void main() {
  group('compareSemver', () {
    test('equal', () {
      expect(compareSemver('1.0.0', '1.0.0'), 0);
    });
    test('less', () {
      expect(compareSemver('1.0.0', '1.0.1'), -1);
    });
    test('greater', () {
      expect(compareSemver('2.0.0', '1.9.9'), 1);
    });
    test('padding missing segments', () {
      expect(compareSemver('1.0', '1.0.1'), -1);
    });
  });
}

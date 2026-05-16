import 'package:dealjoy_merchant/features/merchant_auth/widgets/ein_input_formatter.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final formatter = EinInputFormatter();

  TextEditingValue format(String oldText, String newText, {int? cursor}) {
    return formatter.formatEditUpdate(
      TextEditingValue(text: oldText),
      TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(
          offset: cursor ?? newText.length,
        ),
      ),
    );
  }

  group('EinInputFormatter', () {
    test('formats 9 digits as XX-XXXXXXX', () {
      expect(
        format('', '123456789').text,
        '12-3456789',
      );
    });

    test('inserts dash after second digit while typing', () {
      expect(format('', '1').text, '1');
      expect(format('1', '12').text, '12');
      expect(format('12', '123').text, '12-3');
    });

    test('strips non-digits on paste', () {
      expect(
        format('', '12-3456789').text,
        '12-3456789',
      );
    });

    test('rejects more than 9 digits', () {
      final result = format('12-3456789', '12-34567890');
      expect(result.text, '12-3456789');
    });

    test('formatEinDigits helper', () {
      expect(EinInputFormatter.formatEinDigits(''), '');
      expect(EinInputFormatter.formatEinDigits('12'), '12');
      expect(EinInputFormatter.formatEinDigits('123456789'), '12-3456789');
    });
  });
}

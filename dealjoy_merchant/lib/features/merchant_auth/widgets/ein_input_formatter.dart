import 'package:flutter/services.dart';

/// EIN / Tax ID 输入：仅数字，格式化为 XX-XXXXXXX（第 3 位前自动插入 `-`）
class EinInputFormatter extends TextInputFormatter {
  static const int maxDigits = 9;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final newDigits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (newDigits.length > maxDigits) {
      return oldValue;
    }

    final formatted = formatEinDigits(newDigits);
    final selectionIndex = _resolveSelection(
      oldValue: oldValue,
      newValue: newValue,
      newDigits: newDigits,
      formatted: formatted,
    );

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(
        offset: selectionIndex.clamp(0, formatted.length),
      ),
    );
  }

  /// 将最多 9 位数字格式化为 XX-XXXXXXX
  static String formatEinDigits(String digits) {
    if (digits.isEmpty) return '';
    if (digits.length <= 2) return digits;
    return '${digits.substring(0, 2)}-${digits.substring(2)}';
  }

  static int _resolveSelection({
    required TextEditingValue oldValue,
    required TextEditingValue newValue,
    required String newDigits,
    required String formatted,
  }) {
    if (formatted.isEmpty) return 0;

    // 在末尾追加时，光标置于文末
    final oldDigits = oldValue.text.replaceAll(RegExp(r'\D'), '');
    if (newDigits.length >= oldDigits.length &&
        newValue.selection.isCollapsed &&
        newValue.selection.end >= newValue.text.length - 1) {
      return formatted.length;
    }

    // 其它编辑：按新文本中光标前的数字个数映射到格式化串
    final base = newValue.selection.baseOffset.clamp(0, newValue.text.length);
    final digitsBefore =
        newValue.text.substring(0, base).replaceAll(RegExp(r'\D'), '').length;
    return _offsetForDigitCount(digitsBefore, formatted.length);
  }

  static int _offsetForDigitCount(int digitCount, int formattedLength) {
    if (digitCount <= 0) return 0;
    if (digitCount <= 2) return digitCount;
    // 2 位数字后有一个 `-`
    final offset = digitCount + 1;
    return offset > formattedLength ? formattedLength : offset;
  }
}

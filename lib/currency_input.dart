import 'package:flutter/services.dart';

/// Cash-register entry: digits are cents, so 2270 becomes 22,70.
class CentsInputFormatter extends TextInputFormatter {
  const CentsInputFormatter();

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    if (!newValue.composing.isCollapsed) return newValue;
    if (RegExp(r'[^0-9,.]').hasMatch(newValue.text)) return oldValue;
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return TextEditingValue.empty;
    final cents = int.tryParse(digits);
    if (cents == null || cents > 99999999) return oldValue;
    final text = '${cents ~/ 100},${(cents % 100).toString().padLeft(2, '0')}';
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  }
}

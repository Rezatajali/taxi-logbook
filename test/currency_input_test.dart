import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_logbook/currency_input.dart';

void main() {
  test('Cash-register input formats typing, deletion and pasted amounts as cents', () {
    const formatter = CentsInputFormatter();
    var value = TextEditingValue.empty;
    for (final digit in '2270'.split('')) {
      value = formatter.formatEditUpdate(value, TextEditingValue(text: value.text + digit));
    }
    expect(value.text, '22,70');
    expect(value.selection.baseOffset, 5);
    value = formatter.formatEditUpdate(value, const TextEditingValue(text: '22,7'));
    expect(value.text, '2,27');
    expect(formatter.formatEditUpdate(value, TextEditingValue.empty).text, isEmpty);
    expect(formatter.formatEditUpdate(TextEditingValue.empty,
      const TextEditingValue(text: '30,00')).text, '30,00');
    expect(formatter.formatEditUpdate(value,
      const TextEditingValue(text: '100000000')), value);
    expect(formatter.formatEditUpdate(value,
      const TextEditingValue(text: 'abc')), value);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:steplife/core/utils/number_formatter.dart';

void main() {
  group('NumberFormatter Tests', () {
    test('formatQuantifiableValue should accurately format values into k and M', () {
      expect(NumberFormatter.formatQuantifiableValue(50), '50');
      expect(NumberFormatter.formatQuantifiableValue(50.5), '50.5');
      expect(NumberFormatter.formatQuantifiableValue(1200), '1.2k');
      expect(NumberFormatter.formatQuantifiableValue(15000), '15k');
      expect(NumberFormatter.formatQuantifiableValue(1500000), '1.5M');
    });
  });
}

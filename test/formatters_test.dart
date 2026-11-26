import 'package:flutter_test/flutter_test.dart';
import 'package:fietsradar/utils/formatters.dart';

void main() {
  group('formatDistance', () {
    test('shows metres below one kilometre', () {
      expect(formatDistance(850), '850 m');
    });

    test('shows kilometres with a Dutch decimal comma', () {
      expect(formatDistance(1250), '1,3 km');
    });
  });

  group('formatDuration', () {
    test('shows minutes for short routes', () {
      expect(formatDuration(const Duration(minutes: 8)), '8 min');
    });

    test('shows hours and remaining minutes for longer routes', () {
      expect(formatDuration(const Duration(minutes: 95)), '1 u 35 min');
    });
  });
}

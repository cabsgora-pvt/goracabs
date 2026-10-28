import 'package:flutter_test/flutter_test.dart';

import 'package:customer_app/utils/duration_format.dart';

void main() {
  test('minutes under an hour stay minutes', () {
    expect(formatMinutes(0), '0 min');
    expect(formatMinutes(7), '7 min');
    expect(formatMinutes(59), '59 min');
  });

  test('an hour or more reads as hours and minutes', () {
    expect(formatMinutes(60), '1 h');
    expect(formatMinutes(61), '1 h 1 min');
    expect(formatMinutes(120), '2 h');
    expect(formatMinutes(262), '4 h 22 min'); // the intercity badge that read "262 min"
  });
}

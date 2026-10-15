import 'package:flutter_test/flutter_test.dart';

import 'package:customer_app/utils/place_names.dart';

void main() {
  group('cityOf', () {
    for (final (address, town) in const [
      ('DLF Cyber City, Sector 24, Gurugram, Haryana 122002', 'Gurugram'),
      ('Hawa Mahal Road, Badi Choupad, Jaipur, Rajasthan 302002', 'Jaipur'),
      ('Jaipur, Rajasthan, India', 'Jaipur'),
      ('Connaught Place, New Delhi, Delhi 110001, India', 'New Delhi'),
      ('Bandra West, Mumbai, Maharashtra 400050', 'Mumbai'),
      ('Navrangpura, Ahmedabad 380009', 'Ahmedabad'),
      ('Ahmedabad, Gujarat', 'Ahmedabad'),
      ('Ahmedabad', 'Ahmedabad'),
      ('Delhi, India', 'Delhi'),
      ('Current location', 'Current location'),
      ('', ''),
    ]) {
      test('"$address" → "$town"', () => expect(cityOf(address), town));
    }
  });
}

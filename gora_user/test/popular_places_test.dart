import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:customer_app/widgets/popular_places.dart';

// "Popular places near you" on the rider home.

http.Response _json(Object b) => http.Response(jsonEncode(b), 200, headers: {'content-type': 'application/json'});

Map<String, dynamic> _place(String id, String name, String cat, String type) => {
      'id': id, 'name': name, 'category': cat, 'type': type, 'address': 'Somewhere',
      'lat': 26.29, 'lng': 73.01, 'rating': 4.6, 'distanceKm': 6.6, 'photoUrl': null,
    };

Widget _host(LatLng? at, void Function(PopularPlace) onTap) =>
    MaterialApp(home: Scaffold(body: SingleChildScrollView(child: PopularPlacesSection(at: at, onTap: onTap))));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('shows the server\'s places with category, distance and rating; tap gives the place', (tester) async {
    PopularPlace? tapped;
    await http.runWithClient(() async {
      await tester.pumpWidget(_host(const LatLng(26.24, 73.02), (p) => tapped = p));
      for (var i = 0; i < 5; i++) { await tester.pump(const Duration(milliseconds: 50)); }
    }, () => MockClient((req) async => _json({'places': [
          _place('a', 'Mehrangarh Fort', 'Tourist place', 'tourist_attraction'),
          _place('b', 'Jodhpur Junction', 'Station', 'train_station'),
        ]})));
    expect(find.text('Popular places near you'), findsOneWidget);
    expect(find.text('Mehrangarh Fort'), findsOneWidget);
    expect(find.text('Tourist place'), findsOneWidget);
    expect(find.text('6.6 km'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('popular-a')));
    expect(tapped?.name, 'Mehrangarh Fort');
    expect(tapped?.lat, 26.29);
  });

  testWidgets('nothing to show (no places / offline) hides the whole section', (tester) async {
    await http.runWithClient(() async {
      await tester.pumpWidget(_host(const LatLng(26.24, 73.02), (_) {}));
      for (var i = 0; i < 5; i++) { await tester.pump(const Duration(milliseconds: 50)); }
    }, () => MockClient((req) async => _json({'places': []})));
    expect(find.text('Popular places near you'), findsNothing);
  });

  testWidgets('a new position that arrives while the old one loads is loaded next (no stale city)', (tester) async {
    final asked = <String>[];
    final firstReply = Completer<http.Response>();
    await http.runWithClient(() async {
      await tester.pumpWidget(_host(const LatLng(26.24, 73.02), (_) {})); // last known fix: Jodhpur
      await tester.pump();
      await tester.pumpWidget(_host(const LatLng(28.61, 77.21), (_) {})); // real fix: Delhi, while loading
      await tester.pump();
      firstReply.complete(_json({'places': [_place('j', 'Mehrangarh Fort', 'Tourist place', 'tourist_attraction')]}));
      for (var i = 0; i < 8; i++) { await tester.pump(const Duration(milliseconds: 50)); }
    }, () => MockClient((req) async {
      asked.add(req.url.queryParameters['lat'] ?? '');
      if (asked.length == 1) return firstReply.future;
      return _json({'places': [_place('d', 'India Gate', 'Tourist place', 'tourist_attraction')]});
    }));
    expect(asked, ['26.24000', '28.61000']);
    expect(find.text('India Gate'), findsOneWidget);
    expect(find.text('Mehrangarh Fort'), findsNothing);
  });

  test('a photo URL is used only when it is https', () {
    expect(PopularPlace.fromJson({..._place('x', 'X', 'Mall', 'shopping_mall'), 'photoUrl': 'http://bad'})!.photoUrl, isNull);
    expect(PopularPlace.fromJson({..._place('x', 'X', 'Mall', 'shopping_mall'), 'photoUrl': 'https://lh3.googleusercontent.com/a'})!.photoUrl,
        'https://lh3.googleusercontent.com/a');
    expect(PopularPlace.fromJson({'name': 'no coords'}), isNull);
  });
}

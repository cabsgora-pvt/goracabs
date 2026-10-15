import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:gora_driver/features/ride/widgets/nav_engine.dart';
import 'package:gora_driver/features/ride/widgets/voice_guide.dart';

// Spoken guidance fails quietly: announce twice and it nags, never announce and
// nobody notices until a driver misses a turn. These pin the timing rules and
// the text transforms — the parts most likely to be wrong — without needing a
// speech engine.

NavStep step(String instruction, {double lat = 23.0225, double lng = 72.5714}) => NavStep(
  instruction: instruction,
  maneuver: 'turn-left',
  distanceM: 600,
  durationSec: 90,
  start: LatLng(lat, lng),
  end: LatLng(lat + 0.005, lng + 0.005),
);

void main() {
  group('spokenInstruction', () {
    test('expands road abbreviations', () {
      expect(NavAnnouncer.spokenInstruction('Turn left onto Relief Rd'),
          'Turn left onto Relief Road');
      expect(NavAnnouncer.spokenInstruction('Continue on Ashram Rd.'),
          'Continue on Ashram Road');
      expect(NavAnnouncer.spokenInstruction('Turn right Opp Town Hall'),
          'Turn right Opposite Town Hall');
    });

    test('St is Saint before a name, Street after one', () {
      // A real Ahmedabad road. A blind expansion says "Street Xavier's".
      expect(NavAnnouncer.spokenInstruction("Turn left onto St. Xavier's College Rd"),
          "Turn left onto Saint Xavier's College Road");
      expect(NavAnnouncer.spokenInstruction('Turn right onto Relief St'),
          'Turn right onto Relief Street');
    });

    test('national and state highways are spoken as words', () {
      expect(NavAnnouncer.spokenInstruction('Merge onto NH48'),
          'Merge onto National Highway 48');
      expect(NavAnnouncer.spokenInstruction('Keep left to stay on SH-17'),
          'Keep left to stay on State Highway 17');
    });

    test('does not mangle words that merely contain an abbreviation', () {
      // "Rd" inside "Records", "St" inside "Station" must survive untouched.
      expect(NavAnnouncer.spokenInstruction('Turn left at Records Station'),
          'Turn left at Records Station');
    });
  });

  group('spokenDistance', () {
    test('rounds to something a driver can use, spelled out', () {
      expect(NavAnnouncer.spokenDistance(412), '400 metres');
      expect(NavAnnouncer.spokenDistance(78), '80 metres');
      expect(NavAnnouncer.spokenDistance(3), '10 metres');
      expect(NavAnnouncer.spokenDistance(1000), '1 kilometre');
      expect(NavAnnouncer.spokenDistance(1260), '1.3 kilometres');
    });
  });

  group('NavAnnouncer timing', () {
    const dest = 'Pickup';

    test('far prompt once, near prompt once, no repeats in between', () {
      final a = NavAnnouncer();
      final s = step('Turn left onto Relief Rd');

      expect(a.update(step: s, toManeuverM: 900, arrived: false, destinationLabel: dest), isNull,
          reason: 'Too far out to announce');
      expect(a.update(step: s, toManeuverM: 395, arrived: false, destinationLabel: dest),
          'In 400 metres, turn left onto Relief Road');
      // GPS fixes keep arriving inside the window — none may repeat it.
      expect(a.update(step: s, toManeuverM: 300, arrived: false, destinationLabel: dest), isNull);
      expect(a.update(step: s, toManeuverM: 150, arrived: false, destinationLabel: dest), isNull);
      expect(a.update(step: s, toManeuverM: 70, arrived: false, destinationLabel: dest),
          'Turn left onto Relief Road');
      expect(a.update(step: s, toManeuverM: 30, arrived: false, destinationLabel: dest), isNull);
    });

    test('a manoeuvre first seen inside the near window is said once, not twice', () {
      final a = NavAnnouncer();
      final s = step('Turn right onto CG Rd');
      expect(a.update(step: s, toManeuverM: 60, arrived: false, destinationLabel: dest),
          'Turn right onto CG Road');
      expect(a.update(step: s, toManeuverM: 40, arrived: false, destinationLabel: dest), isNull);
    });

    test('a refreshed route with the same step does not re-announce it', () {
      // The route is re-fetched every 30 s and NavStep objects are rebuilt each
      // time. Same start + same instruction must count as the same step.
      final a = NavAnnouncer();
      a.update(step: step('Turn left onto Relief Rd'), toManeuverM: 395,
          arrived: false, destinationLabel: dest);
      final refreshed = step('Turn left onto Relief Rd');
      expect(a.update(step: refreshed, toManeuverM: 350, arrived: false, destinationLabel: dest),
          isNull);
    });

    test('the next manoeuvre is announced afresh', () {
      final a = NavAnnouncer();
      a.update(step: step('Turn left onto Relief Rd'), toManeuverM: 70,
          arrived: false, destinationLabel: dest);
      final next = step('Turn right onto Ashram Rd', lat: 23.03, lng: 72.58);
      expect(a.update(step: next, toManeuverM: 390, arrived: false, destinationLabel: dest),
          'In 400 metres, turn right onto Ashram Road');
    });

    test('the opening step is said once, as the drive begins', () {
      final a = NavAnnouncer();
      final s = step('Head north on Relief Rd');
      expect(a.depart(s), 'Head north on Relief Road');
      expect(a.depart(s), isNull);
    });

    // Said on the same fix as the countdown to the first turn: saying where to
    // go must not make the turn ahead look new on every fix after it.
    test('departing does not disturb the countdown to the turn ahead', () {
      final a = NavAnnouncer();
      final turn = step('Turn left onto Relief Rd');
      expect(a.depart(step('Head north on Ashram Rd')), isNotNull);
      expect(a.update(step: turn, toManeuverM: 395, arrived: false, destinationLabel: dest),
          'In 400 metres, turn left onto Relief Road');
      expect(a.depart(step('Head north on Ashram Rd')), isNull);
      expect(a.update(step: turn, toManeuverM: 350, arrived: false, destinationLabel: dest), isNull,
          reason: 'said once');
    });

    test('a new leg departs afresh', () {
      final a = NavAnnouncer();
      a.depart(step('Head north on Relief Rd'));
      a.reset();
      expect(a.depart(step('Head south on Relief Rd')), 'Head south on Relief Road');
    });

    test('arrival is announced exactly once', () {
      final a = NavAnnouncer();
      expect(a.update(step: null, toManeuverM: 0, arrived: true, destinationLabel: 'Pickup'),
          'You have arrived at the pickup');
      expect(a.update(step: null, toManeuverM: 0, arrived: true, destinationLabel: 'Pickup'), isNull);
    });

    test('reset lets a new leg be announced from the start', () {
      final a = NavAnnouncer();
      a.update(step: null, toManeuverM: 0, arrived: true, destinationLabel: 'Pickup');
      a.reset();
      expect(a.update(step: null, toManeuverM: 0, arrived: true, destinationLabel: 'Drop'),
          'You have arrived at the drop');
    });
  });
}

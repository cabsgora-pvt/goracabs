import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Basemap styling for the navigation map.
//
// The default Google basemap is built for browsing: saturated POI pins, every
// business labelled, parks and water competing for attention. During navigation
// all of that fights the one thing that matters — the route line — so nav apps
// mute the map underneath and let the route carry the colour.
//
// Two variants, chosen from the app theme, and from the clock after dark —
// a white map at night is genuinely unsafe in a windscreen mount.
//
// Kept as Dart string constants rather than asset JSON so a missing or
// malformed asset can never leave the map unstyled at runtime; the map simply
// ignores a style string it cannot parse.
// ─────────────────────────────────────────────────────────────────────────────

/// Muted daytime map, with the roads still reading as roads.
///
/// Muting the basemap is right — but the first version muted it past the point
/// where it was a map: white roads (#ffffff) on near-white land (#f4f5f7) are a
/// contrast ratio of 1.09, and the road casing was no darker. In the city the
/// live traffic layer painted the roads green and red and hid the problem; on a
/// highway at night, or in any town Google has no traffic data for, the screen
/// was blank grey with the route line floating on it. Drivers reported it as
/// "there is no map, only a line".
///
/// So the land is a step darker, buildings a step darker again, and every road
/// keeps a casing clearly darker than the land it sits on. The route line still
/// carries the colour; the map beneath it now carries the shape of the place.
const String kMapStyleDay = '''
[
  {"elementType":"geometry","stylers":[{"color":"#e9ecf1"}]},
  {"elementType":"labels.icon","stylers":[{"visibility":"off"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#4b5563"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#ffffff"},{"weight":2}]},
  {"featureType":"administrative","elementType":"geometry","stylers":[{"visibility":"off"}]},
  {"featureType":"landscape.man_made","elementType":"geometry","stylers":[{"color":"#e0e4eb"}]},
  {"featureType":"poi","elementType":"labels.text.fill","stylers":[{"color":"#6b7280"}]},
  {"featureType":"poi.business","stylers":[{"visibility":"off"}]},
  {"featureType":"poi.park","elementType":"geometry","stylers":[{"color":"#d7e7c8"}]},
  {"featureType":"road","elementType":"geometry.fill","stylers":[{"color":"#ffffff"}]},
  {"featureType":"road","elementType":"geometry.stroke","stylers":[{"color":"#b4bcc9"}]},
  {"featureType":"road.arterial","elementType":"geometry.stroke","stylers":[{"color":"#a3adbd"}]},
  {"featureType":"road.highway","elementType":"geometry.fill","stylers":[{"color":"#ffe9a8"}]},
  {"featureType":"road.highway","elementType":"geometry.stroke","stylers":[{"color":"#e0bf6b"}]},
  {"featureType":"road.local","elementType":"labels","stylers":[{"visibility":"simplified"}]},
  {"featureType":"transit","elementType":"labels","stylers":[{"visibility":"off"}]},
  {"featureType":"transit.line","elementType":"geometry","stylers":[{"color":"#d3d8e1"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#b5d4ef"}]},
  {"featureType":"water","elementType":"labels.text","stylers":[{"visibility":"off"}]}
]
''';

/// Night map: dark ground, roads lifted out of it, route line brightest.
///
/// The same contrast rule as the day style, inverted: on a dark ground the
/// roads must be LIGHTER, and by enough to survive a sunlit windscreen. The
/// first version drew them at #2b3442 on #1d2430 — a ratio of 1.2, invisible in
/// daylight glare and nearly so at night.
const String kMapStyleNight = '''
[
  {"elementType":"geometry","stylers":[{"color":"#171c26"}]},
  {"elementType":"labels.icon","stylers":[{"visibility":"off"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#a8b1c0"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#0f131b"},{"weight":2}]},
  {"featureType":"administrative","elementType":"geometry","stylers":[{"visibility":"off"}]},
  {"featureType":"landscape.man_made","elementType":"geometry","stylers":[{"color":"#1c222e"}]},
  {"featureType":"poi","elementType":"labels.text.fill","stylers":[{"color":"#7f8797"}]},
  {"featureType":"poi.business","stylers":[{"visibility":"off"}]},
  {"featureType":"poi.park","elementType":"geometry","stylers":[{"color":"#1b2a22"}]},
  {"featureType":"road","elementType":"geometry.fill","stylers":[{"color":"#39435a"}]},
  {"featureType":"road","elementType":"geometry.stroke","stylers":[{"color":"#4a566f"}]},
  {"featureType":"road.arterial","elementType":"geometry.fill","stylers":[{"color":"#434f6b"}]},
  {"featureType":"road.highway","elementType":"geometry.fill","stylers":[{"color":"#544d33"}]},
  {"featureType":"road.highway","elementType":"geometry.stroke","stylers":[{"color":"#6d6344"}]},
  {"featureType":"road.local","elementType":"labels","stylers":[{"visibility":"simplified"}]},
  {"featureType":"transit","elementType":"labels","stylers":[{"visibility":"off"}]},
  {"featureType":"transit.line","elementType":"geometry","stylers":[{"color":"#222a38"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#0d1622"}]},
  {"featureType":"water","elementType":"labels.text","stylers":[{"visibility":"off"}]}
]
''';

/// Route line width for the current zoom.
///
/// A fixed width is wrong at both ends: at city zoom a 6 px line smears across
/// whole blocks, and at street zoom it is a thread lost between the kerbs.
/// Widening with zoom keeps the line reading as "this road" at every scale.
double routeWidthForZoom(double zoom) {
  if (zoom >= 18) return 14;
  if (zoom >= 17) return 11;
  if (zoom >= 15.5) return 9;
  if (zoom >= 13) return 7;
  return 5;
}

/// Casing sits under the core line; this keeps the dark edge proportional.
double casingWidthForZoom(double zoom) => routeWidthForZoom(zoom) + 5;

/// Whether the navigation map should use the night basemap.
///
/// Two signals, deliberately in this order:
///
///  1. The app's own resolved theme. Both apps let the user pick Light / Dark /
///     System and persist it, so `Theme.of(context).brightness` is the only
///     thing that reflects that choice. Reading the DEVICE brightness instead
///     (MediaQuery.platformBrightnessOf) ignores it outright — a driver who set
///     Dark in the app on a light-mode phone still got a white map.
///
///  2. Failing that, the actual hour. A driver has the phone clamped to the
///     windscreen; a full-white map at 22:00 is genuinely unsafe whatever the
///     app theme says. So night hours force the dark basemap even in light mode.
///
/// Uses local device time rather than a sunrise/sunset calculation: the app is
/// India-only, so the seasonal swing is under an hour and not worth a
/// coordinate-dependent computation on every rebuild.
bool useNightMap(BuildContext context) {
  if (Theme.of(context).brightness == Brightness.dark) return true;
  final h = DateTime.now().hour;
  return h >= 19 || h < 6;
}

// ── Route colours ────────────────────────────────────────────────────────────
// The brand navy (#1C2656) is a LIGHT-theme colour. On the night basemap
// (#1d2430) it is almost the same luminance as the ground, so a route drawn in
// it effectively disappears — the one line that must never be hard to see.
//
// So the core brightens on dark maps and the casing darkens, keeping a strong
// value gap against the ground in both themes. This is the same inversion every
// nav app makes at dusk.

/// The bright core of the route line.
Color routeCoreColor(bool night) =>
    night ? const Color(0xFF5B9DFF) : const Color(0xFF1C2656);

/// The dark outline drawn beneath the core, which gives the route its edge.
Color routeCasingColor(bool night) =>
    night ? const Color(0xFF0A1730) : const Color(0xFF0B2A5B);

/// Colour for the already-travelled part of the route — present but receded.
Color routeTravelledColor(bool night) => night
    ? const Color(0xFF5B9DFF).withOpacity(0.28)
    : const Color(0xFF6B7280).withOpacity(0.40);

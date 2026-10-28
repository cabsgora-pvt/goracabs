import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// The fixed "you are picking this spot" pin drawn over the centre of a map.
///
/// Place it with its box centred on the camera target (e.g. in a [Center] over
/// the map's visible band). It shifts itself up so the POINT of the
/// [Icons.location_on] glyph, not the middle of the icon, marks the target.
class CentrePin extends StatelessWidget {
  final double size;
  final Color color;
  const CentrePin({super.key, this.size = 46, this.color = AppTheme.primaryBlue});

  /// Where the tip of [Icons.location_on] sits below the icon's centre: the
  /// Material glyph draws its point at y = 22 of a 24-unit box.
  static double tipBelowCentre(double size) => size * (22 / 24 - 0.5);

  @override
  Widget build(BuildContext context) => Transform.translate(
        offset: Offset(0, -tipBelowCentre(size)),
        child: Icon(Icons.location_on, size: size, color: color),
      );
}

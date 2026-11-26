import 'package:shared_preferences/shared_preferences.dart';

import '../../../models/models.dart';
import '../widgets/voice_guide.dart';

/// "New ride, 142 rupees, 1.2 kilometres away" — said once when a request
/// arrives, in the driver's voice language. A driver with the phone in a mount
/// hears what the request is worth and how far it is without reading the card.
class RequestAnnouncer {
  RequestAnnouncer._();

  /// On unless the driver turned it off (voice settings).
  static const enabledKey = 'request_voice_on';

  static Future<bool> enabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(enabledKey) ?? true;
    } catch (_) {
      return true;
    }
  }

  static Future<void> setEnabled(bool on) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(enabledKey, on);
    } catch (_) {}
  }

  /// The phrase for [r] in [language]. [pickupKm]: how far away the pickup
  /// is (null or 0 when not known — then the distance is left out).
  static String phrase(RideRequestModel r, String language, {double? pickupKm}) {
    final amount = (r.totalFareValue > 0 ? r.totalFareValue : r.baseFare).round();
    final km = pickupKm != null && pickupKm > 0 ? pickupKm : null;
    final dist = km == null ? null : NavAnnouncer.spokenDistance(km * 1000, language: language);
    switch (language) {
      case VoiceLanguage.hindi:
        return [
          _kindHi(r.service),
          if (amount > 0) '$amount रुपये',
          if (dist != null) '$dist दूर',
        ].join(', ');
      case VoiceLanguage.gujarati:
        return [
          _kindGu(r.service),
          if (amount > 0) '$amount રૂપિયા',
          if (dist != null) '$dist દૂર',
        ].join(', ');
      default:
        return [
          _kindEn(r.service),
          if (amount > 0) '$amount rupees',
          if (dist != null) '$dist away',
        ].join(', ');
    }
  }

  static String _kindEn(String s) => switch (s) {
        'delivery' => 'New parcel delivery',
        'rental' => 'New rental',
        'outstation' => 'New outstation trip',
        'hire_driver' => 'New driver hire',
        _ => 'New ride',
      };

  static String _kindHi(String s) => switch (s) {
        'delivery' => 'नई पार्सल डिलीवरी',
        'rental' => 'नई रेंटल बुकिंग',
        'outstation' => 'नई आउटस्टेशन ट्रिप',
        'hire_driver' => 'नई ड्राइवर बुकिंग',
        _ => 'नई राइड',
      };

  static String _kindGu(String s) => switch (s) {
        'delivery' => 'નવી પાર્સલ ડિલિવરી',
        'rental' => 'નવું રેન્ટલ બુકિંગ',
        'outstation' => 'નવી આઉટસ્ટેશન ટ્રિપ',
        'hire_driver' => 'નવું ડ્રાઇવર બુકિંગ',
        _ => 'નવી રાઇડ',
      };
}

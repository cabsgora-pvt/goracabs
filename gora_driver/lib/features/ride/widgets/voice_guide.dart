import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'nav_engine.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Spoken turn-by-turn guidance, in English or Hindi.
//
// Split in two on purpose:
//
//   NavAnnouncer — pure logic. Given where the driver is relative to the next
//                  manoeuvre, decides WHAT to say and WHEN, and remembers what it
//                  already said. No plugin, no platform: fully unit-testable.
//
//   VoiceGuide   — a thin wrapper that hands those phrases to the device's
//                  speech engine, with the audio behaviour nav apps need, and
//                  owns the driver's voice settings.
//
// Keeping the timing rules out of the plugin wrapper is what makes the part most
// likely to be wrong (announcing twice, never announcing, talking over itself)
// the part that can actually be tested.
// ─────────────────────────────────────────────────────────────────────────────

/// Languages guidance can be spoken in. The instructions themselves come from
/// Google Directions in the same language (see /api/directions?language=).
class VoiceLanguage {
  VoiceLanguage._();
  static const english = 'en';
  static const hindi = 'hi';

  /// Name shown in settings, in its own script.
  static String label(String code) => code == hindi ? 'हिंदी' : 'English';
}

class NavAnnouncer {
  NavAnnouncer({this.language = VoiceLanguage.english});

  /// First prompt for a manoeuvre: "In 400 metres, turn left onto ...".
  /// Long enough to change lanes in city traffic, short enough to remember.
  static const double farM = 400;

  /// Final prompt, as the turn arrives: "Turn left onto ...".
  static const double nearM = 80;

  /// A reroute is announced at most this often. Off-route detection can fire
  /// again as the driver weaves back, and "Rerouting" three times in a minute
  /// is noise, not guidance.
  static const Duration rerouteQuiet = Duration(seconds: 30);

  /// 'en' or 'hi' — the language of the phrases this builds.
  String language;

  String? _stepKey;
  bool _farDone = false;
  bool _nearDone = false;
  bool _arrivedDone = false;
  bool _departDone = false;
  DateTime? _lastReroute;

  bool get _hi => language == VoiceLanguage.hindi;

  /// Forget everything announced. Call when the route is replaced (a reroute or
  /// a new leg), so the new route's first manoeuvre is announced afresh.
  void reset() {
    _stepKey = null;
    _farDone = false;
    _nearDone = false;
    _arrivedDone = false;
    _departDone = false;
  }

  /// The opening instruction ("Head north on ..."), said once as the drive
  /// begins: it is where to go now, not a turn to count down to. [reset]
  /// allows it again for a new leg.
  String? depart(NavStep first) {
    if (_departDone) return null;
    _departDone = true;
    final phrase = spokenInstruction(first.instruction, language: language);
    return phrase.isEmpty ? null : phrase;
  }

  /// The phrase to speak now, or null if nothing new should be said.
  ///
  /// [step] is the manoeuvre AHEAD — the step after the one being driven — and
  /// [toManeuverM] the distance to where it begins. (The step being driven
  /// describes the turn that led onto it, already taken.)
  ///
  /// Each manoeuvre gets at most two prompts, and each is spoken once. A GPS fix
  /// arrives every second or two, so without that memory every update inside the
  /// window would repeat the instruction.
  String? update({
    required NavStep? step,
    required double toManeuverM,
    required bool arrived,
    required String destinationLabel,
  }) {
    if (arrived) {
      if (_arrivedDone) return null;
      _arrivedDone = true;
      return _hi
          ? 'आप ${spokenLabel(destinationLabel, language)} पर पहुँच गए हैं'
          : 'You have arrived at the ${spokenLabel(destinationLabel, language)}';
    }
    if (step == null || !toManeuverM.isFinite) return null;

    // A step is identified by where it starts and what it says. Step objects are
    // replaced wholesale on every route refresh, so object identity would treat
    // an unchanged step as new and announce it again. (The step ahead starts
    // at its junction, which a refresh from the driver's position does not
    // move.)
    final key = '${step.start.latitude.toStringAsFixed(5)},'
        '${step.start.longitude.toStringAsFixed(5)}|${step.instruction}';
    if (key != _stepKey) {
      _stepKey = key;
      _farDone = false;
      _nearDone = false;
    }

    final phrase = spokenInstruction(step.instruction, language: language);
    if (phrase.isEmpty) return null;

    if (!_nearDone && toManeuverM <= nearM) {
      // The near prompt supersedes the far one: if a manoeuvre comes up too fast
      // for both (a short street, a fix that skipped the window), say it once.
      _nearDone = true;
      _farDone = true;
      return phrase;
    }
    if (!_farDone && toManeuverM <= farM) {
      _farDone = true;
      final distance = spokenDistance(toManeuverM, language: language);
      return _hi ? '$distance बाद, $phrase' : 'In $distance, ${_lowerFirst(phrase)}';
    }
    return null;
  }

  /// "Rerouting", once per [rerouteQuiet].
  String? rerouted({DateTime? now}) {
    final t = now ?? DateTime.now();
    final last = _lastReroute;
    if (last != null && t.difference(last) < rerouteQuiet) return null;
    _lastReroute = t;
    return _hi ? 'नया रास्ता ढूँढा जा रहा है' : 'Rerouting';
  }

  /// Said as the driver reaches a toll road, alongside the on-screen prompt.
  static String tollPhrase(String language) => language == VoiceLanguage.hindi
      ? 'आप टोल रोड पर हैं। टोल देने के बाद उसे ऐप में जोड़ें।'
      : 'You are on a toll road. Add the toll in the app when you pay it.';

  /// A short sample for the settings screen, in [language].
  static String samplePhrase(String language) => language == VoiceLanguage.hindi
      ? 'आवाज़ से रास्ता बताना चालू है। 200 मीटर बाद, बाएँ मुड़ें।'
      : 'Voice guidance is on. In 200 metres, turn left.';

  /// "412" -> "400 metres"; "1260" -> "1.3 kilometres" (Hindi: मीटर, किलोमीटर).
  ///
  /// Rounded, because "In 412 metres" is precision nobody driving can use, and
  /// spelled out, because an engine reads "m" as the letter M.
  static String spokenDistance(double metres, {String language = VoiceLanguage.english}) {
    final hi = language == VoiceLanguage.hindi;
    if (metres >= 1000) {
      final km = (metres / 100).round() / 10;
      final text = km == km.roundToDouble() ? km.toStringAsFixed(0) : km.toStringAsFixed(1);
      return hi ? '$text किलोमीटर' : '$text kilometre${km == 1 ? '' : 's'}';
    }
    final rounded = metres < 100
        ? ((metres / 10).round() * 10)
        : ((metres / 50).round() * 50);
    final m = rounded < 10 ? 10 : rounded;
    return hi ? '$m मीटर' : '$m metres';
  }

  static const _hindiLabels = <String, String>{
    'pickup': 'पिकअप',
    'drop': 'ड्रॉप',
    'customer': 'ग्राहक',
    'receiver': 'रिसीवर',
    'sender': 'भेजने वाले',
    'start point': 'शुरुआती जगह',
  };

  /// How a leg label is said: "pickup", "stop 2" — or in Hindi, "पिकअप", "स्टॉप 2".
  static String spokenLabel(String label, String language) {
    final l = label.trim().toLowerCase();
    if (language != VoiceLanguage.hindi) return l;
    final stop = RegExp(r'^stop\s+(\d+)$').firstMatch(l);
    if (stop != null) return 'स्टॉप ${stop.group(1)}';
    return _hindiLabels[l] ?? label.trim();
  }

  static const _abbreviations = <String, String>{
    'Rd': 'Road',
    'Hwy': 'Highway',
    'Nr': 'Near',
    'Opp': 'Opposite',
    'Ave': 'Avenue',
    'Ln': 'Lane',
  };

  /// Makes a Directions instruction speakable.
  ///
  /// Speech engines read "Rd" as "R D" and "NH48" as a run of letters, so common
  /// road abbreviations are expanded. Road names stay in Latin script inside
  /// Google's Hindi instructions too, so the same expansions apply there. Two are
  /// handled specially because a blind expansion is wrong on real Indian roads:
  ///
  ///  * "St" is Street at the end of a name ("Relief St") but Saint before one
  ///    ("St. Xavier's College Road" — a real Ahmedabad road).
  ///  * "NH48" has no word boundary between the letters and the number, so a
  ///    plain \bNH\b never matches it.
  static String spokenInstruction(String raw, {String language = VoiceLanguage.english}) {
    var s = raw.trim();
    if (s.isEmpty) return s;
    final hi = language == VoiceLanguage.hindi;

    // Highways first: "NH48", "NH 48", "SH-17" -> "National Highway 48".
    s = s.replaceAllMapped(
      RegExp(r'\b(NH|SH)[\s-]*(\d+)'),
      (m) => hi
          ? '${m[1] == 'NH' ? 'नेशनल' : 'स्टेट'} हाईवे ${m[2]}'
          : '${m[1] == 'NH' ? 'National' : 'State'} Highway ${m[2]}',
    );

    // Saint before a capitalised name, Street everywhere else.
    s = s.replaceAllMapped(RegExp(r"\bSt\.?(?=\s+[A-Z])"), (_) => 'Saint');
    s = s.replaceAllMapped(RegExp(r'\bSt\b\.?'), (_) => 'Street');

    _abbreviations.forEach((abbr, full) {
      // Whole words only, with or without a trailing full stop, so an already
      // expanded word is never mangled.
      //
      // Concatenated raw strings, because raw strings cannot interpolate. In a
      // normal Dart string a backslash-b is a BACKSPACE character, not a regex
      // word boundary, so an interpolated pattern silently never matches.
      s = s.replaceAllMapped(RegExp(r'\b' + abbr + r'\b\.?'), (_) => full);
    });
    return s.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String _lowerFirst(String s) =>
      s.isEmpty ? s : s[0].toLowerCase() + s.substring(1);
}

class VoiceGuide {
  static const mutedKey = 'nav_voice_muted';
  static const languageKey = 'nav_voice_language';

  final FlutterTts _tts = FlutterTts();
  bool _ready = false;
  bool muted = false;

  /// The language the driver chose.
  String preferredLanguage = VoiceLanguage.english;

  /// The language actually being spoken: [preferredLanguage], unless this phone
  /// has no voice for it — then English, rather than Hindi text read out
  /// letter by letter by an English voice.
  String language = VoiceLanguage.english;

  /// Whether this phone can speak Hindi. Null until [init] has asked.
  bool? hindiAvailable;

  /// Configures the engine and restores the driver's voice settings.
  ///
  /// Every call is guarded: a device with no speech engine, or a test
  /// environment with no plugin, must leave navigation fully working — just
  /// silent.
  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      muted = prefs.getBool(mutedKey) ?? false;
      preferredLanguage = prefs.getString(languageKey) == VoiceLanguage.hindi
          ? VoiceLanguage.hindi
          : VoiceLanguage.english;
    } catch (_) {}

    try {
      await _tts.setSpeechRate(0.5);
      await _tts.setVolume(1.0);
      // iOS: lower the driver's music while a prompt plays instead of stopping
      // it or talking over it. Android gets the same through `focus: true`
      // (AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK), which the plugin releases when
      // the utterance finishes, so music returns to full volume afterwards.
      await _tts.setIosAudioCategory(
        IosTextToSpeechAudioCategory.playback,
        [IosTextToSpeechAudioCategoryOptions.duckOthers],
        IosTextToSpeechAudioMode.voicePrompt,
      );
      await _applyLanguage();
      _ready = true;
    } catch (_) {
      _ready = false;
    }
  }

  /// Chooses the voice for [preferredLanguage], falling back to English.
  Future<void> _applyLanguage() async {
    hindiAvailable = await _available('hi-IN');
    if (preferredLanguage == VoiceLanguage.hindi && hindiAvailable == true) {
      await _tts.setLanguage('hi-IN');
      language = VoiceLanguage.hindi;
      return;
    }
    // Indian English where the device has it: it pronounces local road and
    // place names far better than the US voice.
    final hasIndian = await _available('en-IN');
    await _tts.setLanguage(hasIndian ? 'en-IN' : 'en-US');
    language = VoiceLanguage.english;
  }

  Future<bool> _available(String locale) async {
    try {
      final v = await _tts.isLanguageAvailable(locale);
      return v == true || v == 1;
    } catch (_) {
      return false;
    }
  }

  Future<void> setMuted(bool value) async {
    muted = value;
    if (value) await stop();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(mutedKey, value);
    } catch (_) {}
  }

  /// Saves [code] as the driver's language and switches the voice to it.
  /// Returns the language that will actually be spoken.
  Future<String> setLanguage(String code) async {
    preferredLanguage = code == VoiceLanguage.hindi ? VoiceLanguage.hindi : VoiceLanguage.english;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(languageKey, preferredLanguage);
    } catch (_) {}
    try {
      await stop();
      await _applyLanguage();
    } catch (_) {}
    return language;
  }

  /// Speaks [text], replacing anything still being said.
  ///
  /// A newer instruction always wins: a half-spoken prompt for a turn the driver
  /// has already taken is worse than no prompt at all. [evenIfMuted] is for the
  /// settings screen's sample, which the driver asked to hear.
  Future<void> say(String text, {bool evenIfMuted = false}) async {
    if ((muted && !evenIfMuted) || !_ready || text.isEmpty) return;
    try {
      await _tts.stop();
      await _tts.speak(text, focus: true);
    } catch (_) {}
  }

  Future<void> stop() async {
    try { await _tts.stop(); } catch (_) {}
  }

  Future<void> dispose() => stop();
}

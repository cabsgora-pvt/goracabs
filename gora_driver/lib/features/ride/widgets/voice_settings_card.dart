import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import 'voice_guide.dart';

/// Voice guidance settings: on/off, language, and a sample to hear it.
///
/// Voice could only be muted from a button on the navigation map, in English,
/// with no way to check it worked before a trip. The switch here is the same
/// setting as that button, so either place changes both.
class VoiceSettingsCard extends StatefulWidget {
  const VoiceSettingsCard({super.key});

  @override
  State<VoiceSettingsCard> createState() => _VoiceSettingsCardState();
}

class _VoiceSettingsCardState extends State<VoiceSettingsCard> {
  final VoiceGuide _voice = VoiceGuide();
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _voice.init().then((_) { if (mounted) setState(() => _loaded = true); });
  }

  @override
  void dispose() {
    _voice.dispose();
    super.dispose();
  }

  Future<void> _setOn(bool on) async {
    await _voice.setMuted(!on);
    if (mounted) setState(() {});
  }

  Future<void> _setLanguage(String code) async {
    await _voice.setLanguage(code);
    if (!mounted) return;
    setState(() {});
    // Straight away, in the new voice, so the driver hears what they picked.
    await _voice.say(NavAnnouncer.samplePhrase(_voice.language), evenIfMuted: true);
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final on = !_voice.muted;
    final hindiMissing = _voice.preferredLanguage == VoiceLanguage.hindi && _voice.language != VoiceLanguage.hindi;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 12),
      decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
            child: Icon(on ? Icons.record_voice_over_rounded : Icons.voice_over_off_rounded, size: 20, color: AppColors.primary),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Voice guidance', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: onSurface)),
            Text('Spoken turn-by-turn directions while navigating',
              style: TextStyle(fontSize: 11, color: AppColors.textGrey)),
          ])),
          Switch(
            value: on,
            onChanged: _loaded ? _setOn : null,
            activeColor: AppColors.primary,
          ),
        ]),
        const SizedBox(height: 8),
        Text('Language', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textGrey)),
        const SizedBox(height: 6),
        Wrap(spacing: 8, children: [
          for (final code in const [VoiceLanguage.english, VoiceLanguage.hindi])
            ChoiceChip(
              label: Text(VoiceLanguage.label(code)),
              selected: _voice.preferredLanguage == code,
              onSelected: _loaded ? (_) => _setLanguage(code) : null,
              selectedColor: AppColors.primary.withOpacity(0.15),
            ),
        ]),
        if (hindiMissing)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.info_outline, size: 16, color: AppColors.orange),
              const SizedBox(width: 6),
              Expanded(child: Text(
                'This phone has no Hindi voice installed, so guidance stays in English. '
                'Add Hindi in the phone\'s Text-to-speech settings.',
                style: TextStyle(fontSize: 11.5, color: AppColors.textGrey),
              )),
            ]),
          ),
        const SizedBox(height: 4),
        TextButton.icon(
          onPressed: _loaded
              ? () => _voice.say(NavAnnouncer.samplePhrase(_voice.language), evenIfMuted: true)
              : null,
          icon: const Icon(Icons.play_circle_outline, size: 20),
          label: const Text('Play a sample'),
        ),
      ]),
    );
  }
}
